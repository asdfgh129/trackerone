import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/map/coordinate_transform.dart';
import 'package:trackerone/core/map/geo_point.dart';

void main() {
  // 期望值由同一算法离线计算，用于防止改动时偏移量悄悄变化。
  const tiananmenWgs = GeoPoint(39.9087, 116.3975);
  const tiananmenGcj = GeoPoint(39.91010349934476, 116.40374357265176);

  group('WGS-84 -> GCJ-02', () {
    test('matches known Beijing offset', () {
      final result = CoordinateTransform.wgs84ToGcj02(tiananmenWgs);

      expect(result.latitude, closeTo(tiananmenGcj.latitude, 1e-9));
      expect(result.longitude, closeTo(tiananmenGcj.longitude, 1e-9));
    });

    test('offset is hundreds of meters inside China', () {
      final result = CoordinateTransform.wgs84ToGcj02(tiananmenWgs);
      final distance = tiananmenWgs.distanceTo(result);

      expect(distance, greaterThan(100));
      expect(distance, lessThan(1000));
    });

    test('leaves coordinates outside China untouched', () {
      const tokyo = GeoPoint(35.6762, 139.6503);
      expect(CoordinateTransform.wgs84ToGcj02(tokyo), tokyo);
    });
  });

  group('GCJ-02 -> WGS-84', () {
    test('round trip is accurate to sub-meter', () {
      final back = CoordinateTransform.gcj02ToWgs84(
        CoordinateTransform.wgs84ToGcj02(tiananmenWgs),
      );

      // 1e-6 度约 0.11 米。
      expect(back.latitude, closeTo(tiananmenWgs.latitude, 1e-6));
      expect(back.longitude, closeTo(tiananmenWgs.longitude, 1e-6));
    });
  });

  group('BD-09', () {
    test('round trip through Baidu coordinates', () {
      final bd = CoordinateTransform.wgs84ToBd09(tiananmenWgs);
      final back = CoordinateTransform.bd09ToWgs84(bd);

      expect(back.latitude, closeTo(tiananmenWgs.latitude, 1e-5));
      expect(back.longitude, closeTo(tiananmenWgs.longitude, 1e-5));
    });

    test('BD-09 is offset from GCJ-02', () {
      final gcj = CoordinateTransform.wgs84ToGcj02(tiananmenWgs);
      final bd = CoordinateTransform.gcj02ToBd09(gcj);

      expect(gcj.distanceTo(bd), greaterThan(50));
    });
  });

  group('convert', () {
    test('identity when source equals target', () {
      expect(
        CoordinateTransform.convert(
          tiananmenWgs,
          from: MapCoordinateSystem.wgs84,
          to: MapCoordinateSystem.wgs84,
        ),
        tiananmenWgs,
      );
    });

    test('wgs84 -> gcj02 matches dedicated method', () {
      expect(
        CoordinateTransform.convert(
          tiananmenWgs,
          from: MapCoordinateSystem.wgs84,
          to: MapCoordinateSystem.gcj02,
        ),
        CoordinateTransform.wgs84ToGcj02(tiananmenWgs),
      );
    });
  });

  group('GeoPoint', () {
    test('distance between identical points is zero', () {
      expect(tiananmenWgs.distanceTo(tiananmenWgs), 0);
    });

    test('value equality', () {
      expect(const GeoPoint(1, 2), const GeoPoint(1, 2));
      expect(const GeoPoint(1, 2).hashCode, const GeoPoint(1, 2).hashCode);
    });
  });
}
