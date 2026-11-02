import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/build_config.dart';
import 'amap/amap_tracker_map.dart';
import 'geo_point.dart';
import 'map_models.dart';
import 'map_privacy_consent.dart';
import 'map_provider.dart';

/// 唯一的地图入口。业务层只依赖本 Widget 与 [MapDeviceMarker]，不感知地图供应商。
///
/// 首次进入时会检查地图 SDK 隐私授权；未同意时展示合规说明卡片，
/// 同意后才初始化高德 SDK 并加载底图。
class TrackerMapView extends ConsumerWidget {
  const TrackerMapView({
    required this.markers,
    this.trails = const [],
    this.initialTarget,
    this.initialZoom = 15,
    this.onMarkerTap,
    super.key,
  });

  final List<MapDeviceMarker> markers;
  final List<MapTrail> trails;
  final GeoPoint? initialTarget;
  final double initialZoom;
  final ValueChanged<MapDeviceMarker>? onMarkerTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(mapConfigProvider);

    return switch (config.provider) {
      MapProvider.none => const _MapUnavailable(),
      MapProvider.amap => _AmapGate(
          markers: markers,
          trails: trails,
          initialTarget: initialTarget,
          initialZoom: initialZoom,
          trafficEnabled: config.trafficEnabled,
          onMarkerTap: onMarkerTap,
        ),
    };
  }
}

class _AmapGate extends ConsumerWidget {
  const _AmapGate({
    required this.markers,
    required this.trails,
    required this.initialTarget,
    required this.initialZoom,
    required this.trafficEnabled,
    required this.onMarkerTap,
  });

  final List<MapDeviceMarker> markers;
  final List<MapTrail> trails;
  final GeoPoint? initialTarget;
  final double initialZoom;
  final bool trafficEnabled;
  final ValueChanged<MapDeviceMarker>? onMarkerTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(mapPrivacyConsentProvider);

    return consent.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _MapConsentCard(
        onAgree: () => ref.read(mapPrivacyConsentProvider.notifier).agree(),
      ),
      data: (agreed) {
        if (!agreed) {
          return _MapConsentCard(
            onAgree: () =>
                ref.read(mapPrivacyConsentProvider.notifier).agree(),
          );
        }
        if (!BuildConfig.hasAmapKey) {
          return const _MapKeyMissing();
        }
        return AmapTrackerMap(
          markers: markers,
          trails: trails,
          initialTarget: initialTarget,
          initialZoom: initialZoom,
          trafficEnabled: trafficEnabled,
          onMarkerTap: onMarkerTap,
        );
      },
    );
  }
}

/// 地图 SDK 合规授权卡片。
///
/// 文案需与隐私政策中的 SDK 清单一致，应用商店检测会逐条核对。
class _MapConsentCard extends StatelessWidget {
  const _MapConsentCard({required this.onAgree});

  final VoidCallback onAgree;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerLow,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text('地图服务说明', style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                '本应用使用高德地图 SDK 显示位置与轨迹。'
                '为提供地图能力，SDK 会收集设备信息、网络状态和地图交互数据。'
                '请阅读《隐私政策》中的第三方 SDK 清单后使用。',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAgree,
                child: const Text('同意并加载地图'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('地图未配置', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '构建时通过 --dart-define=MAP_PROVIDER=amap '
              '与 AMAP_ANDROID_KEY / AMAP_IOS_KEY 启用高德地图。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// 已选择高德但缺少 Key：不要初始化 SDK，避免白屏或原生崩溃。
class _MapKeyMissing extends StatelessWidget {
  const _MapKeyMissing();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_off_outlined,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text('缺少高德地图 Key', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              '请在构建时传入 --dart-define=AMAP_ANDROID_KEY=... '
              '与 --dart-define=AMAP_IOS_KEY=...。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
