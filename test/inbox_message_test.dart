import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/entities/inbox_message.dart';

void main() {
  group('InboxMessage.fromJson', () {
    test('parses the gateway contract payload', () {
      final message = InboxMessage.fromJson(const {
        'id': 'msg_123',
        'kind': 'command',
        'title': '指令：断油',
        'body': '调度要求对京A12345 断油',
        'data': {
          'deviceId': 12,
          'command': 'engineStop',
          'attributes': {'frequency': 30},
        },
        'createdAt': '2026-11-19T10:00:00Z',
        'expiresAt': '2026-11-19T11:00:00Z',
      });

      expect(message.id, 'msg_123');
      expect(message.kind, InboxKind.command);
      expect(message.title, '指令：断油');
      expect(message.body, '调度要求对京A12345 断油');
      expect(message.deviceId, 12);
      expect(message.command, 'engineStop');
      expect(message.commandAttributes, {'frequency': 30});
      expect(message.hasCommand, isTrue);
      expect(message.createdAt, DateTime.utc(2026, 11, 19, 10));
      expect(message.expiresAt, DateTime.utc(2026, 11, 19, 11));
    });

    test('falls back to unknown kind and tolerates missing fields', () {
      final message = InboxMessage.fromJson(const {'id': 'x', 'kind': 'push'});

      expect(message.kind, InboxKind.unknown);
      expect(message.title, isNull);
      expect(message.body, isNull);
      expect(message.data, isEmpty);
      expect(message.deviceId, isNull);
      expect(message.command, isNull);
      expect(message.hasCommand, isFalse);
      expect(message.createdAt, isNull);
      expect(message.isExpired, isFalse);
    });

    test('accepts numeric strings and ignores malformed dates', () {
      final message = InboxMessage.fromJson(const {
        'id': 42,
        'kind': 'command',
        'data': {'deviceId': '7', 'command': 'rebootDevice'},
        'createdAt': 'not-a-date',
      });

      expect(message.id, '42');
      expect(message.deviceId, 7);
      expect(message.hasCommand, isTrue);
      expect(message.createdAt, isNull);
    });

    test('hasCommand requires command kind, device and command type', () {
      InboxMessage build({Object? kind, Object? deviceId, Object? command}) {
        return InboxMessage.fromJson({
          'id': 'm',
          'kind': kind,
          'data': {
            if (deviceId != null) 'deviceId': deviceId,
            if (command != null) 'command': command,
          },
        });
      }

      expect(
        build(kind: 'command', deviceId: 1, command: 'alarmArm').hasCommand,
        isTrue,
      );
      expect(
        build(kind: 'notice', deviceId: 1, command: 'alarmArm').hasCommand,
        isFalse,
      );
      expect(build(kind: 'command', command: 'alarmArm').hasCommand, isFalse);
      expect(build(kind: 'command', deviceId: 1).hasCommand, isFalse);
      expect(
        build(kind: 'command', deviceId: 1, command: '').hasCommand,
        isFalse,
      );
    });

    test('isExpired only compares past expiry timestamps', () {
      final expired = InboxMessage.fromJson({
        'id': 'm',
        'expiresAt':
            DateTime.now()
                .subtract(const Duration(minutes: 1))
                .toUtc()
                .toIso8601String(),
      });
      final future = InboxMessage.fromJson({
        'id': 'm',
        'expiresAt':
            DateTime.now()
                .add(const Duration(minutes: 1))
                .toUtc()
                .toIso8601String(),
      });

      expect(expired.isExpired, isTrue);
      expect(future.isExpired, isFalse);
    });
  });

  test('toJson round-trips through fromJson', () {
    final original = InboxMessage(
      id: 'm1',
      kind: InboxKind.chat,
      title: '调度员',
      body: '请确认车辆是否已到达仓库。',
      data: const {'deviceId': 3},
      createdAt: DateTime.utc(2026, 11, 19, 10, 30),
    );

    final restored = InboxMessage.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.kind, original.kind);
    expect(restored.title, original.title);
    expect(restored.body, original.body);
    expect(restored.deviceId, 3);
    expect(restored.createdAt, original.createdAt);
    expect(restored.toJson(), original.toJson());
  });
}
