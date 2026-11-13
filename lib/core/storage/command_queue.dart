import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';
import 'realtime_cache.dart';

/// 指令状态。字符串值直接落库，增删时保持稳定。
enum CommandStatus {
  pending,
  sending,
  sent,
  failed,
  cancelled;

  static CommandStatus parse(String? value) {
    return CommandStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => CommandStatus.pending,
    );
  }

  bool get isFinished => this == sent || this == cancelled;
}

/// 一条本地指令记录。
class QueuedCommand {
  const QueuedCommand({
    required this.id,
    required this.serverId,
    required this.deviceId,
    required this.type,
    required this.attributes,
    required this.status,
    required this.attempts,
    required this.createdAt,
    required this.updatedAt,
    this.lastError,
  });

  final int id;
  final String serverId;
  final int deviceId;
  final String type;
  final Map<String, dynamic> attributes;
  final CommandStatus status;
  final int attempts;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get canRetry =>
      status == CommandStatus.pending || status == CommandStatus.failed;

  bool get canCancel =>
      status == CommandStatus.pending || status == CommandStatus.failed;
}

/// 指令队列：先落库，再发送。
class CommandQueue {
  const CommandQueue(this._db);

  final AppDatabase _db;

  Future<QueuedCommand> enqueue({
    required String serverId,
    required int deviceId,
    required String type,
    Map<String, dynamic> attributes = const {},
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = await _db.into(_db.pendingCommands).insert(
          PendingCommandsCompanion.insert(
            serverId: serverId,
            deviceId: deviceId,
            type: type,
            attributes: Value(jsonEncode(attributes)),
            createdAt: now,
            updatedAt: now,
          ),
        );
    final row = await (_db.select(_db.pendingCommands)
          ..where((table) => table.id.equals(id)))
        .getSingle();
    return _toModel(row);
  }

  Future<List<QueuedCommand>> list(
    String serverId, {
    int? deviceId,
    int limit = 100,
  }) async {
    final query = _db.select(_db.pendingCommands)
      ..where((table) => table.serverId.equals(serverId))
      ..orderBy([(table) => OrderingTerm.desc(table.createdAt)])
      ..limit(limit);
    if (deviceId != null) {
      query.where((table) => table.deviceId.equals(deviceId));
    }
    return (await query.get()).map(_toModel).toList(growable: false);
  }

  /// 需要自动重试的记录：仍为 pending 且未超过最大次数。
  ///
  /// 非重试类失败（401/403/参数错误）会落为 `failed` 终态，只能由用户
  /// 手动重试（[resetForRetry]），不会被轮询自动重发。
  Future<List<QueuedCommand>> retryable(
    String serverId, {
    int maxAttempts = 6,
  }) async {
    final rows = await (_db.select(_db.pendingCommands)
          ..where(
            (table) =>
                table.serverId.equals(serverId) &
                table.status.equals(CommandStatus.pending.name) &
                table.attempts.isSmallerThanValue(maxAttempts),
          )
          ..orderBy([(table) => OrderingTerm.asc(table.createdAt)]))
        .get();
    return rows.map(_toModel).toList(growable: false);
  }

  Future<int> pendingCount(String serverId) async {
    final count = _db.pendingCommands.id.count();
    final query = _db.selectOnly(_db.pendingCommands)
      ..addColumns([count])
      ..where(
        _db.pendingCommands.serverId.equals(serverId) &
            _db.pendingCommands.status.isIn([
              CommandStatus.pending.name,
              CommandStatus.failed.name,
              CommandStatus.sending.name,
            ]),
      );
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<void> markSending(int id) => _update(
        id,
        status: CommandStatus.sending,
      );

  Future<void> markSent(int id) => _update(
        id,
        status: CommandStatus.sent,
        lastError: const Value(null),
      );

  Future<void> markFailed(
    int id, {
    required String error,
    required bool retryable,
  }) async {
    final current = await _byId(id);
    await _update(
      id,
      status: retryable ? CommandStatus.pending : CommandStatus.failed,
      attempts: (current?.attempts ?? 0) + 1,
      lastError: Value(error),
    );
  }

  Future<void> markCancelled(int id) => _update(
        id,
        status: CommandStatus.cancelled,
      );

  /// 离线等场景的「已入队」：保持 pending，但不消耗发送尝试次数。
  Future<void> markQueued(int id, {required String reason}) => _update(
        id,
        status: CommandStatus.pending,
        lastError: Value(reason),
      );

  /// 进程被杀时可能残留 `sending`；启动时恢复为 pending，避免永久卡住。
  ///
  /// 返回恢复的记录数，便于测试与诊断。
  Future<int> recoverInterrupted(String serverId) {
    return (_db.update(_db.pendingCommands)
          ..where(
            (table) =>
                table.serverId.equals(serverId) &
                table.status.equals(CommandStatus.sending.name),
          ))
        .write(
      PendingCommandsCompanion(
        status: Value(CommandStatus.pending.name),
        lastError: const Value('上次发送未完成，已重新入队'),
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  Future<void> resetForRetry(int id) => _update(
        id,
        status: CommandStatus.pending,
        attempts: 0,
        lastError: const Value(null),
      );

  Future<void> clearFinished(String serverId) async {
    await (_db.delete(_db.pendingCommands)
          ..where(
            (table) =>
                table.serverId.equals(serverId) &
                table.status.isIn([
                  CommandStatus.sent.name,
                  CommandStatus.cancelled.name,
                  CommandStatus.failed.name,
                ]),
          ))
        .go();
  }

  Future<void> clearServer(String serverId) async {
    await (_db.delete(_db.pendingCommands)
          ..where((table) => table.serverId.equals(serverId)))
        .go();
  }

  /// 清空所有服务器的指令记录。
  Future<void> clearAll() async {
    await _db.delete(_db.pendingCommands).go();
  }

  Future<QueuedCommand?> _byId(int id) async {
    final row = await (_db.select(_db.pendingCommands)
          ..where((table) => table.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : _toModel(row);
  }

  Future<void> _update(
    int id, {
    required CommandStatus status,
    int? attempts,
    Value<String?> lastError = const Value.absent(),
  }) async {
    await (_db.update(_db.pendingCommands)
          ..where((table) => table.id.equals(id)))
        .write(
      PendingCommandsCompanion(
        status: Value(status.name),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        lastError: lastError,
        updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
  }

  static QueuedCommand _toModel(PendingCommand row) {
    Map<String, dynamic> attributes = const {};
    try {
      final decoded = jsonDecode(row.attributes);
      if (decoded is Map) {
        attributes = decoded.cast<String, dynamic>();
      }
    } catch (_) {
      // payload 损坏时按空属性处理，避免阻塞队列。
    }
    return QueuedCommand(
      id: row.id,
      serverId: row.serverId,
      deviceId: row.deviceId,
      type: row.type,
      attributes: attributes,
      status: CommandStatus.parse(row.status),
      attempts: row.attempts,
      lastError: row.lastError,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
    );
  }
}

/// 指令发送结果，用于区分「已发送」与「已入队」。
enum CommandDispatch { sent, queued }

final commandQueueProvider = Provider<CommandQueue>((ref) {
  return CommandQueue(ref.watch(appDatabaseProvider));
});
