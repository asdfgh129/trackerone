import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/entities/device_command.dart';

void main() {
  group('DeviceCommandType.fromSupported', () {
    test('returns empty when nothing is reported', () {
      expect(DeviceCommandType.fromSupported(null), isEmpty);
      expect(DeviceCommandType.fromSupported(const []), isEmpty);
    });

    test('filters by api type and keeps enum order', () {
      final commands = DeviceCommandType.fromSupported(const [
        'engineStop',
        'positionSingle',
        'unknownCommand',
      ]);

      expect(commands, [
        DeviceCommandType.positionSingle,
        DeviceCommandType.engineStop,
      ]);
    });

    test('accepts non string values from JSON payloads', () {
      final commands = DeviceCommandType.fromSupported(const [
        1,
        'message',
        null,
      ]);

      expect(commands, [DeviceCommandType.message]);
    });
  });

  group('DeviceCommandType.tryParse', () {
    test('maps api types back to enum values', () {
      expect(
        DeviceCommandType.tryParse('engineStop'),
        DeviceCommandType.engineStop,
      );
      expect(
        DeviceCommandType.tryParse('positionPeriodic'),
        DeviceCommandType.positionPeriodic,
      );
    });

    test('returns null for unknown or empty input', () {
      expect(DeviceCommandType.tryParse(null), isNull);
      expect(DeviceCommandType.tryParse(''), isNull);
      expect(DeviceCommandType.tryParse('teleport'), isNull);
    });
  });

  test('destructive commands require confirmation', () {
    expect(DeviceCommandType.rebootDevice.needsConfirmation, isTrue);
    expect(DeviceCommandType.factoryReset.needsConfirmation, isTrue);
    expect(DeviceCommandType.engineStop.needsConfirmation, isFalse);
  });

  test('command attributes only include relevant parameters', () {
    expect(
      buildCommandAttributes(
        DeviceCommandType.positionPeriodic,
        frequencySeconds: 30,
      ),
      {'frequency': 30},
    );
    expect(
      buildCommandAttributes(DeviceCommandType.message, message: 'hello'),
      {'message': 'hello'},
    );
    expect(buildCommandAttributes(DeviceCommandType.positionSingle), isEmpty);
    expect(
      buildCommandAttributes(DeviceCommandType.message, message: ''),
      isEmpty,
    );
  });
}
