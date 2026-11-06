import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/storage/app_database.dart';
import 'package:trackerone/core/storage/realtime_cache.dart';
import 'package:trackerone/domain/entities/models.dart';

void main() {
  late AppDatabase database;
  late RealtimeCache cache;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    cache = RealtimeCache(database);
  });

  tearDown(() => database.close());

  test('round trips devices and positions as JSON', () async {
    final device = Device(
      id: 7,
      name: 'Van',
      uniqueId: '12345678',
      status: 'online',
      lastUpdate: DateTime.utc(2026, 11, 4, 8, 30),
      category: 'van',
      attributes: const {'batteryLevel': 80},
    );
    final position = Position(
      id: 99,
      deviceId: 7,
      latitude: 39.9042,
      longitude: 116.4074,
      fixTime: DateTime.utc(2026, 11, 4, 8, 31),
      speedKnots: 12,
      course: 90,
      altitude: 43,
      accuracy: 5,
      attributes: const {'batteryLevel': 79},
    );

    await cache.saveSnapshot(
      serverId: 'server-a',
      devices: [device],
      positions: [position],
    );

    final cached = await cache.load('server-a');
    expect(cached.devices, hasLength(1));
    expect(cached.devices.single.name, 'Van');
    expect(cached.devices.single.category, 'van');
    expect(cached.positions.single.id, 99);
    expect(cached.positions.single.latitude, closeTo(39.9042, 1e-6));
    expect(cached.positions.single.batteryLevel, 79);
    expect(cached.updatedAt, isNotNull);
  });

  test('upsert replaces the latest position and keeps events', () async {
    final first = Position(
      id: 1,
      deviceId: 7,
      latitude: 1,
      longitude: 1,
      fixTime: DateTime.utc(2026, 11, 4, 8),
    );
    final second = Position(
      id: 2,
      deviceId: 7,
      latitude: 2,
      longitude: 2,
      fixTime: DateTime.utc(2026, 11, 4, 9),
    );
    final event = DeviceEvent(
      id: 555,
      deviceId: 7,
      type: 'geofenceEnter',
      eventTime: DateTime.utc(2026, 11, 4, 9),
    );

    await cache.upsertBatch(
      serverId: 'server-a',
      positions: [first],
      events: [event],
    );
    await cache.upsertBatch(serverId: 'server-a', positions: [second]);

    final cached = await cache.load('server-a');
    expect(cached.positions, hasLength(1));
    expect(cached.positions.single.id, 2);
    expect(cached.events.single.id, 555);
  });

  test('isolates data by server and clears one server only', () async {
    await cache.saveSnapshot(
      serverId: 'a',
      devices: const [
        Device(id: 1, name: 'A', uniqueId: '1', status: 'online'),
      ],
      positions: const [],
    );
    await cache.saveSnapshot(
      serverId: 'b',
      devices: const [
        Device(id: 2, name: 'B', uniqueId: '2', status: 'online'),
      ],
      positions: const [],
    );

    expect((await cache.load('a')).devices.single.name, 'A');
    expect((await cache.load('b')).devices.single.name, 'B');

    await cache.clear('a');
    expect((await cache.load('a')).isEmpty, isTrue);
    expect((await cache.load('b')).devices.single.name, 'B');
  });

  test('clearAll removes every server', () async {
    for (final id in ['a', 'b']) {
      await cache.saveSnapshot(
        serverId: id,
        devices: [
          Device(id: 1, name: id, uniqueId: id, status: 'online'),
        ],
        positions: const [],
      );
    }

    await cache.clearAll();

    expect((await cache.load('a')).isEmpty, isTrue);
    expect((await cache.load('b')).isEmpty, isTrue);
  });
}
