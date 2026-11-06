import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/storage/app_database.dart';
import 'package:trackerone/core/storage/command_queue.dart';

void main() {
  late AppDatabase database;
  late CommandQueue queue;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    queue = CommandQueue(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('enqueue persists command and starts as pending', () async {
    final command = await queue.enqueue(
      serverId: 's1',
      deviceId: 7,
      type: 'positionSingle',
    );

    expect(command.id, greaterThan(0));
    expect(command.status, CommandStatus.pending);
    expect(command.attempts, 0);
    expect(command.attributes, isEmpty);

    final items = await queue.list('s1');
    expect(items, hasLength(1));
    expect(items.single.deviceId, 7);
    expect(items.single.type, 'positionSingle');
  });

  test('enqueue keeps attributes and isolates servers', () async {
    await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionPeriodic',
      attributes: const {'frequency': 60},
    );
    await queue.enqueue(serverId: 's2', deviceId: 2, type: 'message');

    final first = await queue.list('s1');
    expect(first.single.attributes['frequency'], 60);
    expect(await queue.list('s2'), hasLength(1));
  });

  test('retryable only returns pending below attempt limit', () async {
    final sent = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final failed = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final exhausted = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );

    await queue.markSent(sent.id);
    await queue.markFailed(failed.id, error: 'offline', retryable: true);
    for (var i = 0; i < 6; i++) {
      await queue.markFailed(
        exhausted.id,
        error: 'offline',
        retryable: true,
      );
    }

    final items = await queue.retryable('s1');
    expect(items.map((item) => item.id), [failed.id]);
  });

  test('non retryable failure becomes failed and is not retried', () async {
    final command = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );

    await queue.markFailed(command.id, error: 'forbidden', retryable: false);

    final items = await queue.list('s1');
    expect(items.single.status, CommandStatus.failed);
    expect(items.single.lastError, 'forbidden');
    expect(await queue.retryable('s1'), isEmpty);
  });

  test('retry resets attempts and status', () async {
    final command = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    await queue.markFailed(command.id, error: 'timeout', retryable: false);

    await queue.resetForRetry(command.id);

    final items = await queue.list('s1');
    expect(items.single.status, CommandStatus.pending);
    expect(items.single.attempts, 0);
    expect(items.single.lastError, isNull);
  });

  test('cancel and clear finished', () async {
    final cancelled = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final sent = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final pending = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );

    await queue.markCancelled(cancelled.id);
    await queue.markSent(sent.id);
    await queue.clearFinished('s1');

    final items = await queue.list('s1');
    expect(items.map((item) => item.id), [pending.id]);
  });

  test('pending count includes pending, failed and sending', () async {
    final pending = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final failed = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final sending = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );
    final sent = await queue.enqueue(
      serverId: 's1',
      deviceId: 1,
      type: 'positionSingle',
    );

    await queue.markFailed(failed.id, error: 'x', retryable: false);
    await queue.markSending(sending.id);
    await queue.markSent(sent.id);

    expect(await queue.pendingCount('s1'), 3);
    expect(pending.status, CommandStatus.pending);
  });

  test('clearServer removes every command for that server', () async {
    await queue.enqueue(serverId: 's1', deviceId: 1, type: 'positionSingle');
    await queue.enqueue(serverId: 's2', deviceId: 1, type: 'positionSingle');

    await queue.clearServer('s1');

    expect(await queue.list('s1'), isEmpty);
    expect(await queue.list('s2'), hasLength(1));
  });

  test('clearAll removes commands for every server', () async {
    await queue.enqueue(serverId: 's1', deviceId: 1, type: 'positionSingle');
    await queue.enqueue(serverId: 's2', deviceId: 1, type: 'positionSingle');

    await queue.clearAll();

    expect(await queue.list('s1'), isEmpty);
    expect(await queue.list('s2'), isEmpty);
  });
}
