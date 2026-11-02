import 'dart:math' as math;

/// 坐标系。
///
/// 约定：**数据层永远是 [wgs84]**，只有渲染层才转换。
/// - Traccar 服务端与 OsmAnd 上报：WGS-84
/// - 高德 / 腾讯地图：GCJ-02（火星坐标）
/// - 百度地图：BD-09
enum MapCoordinateSystem {
  /// GPS 原始坐标，服务端存储与 GPX 导出使用。
  wgs84,

  /// 国测局加密坐标，高德 / 腾讯使用。
  gcj02,

  /// 百度在 GCJ-02 基础上再次偏移。
  bd09,
}

/// 不可变经纬度点。
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  double get lat => latitude;
  double get lng => longitude;

  GeoPoint copyWith({double? latitude, double? longitude}) =>
      GeoPoint(latitude ?? this.latitude, longitude ?? this.longitude);

  /// 球面距离（米），用于抽稀、聚合与停留判断。
  double distanceTo(GeoPoint other) {
    const earthRadius = 6371000.0;
    final dLat = _rad(other.latitude - latitude);
    final dLng = _rad(other.longitude - longitude);
    final sinLat = math.sin(dLat / 2);
    final sinLng = math.sin(dLng / 2);
    final a = sinLat * sinLat +
        math.cos(_rad(latitude)) *
            math.cos(_rad(other.latitude)) *
            sinLng *
            sinLng;
    return 2 * earthRadius * math.asin(math.sqrt(a));
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() =>
      'GeoPoint(${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)})';

  static double _rad(double degrees) => degrees * math.pi / 180.0;
}
