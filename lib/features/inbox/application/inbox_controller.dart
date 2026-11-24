import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/failure_localizer.dart';
import '../../../core/localization/localization.dart';
import '../../../core/push/inbox_api.dart';
import '../../../core/push/inbox_store.dart';
import '../../../domain/entities/inbox_message.dart';
import '../../../domain/failures.dart';
import '../../auth/application/session_controller.dart';

/// 收件箱状态。
class InboxState {
  const InboxState({
    this.messages = const [],
    this.readIds = const {},
    this.syncing = false,
    this.error,
    this.gatewayMissing = false,
    this.cursor,
  });

  final List<InboxMessage> messages;

  /// 本机已读的消息 id（按 server+user 隔离持久化）。
  final Set<String> readIds;

  final bool syncing;

  /// 本地化后的错误文案，供列表页展示。
  final String? error;

  /// 未配置 `PUSH_GATEWAY_URL`：没有可同步的服务端，界面只做说明。
  final bool gatewayMissing;

  final String? cursor;

  bool get isEmpty => messages.isEmpty;

  int get unread =>
      messages
          .where((m) => !m.isCommandPending && !readIds.contains(m.id))
          .length;

  bool isUnread(InboxMessage message) =>
      !message.isCommandPending && !readIds.contains(message.id);

  InboxState copyWith({
    List<InboxMessage>? messages,
    Set<String>? readIds,
    bool? syncing,
    String? error,
    bool clearError = false,
    bool? gatewayMissing,
    String? cursor,
  }) {
    return InboxState(
      messages: messages ?? this.messages,
      readIds: readIds ?? this.readIds,
      syncing: syncing ?? this.syncing,
      error: clearError ? null : (error ?? this.error),
      gatewayMissing: gatewayMissing ?? this.gatewayMissing,
      cursor: cursor ?? this.cursor,
    );
  }
}

/// 服务端主动下发的消息。
///
/// 设计取舍见 `docs/17-adr-downlink.md`：推送负责唤醒，REST 收件箱负责
/// 持久化与回执，不引入 MQTT 长连接。
class InboxController extends AsyncNotifier<InboxState> {
  static const int _pageSize = 50;

  bool _syncing = false;

  @override
  Future<InboxState> build() async {
    final session = await ref.watch(sessionProvider.future);
    final token = session.token;
    final server = session.server;
    final account = session.account;
    if (token == null || token.isEmpty || server == null || account == null) {
      return const InboxState();
    }

    final api = ref.watch(inboxApiProvider);
    if (!api.enabled) {
      return const InboxState(gatewayMissing: true);
    }

    final scope = _scope(server.id, account.id);
    final store = ref.watch(inboxStoreProvider);
    final readIds = await store.readReadIds(scope);
    try {
      // 冷启动不沿用旧游标：消息正文不落盘，需重新拉取最新一页才能展示。
      final page = await api.fetch(
        token: token,
        cursor: null,
        limit: _pageSize,
      );
      await _ackAll(api, token, page.messages);
      return InboxState(
        messages: page.messages,
        readIds: readIds,
        cursor: page.nextCursor,
      );
    } on AppFailure catch (failure) {
      return InboxState(
        readIds: readIds,
        error: failureMessage(ref.read(appLocalizationsProvider), failure),
      );
    } catch (error) {
      return InboxState(readIds: readIds, error: '$error');
    }
  }

  String _scope(String serverId, int userId) => '$serverId:$userId';

  /// 增量同步。`force` 为 true 时忽略游标，重新拉取当前页。
  Future<void> sync({bool force = false}) async {
    if (_syncing) return;
    final session = ref.read(sessionProvider).valueOrNull;
    final token = session?.token;
    final server = session?.server;
    final account = session?.account;
    if (token == null || token.isEmpty || server == null || account == null) {
      return;
    }

    final api = ref.read(inboxApiProvider);
    if (!api.enabled) {
      state = const AsyncData(InboxState(gatewayMissing: true));
      return;
    }

    final current = state.valueOrNull ?? const InboxState();
    _syncing = true;
    state = AsyncData(current.copyWith(syncing: true, clearError: true));
    final scope = _scope(server.id, account.id);
    final store = ref.read(inboxStoreProvider);

    try {
      final page = await api.fetch(
        token: token,
        cursor: force ? null : current.cursor,
        limit: _pageSize,
      );
      final merged = _resolvePending(_merge(current.messages, page.messages));
      final cursor = page.nextCursor ?? current.cursor;
      await _ackAll(api, token, page.messages);
      final readIds = await store.readReadIds(scope);
      state = AsyncData(
        current.copyWith(
          messages: merged,
          readIds: readIds,
          cursor: cursor,
          syncing: false,
          clearError: true,
        ),
      );
    } on AppFailure catch (failure) {
      state = AsyncData(
        current.copyWith(
          syncing: false,
          error: failureMessage(ref.read(appLocalizationsProvider), failure),
        ),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(syncing: false, error: '$error'));
    } finally {
      _syncing = false;
    }
  }

  Future<void> markRead(String id, {bool all = false}) async {
    final session = ref.read(sessionProvider).valueOrNull;
    final server = session?.server;
    final account = session?.account;
    final current = state.valueOrNull;
    if (server == null || account == null || current == null) return;

    final store = ref.read(inboxStoreProvider);
    final scope = _scope(server.id, account.id);
    final ids = await store.readReadIds(scope);
    if (all) {
      ids.addAll(current.messages.map((m) => m.id));
    } else {
      ids.add(id);
    }
    await store.writeReadIds(scope, ids);
    state = AsyncData(current.copyWith(readIds: ids));
  }

  Future<void> markAllRead() => markRead('', all: true);

  /// 记录一条本地「等待设备返回结果」占位消息。
  ///
  /// 占位消息不落盘、不计未读；收到同一设备的 `commandResult` 后自动移除，
  /// 超过 15 分钟也会清理，避免长期停留在列表里。
  void noteCommandDispatched({required int deviceId, required String command}) {
    final current = state.valueOrNull;
    if (current == null) return;
    final now = DateTime.now();
    final pending = InboxMessage(
      id: 'local-${now.microsecondsSinceEpoch}',
      kind: InboxKind.notice,
      data: {
        'eventType': 'commandPending',
        'deviceId': deviceId,
        'command': command,
      },
      createdAt: now,
    );
    state = AsyncData(
      current.copyWith(messages: [pending, ...current.messages]),
    );
  }

  /// 移除已被真实结果覆盖或超时的本地占位消息。
  List<InboxMessage> _resolvePending(List<InboxMessage> messages) {
    final results = messages.where((m) => m.isCommandResult).toList();
    final now = DateTime.now();
    return messages
        .where((message) {
          if (!message.isCommandPending) return true;
          final created = message.createdAt ?? now;
          if (now.difference(created) > const Duration(minutes: 15)) {
            return false;
          }
          return !results.any((result) {
            if (result.deviceId != message.deviceId) return false;
            final resultAt = result.createdAt ?? now;
            return !resultAt.isBefore(
              created.subtract(const Duration(minutes: 1)),
            );
          });
        })
        .toList(growable: false);
  }

  /// 投递回执失败不阻塞展示：消息会在下次同步时重新下发并被去重。
  Future<void> _ackAll(
    InboxApi api,
    String token,
    List<InboxMessage> list,
  ) async {
    for (final message in list) {
      try {
        await api.ack(token: token, id: message.id);
      } catch (_) {
        // 忽略：下次同步重试。
      }
    }
  }

  /// 合并新旧消息：按 id 去重，时间倒序。
  List<InboxMessage> _merge(
    List<InboxMessage> current,
    List<InboxMessage> incoming,
  ) {
    final byId = <String, InboxMessage>{
      for (final message in current) message.id: message,
      for (final message in incoming) message.id: message,
    };
    final merged =
        byId.values.toList()..sort((a, b) {
          final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });
    return merged;
  }
}

final inboxProvider = AsyncNotifierProvider<InboxController, InboxState>(
  InboxController.new,
);

/// 未读数：用于设置页角标与底部导航提示。
final inboxUnreadProvider = Provider<int>((ref) {
  return ref.watch(inboxProvider).valueOrNull?.unread ?? 0;
});
