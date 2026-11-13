import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/command_queue.dart';
import '../../../domain/entities/device_command.dart';
import '../../../domain/failures.dart';
import '../../auth/application/session_controller.dart';
import '../../realtime/application/realtime_controller.dart';

/// 指令队列视图状态。
class CommandState {
  const CommandState({
    this.items = const [],
    this.flushing = false,
  });

  final List<QueuedCommand> items;
  final bool flushing;

  List<QueuedCommand> forDevice(int deviceId) => items
      .where((item) => item.deviceId == deviceId)
      .toList(growable: false);

  int get pendingCount => items
      .where(
        (item) =>
            item.status == CommandStatus.pending ||
            item.status == CommandStatus.failed ||
            item.status == CommandStatus.sending,
      )
      .length;

  CommandState copyWith({
    List<QueuedCommand>? items,
    bool? flushing,
  }) {
    return CommandState(
      items: items ?? this.items,
      flushing: flushing ?? this.flushing,
    );
  }
}

/// 指令发送与重试。
///
/// 设计要点：
/// - 指令先写本地队列，再请求服务器，避免点击后进程被杀导致“不知道发没发”；
/// - 网络 / 超时 / 5xx 自动重试（30 秒一次，最多 6 次）；
/// - 401 / 400 / 403 直接失败，避免无意义重试；
/// - WebSocket 重连成功时立即补发。
class CommandController extends AsyncNotifier<CommandState> {
  static const _retryInterval = Duration(seconds: 30);
  static const _maxAttempts = 6;

  Timer? _timer;
  String? _serverId;
  bool _flushing = false;
  bool _disposed = false;

  @override
  Future<CommandState> build() async {
    _disposed = false;
    _timer?.cancel();
    _timer = null;

    ref.onDispose(() {
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });

    // 网络恢复后立即补发，不等 30 秒轮询。
    ref.listen(realtimeProvider, (previous, next) {
      final wasConnected = previous?.valueOrNull?.connected ?? false;
      final connected = next.valueOrNull?.connected ?? false;
      if (!wasConnected && connected) {
        unawaited(flush());
      }
    });

    final queue = ref.watch(commandQueueProvider);

    final session = await ref.watch(sessionProvider.future);
    final server = session.server;
    _serverId = server?.id;

    if (server == null || !session.isAuthenticated) {
      return const CommandState();
    }

    _timer = Timer.periodic(
      _retryInterval,
      (_) => unawaited(flush()),
    );

    // 上次进程被杀可能留下 sending，先恢复再加载列表。
    await queue.recoverInterrupted(server.id);

    final items = await queue.list(server.id);
    return CommandState(items: items);
  }

  /// 立即发送；网络类错误自动入队并返回 [CommandDispatch.queued]。
  Future<CommandDispatch> send({
    required int deviceId,
    required DeviceCommandType type,
    Map<String, dynamic> attributes = const {},
  }) async {
    final serverId = _serverId;
    final api = ref.read(traccarApiProvider);
    if (serverId == null || api == null) {
      throw const AppFailure(
        FailureKind.unauthorized,
        '登录已失效，无法发送指令',
      );
    }

    final queue = ref.read(commandQueueProvider);
    final row = await queue.enqueue(
      serverId: serverId,
      deviceId: deviceId,
      type: type.apiType,
      attributes: attributes,
    );
    await _reload();

    // 已知离线时跳过必然超时的请求，且不消耗重试次数。
    final offline = ref.read(sessionProvider).valueOrNull?.offline ?? false;
    if (offline) {
      await queue.markQueued(
        row.id,
        reason: '当前离线，指令已加入队列',
      );
      await _reload();
      return CommandDispatch.queued;
    }

    try {
      await api.sendCommand(
        deviceId: deviceId,
        type: type.apiType,
        attributes: attributes,
      );
      await queue.markSent(row.id);
      await _reload();
      return CommandDispatch.sent;
    } on AppFailure catch (failure) {
      await queue.markFailed(
        row.id,
        error: failure.message,
        retryable: failure.isRetryable,
      );
      await _reload();
      if (!failure.isRetryable) rethrow;
      return CommandDispatch.queued;
    }
  }

  /// 发送队列中所有可重试指令。
  Future<void> flush() async {
    if (_flushing) return;
    final serverId = _serverId;
    final api = ref.read(traccarApiProvider);
    if (serverId == null || api == null) return;

    // 已知离线时不要把重试次数耗光；等网络恢复后再补发。
    final offline = ref.read(sessionProvider).valueOrNull?.offline ?? false;
    if (offline) return;

    _flushing = true;
    final queue = ref.read(commandQueueProvider);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.copyWith(flushing: true));
    }

    try {
      final items = await queue.retryable(
        serverId,
        maxAttempts: _maxAttempts,
      );
      for (final item in items) {
        await queue.markSending(item.id);
        try {
          await api.sendCommand(
            deviceId: item.deviceId,
            type: item.type,
            attributes: item.attributes,
          );
          await queue.markSent(item.id);
        } on AppFailure catch (failure) {
          await queue.markFailed(
            item.id,
            error: failure.message,
            retryable: failure.isRetryable,
          );
          if (failure.isUnauthorized) {
            unawaited(ref.read(sessionProvider.notifier).invalidate());
            break;
          }
        } catch (error) {
          await queue.markFailed(
            item.id,
            error: error.toString(),
            retryable: true,
          );
        }
      }
    } finally {
      _flushing = false;
      await _reload();
    }
  }

  Future<void> retry(int id) async {
    final queue = ref.read(commandQueueProvider);
    await queue.resetForRetry(id);
    await flush();
    await _reload();
  }

  Future<void> cancel(int id) async {
    await ref.read(commandQueueProvider).markCancelled(id);
    await _reload();
  }

  Future<void> clearFinished() async {
    final serverId = _serverId;
    if (serverId == null) return;
    await ref.read(commandQueueProvider).clearFinished(serverId);
    await _reload();
  }

  Future<void> _reload() async {
    if (_disposed) return;
    final serverId = _serverId;
    if (serverId == null) return;
    final items = await ref.read(commandQueueProvider).list(serverId);
    if (_disposed) return;
    state = AsyncData(
      CommandState(items: items, flushing: _flushing),
    );
  }
}

final commandProvider =
    AsyncNotifierProvider<CommandController, CommandState>(
  CommandController.new,
);
