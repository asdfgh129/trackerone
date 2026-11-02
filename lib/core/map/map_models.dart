import 'geo_point.dart';

/// 地图上要渲染的设备标记。业务层使用 WGS-84，渲染层负责转换。
class MapDeviceMarker {
  const MapDeviceMarker({
    required this.deviceId,
    required this.label,
    required this.point,
    this.course = 0,
    this.online = false,
    this.isSelf = false,
    this.batteryLevel,
    this.speedMetersPerSecond,
  });

  final int deviceId;
  final String label;
  final GeoPoint point;

  /// 方位角，0–360，0 为正北。
  final double course;
  final bool online;

  /// 是否为「本机」上报设备，UI 用不同图标与标签。
  final bool isSelf;
  final double? batteryLevel;
  final double? speedMetersPerSecond;
}

/// 轨迹尾迹。点数由调用方按距离 / 时间抽稀后传入。
class MapTrail {
  const MapTrail({
    required this.deviceId,
    required this.points,
    this.width = 4,
  });

  final int deviceId;
  final List<GeoPoint> points;
  final int width;
}

/// 地图相机目标。
class MapCameraTarget {
  const MapCameraTarget({
    required this.point,
    this.zoom = 15,
    this.animate = true,
  });

  final GeoPoint point;
  final double zoom;
  final bool animate;
}
