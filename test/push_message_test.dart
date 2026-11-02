import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/push/push_gateway.dart';

void main() {
  group('PushMessage.fromData', () {
    test('parses string event id from push payload', () {
      final message = PushMessage.fromData({
        'eventId': '555',
        'title': '围栏进入',
        'body': '车辆进入「公司」',
      });

      expect(message.eventId, 555);
      expect(message.title, '围栏进入');
      expect(message.body, '车辆进入「公司」');
      expect(message.isCommand, isFalse);
    });

    test('parses numeric event id', () {
      final message = PushMessage.fromData({'eventId': 42});
      expect(message.eventId, 42);
    });

    test('detects remote command payload', () {
      final message = PushMessage.fromData({
        'command': 'positionSingle',
      });

      expect(message.isCommand, isTrue);
      expect(message.command, 'positionSingle');
    });

    test('ignores empty strings and missing fields', () {
      final message = PushMessage.fromData({'eventId': '', 'command': ''});

      expect(message.eventId, isNull);
      expect(message.title, isNull);
      expect(message.isCommand, isFalse);
      // 原始 payload 保留，便于诊断；只是归一化字段为空。
      expect(message.data, hasLength(2));
    });
  });
}
