import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/entities/models.dart';

void main() {
  group('Position', () {
    test('parses Traccar payload and converts knots to m/s', () {
      final position = Position.fromJson({
        'id': 1,
        'deviceId': 42,
        'fixTime': '2026-11-01T08:12:30.000+00:00',
        'latitude': 39.9042,
        'longitude': 116.4074,
        'speed': 10,
        'course': 87,
        'attributes': {'batteryLevel': 78},
      });

      expect(position.deviceId, 42);
      expect(position.latitude, closeTo(39.9042, 1e-6));
      expect(position.speedMetersPerSecond, closeTo(5.14444, 1e-4));
      expect(position.batteryLevel, 78);
      expect(position.fixTime?.isUtc, isTrue);
    });

    test('tolerates missing optional fields', () {
      final position = Position.fromJson({
        'id': 2,
        'deviceId': 1,
        'latitude': '1.5',
        'longitude': '2.5',
      });

      expect(position.speedKnots, 0);
      expect(position.attributes, isEmpty);
      expect(position.altitude, isNull);
    });
  });

  test('Device exposes online status', () {
    final device = Device.fromJson({
      'id': 7,
      'name': 'Phone',
      'uniqueId': '12345678',
      'status': 'online',
    });

    expect(device.isOnline, isTrue);
    expect(device.name, 'Phone');
  });
}
