import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// 设备快照。`payload` 保存 Traccar JSON，避免服务端字段变化时迁移表结构。
class CachedDevices extends Table {
  TextColumn get serverId => text()();
  IntColumn get deviceId => integer()();
  TextColumn get payload => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {serverId, deviceId};
}

/// 每台设备只保留最新位置，用于离线地图。
class CachedPositions extends Table {
  TextColumn get serverId => text()();
  IntColumn get deviceId => integer()();
  TextColumn get payload => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {serverId, deviceId};
}

/// 最近事件；按事件 id 去重。
class CachedEvents extends Table {
  TextColumn get serverId => text()();
  IntColumn get eventId => integer()();
  TextColumn get payload => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {serverId, eventId};
}

/// 待发送 / 已发送的 Traccar 指令。
///
/// 指令先落库再请求，网络不可用时保持 [CommandStatus.pending]，
/// 恢复后由 [CommandController] 自动重试，避免用户重复点击。
class PendingCommands extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text()();
  IntColumn get deviceId => integer()();
  TextColumn get type => text()();
  TextColumn get attributes => text().withDefault(const Constant('{}'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}

@DriftDatabase(
  tables: [CachedDevices, CachedPositions, CachedEvents, PendingCommands],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(pendingCommands);
          }
        },
      );

  static QueryExecutor _open() {
    return LazyDatabase(() async {
      final directory = await getApplicationSupportDirectory();
      final file = File(p.join(directory.path, 'trackerone.sqlite'));
      return NativeDatabase(file);
    });
  }
}
