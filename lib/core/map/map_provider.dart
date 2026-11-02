import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/build_config.dart';
import 'geo_point.dart';

/// 地图供应商。
///
/// 首发（中国大陆）使用高德；腾讯为备选，百度因 BD-09 二次偏移成本高不采用。
enum MapProvider {
  /// 高德地图（amap_map），GCJ-02。
  amap,

  /// 未接入任何底图，UI 展示占位（开发早期 / 无 Key）。
  none;

  static MapProvider parse(String value) => switch (value.trim().toLowerCase()) {
        'amap' || 'gaode' => MapProvider.amap,
        _ => MapProvider.none,
      };
}

/// 底图样式。
enum MapLayerStyle { standard, satellite, night }

/// 地图运行时配置。
///
/// 业务代码只依赖本配置，不直接依赖 `amap_map`。
class MapConfig {
  const MapConfig({
    this.provider = MapProvider.none,
    this.style = MapLayerStyle.standard,
    this.trafficEnabled = false,
    this.trailLength = 50,
    this.animateMarkers = true,
  });

  final MapProvider provider;
  final MapLayerStyle style;
  final bool trafficEnabled;

  /// 尾迹保留的点数。
  final int trailLength;
  final bool animateMarkers;

  /// 数据层坐标系固定为 WGS-84。
  MapCoordinateSystem get dataCoordinateSystem => MapCoordinateSystem.wgs84;

  /// 渲染层坐标系。
  MapCoordinateSystem get renderCoordinateSystem => switch (provider) {
        MapProvider.amap => MapCoordinateSystem.gcj02,
        MapProvider.none => MapCoordinateSystem.wgs84,
      };

  factory MapConfig.fromEnvironment() {
    return MapConfig(
      provider: MapProvider.parse(BuildConfig.mapProvider),
      trafficEnabled: BuildConfig.isProd,
    );
  }

  MapConfig copyWith({
    MapProvider? provider,
    MapLayerStyle? style,
    bool? trafficEnabled,
    int? trailLength,
    bool? animateMarkers,
  }) {
    return MapConfig(
      provider: provider ?? this.provider,
      style: style ?? this.style,
      trafficEnabled: trafficEnabled ?? this.trafficEnabled,
      trailLength: trailLength ?? this.trailLength,
      animateMarkers: animateMarkers ?? this.animateMarkers,
    );
  }
}

final mapConfigProvider = Provider<MapConfig>(
  (ref) => MapConfig.fromEnvironment(),
);
