import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/models.dart';
import 'app_database.dart';

/// 离线可用的实时快照。
class CachedRealtime {
  const CachedRealtime({
    this.devices = const [],
    this.positions = const [],
    this.events = const [],
    this.updatedAt,
  });

  final List<Device> devices;
  final List<Position> positions;
  final List<DeviceEvent> events;
  final DateTime? updatedAt;

  bool get isEmpty => devices.isEmpty && positions.isEmpty && events.isEmpty;
}

/// 设备 / 最新位置 / 事件的本地缓存。
///
/// 写入使用 JSON payload：Traccar 增加字段时无需迁移数据库。
class RealtimeCache {
  const RealtimeCache(this._db);

  final AppDatabase _db;

  Future<CachedRealtime> load(String serverId) async {
    final deviceRows = await (_db.select(_db.cachedDevices)
          ..where((table) => table.serverId.equals(serverId)))
        .get();
    final positionRows = await (_db.select(_db.cachedPositions)
          ..where((table) => table.serverId.equals(serverId)))
        .get();
    final eventRows = await (_db.select(_db.cachedEvents)
          ..where((table) => table.serverId.equals(serverId))
          ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])
          ..limit(200))
        .get();

    var latest = 0;
    for (final row in deviceRows) {
      if (row.updatedAt > latest) latest = row.updatedAt;
    }
    for (final row in positionRows) {
      if (row.updatedAt > latest) latest = row.updatedAt;
    }
    for (final row in eventRows) {
      if (row.updatedAt > latest) latest = row.updatedAt;
    }

    return CachedRealtime(
      devices: deviceRows
          .map((row) => _decode(row.payload, Device.fromJson))
          .whereType<Device>()
          .toList(growable: false),
      positions: positionRows
          .map((row) => _decode(row.payload, Position.fromJson))
          .whereType<Position>()
          .toList(growable: false),
      events: eventRows
          .map((row) => _decode(row.payload, DeviceEvent.fromJson))
          .whereType<DeviceEvent>()
          .toList(growable: false),
      updatedAt: latest == 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(latest),
    );
  }

  Future<void> saveSnapshot({
    required String serverId,
    required Iterable<Device> devices,
    required Iterable<Position> positions,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _deleteSnapshotRows(serverId);
      await _db.batch((batch) {
        batch.insertAll(
          _db.cachedDevices,
          devices
              .map(
                (device) => CachedDevicesCompanion.insert(
                  serverId: serverId,
                  deviceId: device.id,
                  payload: jsonEncode(device.toJson()),
                  updatedAt: now,
                ),
              )
              .toList(growable: false),
          mode: InsertMode.insertOrReplace,
        );
        batch.insertAll(
          _db.cachedPositions,
          positions
              .map(
                (position) => CachedPositionsCompanion.insert(
                  serverId: serverId,
                  deviceId: position.deviceId,
                  payload: jsonEncode(position.toJson()),
                  updatedAt: now,
                ),
              )
              .toList(growable: false),
          mode: InsertMode.insertOrReplace,
        );
      });
    });
  }

  Future<void> upsertBatch({
    required String serverId,
    Iterable<Device> devices = const [],
    Iterable<Position> positions = const [],
    Iterable<DeviceEvent> events = const [],
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.batch((batch) {
      batch.insertAll(
        _db.cachedDevices,
        devices
            .map(
              (device) => CachedDevicesCompanion.insert(
                serverId: serverId,
                deviceId: device.id,
                payload: jsonEncode(device.toJson()),
                updatedAt: now,
              ),
            )
            .toList(growable: false),
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        _db.cachedPositions,
        positions
            .map(
              (position) => CachedPositionsCompanion.insert(
                serverId: serverId,
                deviceId: position.deviceId,
                payload: jsonEncode(position.toJson()),
                updatedAt: now,
              ),
            )
            .toList(growable: false),
        mode: InsertMode.insertOrReplace,
      );
      batch.insertAll(
        _db.cachedEvents,
        events
            .map(
              (event) => CachedEventsCompanion.insert(
                serverId: serverId,
                eventId: event.id,
                payload: jsonEncode(event.toJson()),
                updatedAt: now,
              ),
            )
            .toList(growable: false),
        mode: InsertMode.insertOrReplace,
      );
    });

    // 事件只保留 30 天，避免长期运行无限增长。
    final cutoff = DateTime.now()
        .subtract(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await (_db.delete(_db.cachedEvents)
          ..where(
            (table) =>
                table.serverId.equals(serverId) &
                table.updatedAt.isSmallerThanValue(cutoff),
          ))
        .go();
  }

  Future<void> clear(String serverId) async {
    await _db.transaction(() => _deleteServerRows(serverId));
  }

  /// 清空所有服务器的设备、位置与事件缓存。
  Future<void> clearAll() async {
    await _db.transaction(() async {
      await _db.delete(_db.cachedDevices).go();
      await _db.delete(_db.cachedPositions).go();
      await _db.delete(_db.cachedEvents).go();
    });
  }

  Future<void> _deleteSnapshotRows(String serverId) async {
    await (_db.delete(_db.cachedDevices)
          ..where((table) => table.serverId.equals(serverId)))
        .go();
    await (_db.delete(_db.cachedPositions)
          ..where((table) => table.serverId.equals(serverId)))
        .go();
  }

  Future<void> _deleteServerRows(String serverId) async {
    await (_db.delete(_db.cachedDevices)
          ..where((table) => table.serverId.equals(serverId)))
        .go();
    await (_db.delete(_db.cachedPositions)
          ..where((table) => table.serverId.equals(serverId)))
        .go();
    await (_db.delete(_db.cachedEvents)
          ..where((table) => table.serverId.equals(serverId)))
        .go();
  }

  static T? _decode<T>(
    String payload,
    T Function(Map<String, dynamic>) parse,
  ) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      return parse(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }
}

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final realtimeCacheProvider = Provider<RealtimeCache>((ref) {
  return RealtimeCache(ref.watch(appDatabaseProvider));
});
