import 'dart:math' as math;

import 'geo_point.dart';
import 'map_models.dart';

/// 按地图缩放级别对设备标记做网格聚合。
///
/// 纯函数，方便单测与在不同地图供应商之间复用：
/// - `zoom >= 17` 不聚合，保证街道级别能看到单台设备；
/// - 「本机」标记永远单独展示，避免用户找不到自己；
/// - 聚合点取组内经纬度平均值，标签为设备数量。
///
/// 网格大小随缩放指数变化：zoom 15 时约 400m，zoom 10 时约 14km。
List<MapDeviceMarker> clusterMarkers(
  List<MapDeviceMarker> markers, {
  required double zoom,
  bool enabled = true,
}) {
  if (!enabled || markers.length <= 1 || zoom >= 17) {
    return markers;
  }

  final cell = 0.004 * math.pow(2, 15 - zoom).toDouble();
  if (cell <= 0) return markers;

  final buckets = <String, List<MapDeviceMarker>>{};
  final result = <MapDeviceMarker>[];

  for (final marker in markers) {
    if (marker.isSelf || marker.isCluster) {
      result.add(marker);
      continue;
    }
    final latCell = (marker.point.latitude / cell).floor();
    final lonCell = (marker.point.longitude / cell).floor();
    buckets.putIfAbsent('$latCell:$lonCell', () => []).add(marker);
  }

  for (final group in buckets.values) {
    if (group.length == 1) {
      result.add(group.first);
      continue;
    }
    var lat = 0.0;
    var lon = 0.0;
    var online = false;
    for (final marker in group) {
      lat += marker.point.latitude;
      lon += marker.point.longitude;
      online = online || marker.online;
    }
    result.add(
      MapDeviceMarker(
        deviceId: group.first.deviceId,
        label: '${group.length}',
        point: GeoPoint(lat / group.length, lon / group.length),
        online: online,
        clusterCount: group.length,
        clusterDeviceIds:
            group.map((marker) => marker.deviceId).toList(growable: false),
      ),
    );
  }

  // 聚合点排在后面，避免遮挡本机与单台设备。
  result.sort((a, b) {
    if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
    if (a.isCluster != b.isCluster) return a.isCluster ? 1 : -1;
    return a.label.compareTo(b.label);
  });
  return result;
}
