import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/domain/entities/device_command.dart';

void main() {
  group('DeviceCommandType.fromSupported', () {
    test('returns empty when nothing is reported', () {
      expect(DeviceCommandType.fromSupported(null), isEmpty);
      expect(DeviceCommandType.fromSupported(const []), isEmpty);
    });

    test('filters by api type and keeps enum order', () {
      final commands = DeviceCommandType.fromSupported(
        const ['engineStop', 'positionSingle', 'unknownCommand'],
      );

      expect(
        commands,
        [DeviceCommandType.positionSingle, DeviceCommandType.engineStop],
      );
    });

    test('accepts non string values from JSON payloads', () {
      final commands = DeviceCommandType.fromSupported(
        const [1, 'message', null],
      );

      expect(commands, [DeviceCommandType.message]);
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
    expect(
      buildCommandAttributes(DeviceCommandType.positionSingle),
      isEmpty,
    );
    expect(
      buildCommandAttributes(DeviceCommandType.message, message: ''),
      isEmpty,
    );
  });
}
