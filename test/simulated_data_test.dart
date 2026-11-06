import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/dev/simulated_data.dart';

void main() {
  test('builds requested number of simulated devices', () {
    final data = buildSimulatedData(500);

    expect(data.devices, hasLength(500));
    expect(data.positions, hasLength(500));
    expect(data.devices.first.uniqueId, 'sim-900000');
    expect(data.positions.every((p) => p.deviceId >= 900000), isTrue);
  });

  test('returns empty collections for non positive count', () {
    expect(buildSimulatedData(0).devices, isEmpty);
    expect(buildSimulatedData(-1).positions, isEmpty);
  });

  test('alternates offline devices and is deterministic', () {
    final first = buildSimulatedData(20, now: DateTime(2026));
    final second = buildSimulatedData(20, now: DateTime(2026));

    expect(first.devices[7].isOnline, isFalse);
    expect(first.devices[1].isOnline, isTrue);
    expect(first.positions.first.latitude, second.positions.first.latitude);
    expect(first.positions.last.fixTime, second.positions.last.fixTime);
  });
}
