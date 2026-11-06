import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/map/geo_point.dart';
import 'package:trackerone/core/map/map_models.dart';
import 'package:trackerone/core/map/marker_cluster.dart';

MapDeviceMarker marker({
  required int id,
  required double lat,
  required double lon,
  bool self = false,
  bool online = true,
}) {
  return MapDeviceMarker(
    deviceId: id,
    label: 'D$id',
    point: GeoPoint(lat, lon),
    isSelf: self,
    online: online,
  );
}

void main() {
  test('keeps markers unchanged at street zoom', () {
    final markers = [
      marker(id: 1, lat: 31.2300, lon: 121.4700),
      marker(id: 2, lat: 31.2301, lon: 121.4701),
    ];

    expect(clusterMarkers(markers, zoom: 17), same(markers));
  });

  test('clusters nearby markers and averages the center', () {
    final markers = [
      marker(id: 1, lat: 31.2300, lon: 121.4700, online: true),
      marker(id: 2, lat: 31.2304, lon: 121.4704, online: false),
      marker(id: 3, lat: 31.9000, lon: 121.9000),
    ];

    final result = clusterMarkers(markers, zoom: 14);

    expect(result, hasLength(2));
    final cluster = result.firstWhere((item) => item.isCluster);
    expect(cluster.clusterCount, 2);
    expect(cluster.clusterDeviceIds, [1, 2]);
    expect(cluster.online, isTrue);
    expect(cluster.point.latitude, closeTo(31.2302, 1e-9));
    expect(cluster.point.longitude, closeTo(121.4702, 1e-9));
  });

  test('never clusters the current device', () {
    final markers = [
      marker(id: 1, lat: 31.23, lon: 121.47, self: true),
      marker(id: 2, lat: 31.2301, lon: 121.4701),
    ];

    final result = clusterMarkers(markers, zoom: 12);

    expect(result, hasLength(2));
    expect(result.where((item) => item.isSelf), hasLength(1));
    expect(result.where((item) => item.isCluster), isEmpty);
  });

  test('can be disabled', () {
    final markers = [
      marker(id: 1, lat: 31.23, lon: 121.47),
      marker(id: 2, lat: 31.23, lon: 121.47),
    ];

    expect(clusterMarkers(markers, zoom: 14, enabled: false), same(markers));
  });
}
