import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/build_config.dart';
import '../../l10n/app_localizations.dart';
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
    this.onZoomChanged,
    super.key,
  });

  final List<MapDeviceMarker> markers;
  final List<MapTrail> trails;
  final GeoPoint? initialTarget;
  final double initialZoom;
  final ValueChanged<MapDeviceMarker>? onMarkerTap;
  final ValueChanged<double>? onZoomChanged;

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
          onZoomChanged: onZoomChanged,
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
    this.onZoomChanged,
  });

  final List<MapDeviceMarker> markers;
  final List<MapTrail> trails;
  final GeoPoint? initialTarget;
  final double initialZoom;
  final bool trafficEnabled;
  final ValueChanged<MapDeviceMarker>? onMarkerTap;
  final ValueChanged<double>? onZoomChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(mapPrivacyConsentProvider);

    return consent.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => _MapConsentCard(
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
          onZoomChanged: onZoomChanged,
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
    final l10n = AppLocalizations.of(context);
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
              Text(l10n.mapConsentTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                l10n.mapConsentBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onAgree,
                child: Text(l10n.mapConsentAgree),
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.map_outlined, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.mapUnavailableTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.mapUnavailableBody,
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
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.key_off_outlined,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(l10n.mapKeyMissingTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.mapKeyMissingBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
