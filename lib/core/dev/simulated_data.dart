import '../../domain/entities/models.dart';

/// 生成本地模拟设备，用于在没有 500/1000 台真实设备时验证地图性能。
///
/// 设备集中在约 40×40 的网格内，刻意制造可聚合的密集区域。
/// 通过 `--dart-define=SIMULATE_DEVICES=500` 启用。
({List<Device> devices, List<Position> positions}) buildSimulatedData(
  int count, {
  DateTime? now,
}) {
  if (count <= 0) {
    return (devices: const <Device>[], positions: const <Position>[]);
  }
  final time = now ?? DateTime.now();
  final devices = <Device>[];
  final positions = <Position>[];
  const baseLat = 31.2304;
  const baseLon = 121.4737;

  for (var index = 0; index < count; index++) {
    final id = 900000 + index;
    final row = index ~/ 40;
    final column = index % 40;
    final online = index % 7 != 0;
    devices.add(
      Device(
        id: id,
        name: 'SIM-${(index + 1).toString().padLeft(4, '0')}',
        uniqueId: 'sim-$id',
        status: online ? 'online' : 'offline',
        lastUpdate: time,
        category: 'car',
        model: 'Simulator',
        attributes: const {'simulated': true},
      ),
    );
    positions.add(
      Position(
        id: 800000 + index,
        deviceId: id,
        latitude: baseLat + row * 0.0012 + (column % 3) * 0.00015,
        longitude: baseLon + column * 0.0012 + (row % 3) * 0.00015,
        fixTime: time.subtract(Duration(seconds: index % 120)),
        speedKnots: (index % 60) * 0.8,
        course: (index * 7) % 360,
        altitude: 10,
        accuracy: 5,
        attributes: {
          'batteryLevel': 40 + (index % 60),
        },
      ),
    );
  }

  return (devices: devices, positions: positions);
}
