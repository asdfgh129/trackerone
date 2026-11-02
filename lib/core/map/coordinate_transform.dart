import 'dart:math' as math;

import 'geo_point.dart';

/// WGS-84 / GCJ-02 / BD-09 坐标转换。
///
/// 只做数学转换，不依赖任何地图 SDK，可直接单元测试。
/// 参考实现：国测局偏移算法（公开通用版本），精度约 1 米，足够展示；
/// 若需要与高德 SDK 完全一致，可在 [gcj02ToWgs84] 增加迭代次数。
abstract final class CoordinateTransform {
  /// 克拉索夫斯基椭球参数。
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  /// 百度使用的额外偏移常量。
  static const double _xPi = math.pi * 3000.0 / 180.0;

  /// 中国大陆粗略边界（含港澳台外的大陆区域）。
  ///
  /// 境外不做偏移，直接返回原坐标，避免把海外轨迹画错。
  static bool isOutOfChina(double latitude, double longitude) {
    return longitude < 72.004 ||
        longitude > 137.8347 ||
        latitude < 0.8293 ||
        latitude > 55.8271;
  }

  /// WGS-84 → GCJ-02（高德 / 腾讯）。
  static GeoPoint wgs84ToGcj02(GeoPoint point) {
    if (isOutOfChina(point.latitude, point.longitude)) {
      return point;
    }
    final delta = _delta(point.latitude, point.longitude);
    return GeoPoint(
      point.latitude + delta.latitude,
      point.longitude + delta.longitude,
    );
  }

  /// GCJ-02 → WGS-84（反解，迭代逼近）。
  ///
  /// 用于「用户在高德地图上点选一个点，需要存回 WGS-84」的场景。
  static GeoPoint gcj02ToWgs84(GeoPoint point) {
    if (isOutOfChina(point.latitude, point.longitude)) {
      return point;
    }
    var wgs = point;
    for (var i = 0; i < 6; i++) {
      final converted = wgs84ToGcj02(wgs);
      wgs = GeoPoint(
        wgs.latitude + (point.latitude - converted.latitude),
        wgs.longitude + (point.longitude - converted.longitude),
      );
    }
    return wgs;
  }

  /// GCJ-02 → BD-09（百度）。
  static GeoPoint gcj02ToBd09(GeoPoint point) {
    if (isOutOfChina(point.latitude, point.longitude)) {
      return point;
    }
    final z = math.sqrt(
          point.longitude * point.longitude +
              point.latitude * point.latitude,
        ) +
        0.00002 * math.sin(point.latitude * _xPi);
    final theta = math.atan2(point.latitude, point.longitude) +
        0.000003 * math.cos(point.longitude * _xPi);
    return GeoPoint(
      z * math.sin(theta) + 0.006,
      z * math.cos(theta) + 0.0065,
    );
  }

  /// BD-09 → GCJ-02（百度坐标反解）。
  static GeoPoint bd09ToGcj02(GeoPoint point) {
    if (isOutOfChina(point.latitude, point.longitude)) {
      return point;
    }
    final x = point.longitude - 0.0065;
    final y = point.latitude - 0.006;
    final z = math.sqrt(x * x + y * y) - 0.00002 * math.sin(y * _xPi);
    final theta = math.atan2(y, x) - 0.000003 * math.cos(x * _xPi);
    return GeoPoint(z * math.sin(theta), z * math.cos(theta));
  }

  /// WGS-84 → BD-09。
  static GeoPoint wgs84ToBd09(GeoPoint point) =>
      gcj02ToBd09(wgs84ToGcj02(point));

  /// BD-09 → WGS-84。
  static GeoPoint bd09ToWgs84(GeoPoint point) =>
      gcj02ToWgs84(bd09ToGcj02(point));

  /// 按目标坐标系转换。数据层调用方永远传 `wgs84`。
  static GeoPoint convert(
    GeoPoint point, {
    required MapCoordinateSystem from,
    required MapCoordinateSystem to,
  }) {
    if (from == to) return point;

    // 先统一转成 GCJ-02 作为中间态。
    final gcj = switch (from) {
      MapCoordinateSystem.wgs84 => wgs84ToGcj02(point),
      MapCoordinateSystem.gcj02 => point,
      MapCoordinateSystem.bd09 => bd09ToGcj02(point),
    };

    return switch (to) {
      MapCoordinateSystem.gcj02 => gcj,
      MapCoordinateSystem.wgs84 => gcj02ToWgs84(gcj),
      MapCoordinateSystem.bd09 => gcj02ToBd09(gcj),
    };
  }

  static GeoPoint _delta(double latitude, double longitude) {
    final dLat = _transformLat(longitude - 105.0, latitude - 35.0);
    final dLng = _transformLng(longitude - 105.0, latitude - 35.0);

    final radLat = latitude / 180.0 * math.pi;
    final magic = 1 - _ee * math.sin(radLat) * math.sin(radLat);
    final sqrtMagic = math.sqrt(magic);

    return GeoPoint(
      (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi),
      (dLng * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi),
    );
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) +
            40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) +
            320.0 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) +
            40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
