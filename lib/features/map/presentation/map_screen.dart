import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/map/geo_point.dart';
import '../../../core/map/map_models.dart';
import '../../../core/map/marker_cluster.dart';
import '../../../core/map/tracker_map_view.dart';
import '../../../domain/entities/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../realtime/application/realtime_controller.dart';
import '../../tracking/application/tracking_controller.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  int? _selectedDeviceId;
  double _zoom = 15;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final realtime = ref.watch(realtimeProvider);
    final uniqueId =
        ref.watch(trackingProvider).valueOrNull?.uniqueId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.mapTitle),
        actions: [
          const _ConnectionBadge(),
          IconButton(
            tooltip: l10n.mapSearchHint,
            onPressed: () => _pickDevice(realtime.valueOrNull),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: l10n.mapRefresh,
            onPressed: () =>
                ref.read(realtimeProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: realtime.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MapError(
          message: error.toString(),
          onRetry: () => ref.invalidate(realtimeProvider),
        ),
        data: (state) {
          final rawMarkers = _markers(state, uniqueId);
          final markers = clusterMarkers(rawMarkers, zoom: _zoom);
          final selected = _selectedMarker(rawMarkers);
          final clustered = rawMarkers.length - markers.length;
          return Stack(
            children: [
              Positioned.fill(
                child: TrackerMapView(
                  markers: markers,
                  initialTarget:
                      rawMarkers.isNotEmpty ? rawMarkers.first.point : null,
                  initialZoom: _zoom,
                  onZoomChanged: (zoom) {
                    if ((zoom - _zoom).abs() < 0.25) return;
                    setState(() => _zoom = zoom);
                  },
                  onMarkerTap: (marker) {
                    if (marker.isCluster) {
                      unawaited(_pickDevice(state, deviceIds: marker.clusterDeviceIds));
                      return;
                    }
                    setState(() => _selectedDeviceId = marker.deviceId);
                  },
                ),
              ),
              if (state.error != null)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 12,
                  child: _Banner(text: state.error!),
                ),
              if (clustered > 0)
                Positioned(
                  left: 16,
                  right: 16,
                  top: state.error == null ? 12 : 64,
                  child: _Banner(
                    text: l10n.mapClusteredNotice(clustered),
                    icon: Icons.layers_outlined,
                    isError: false,
                  ),
                ),
              if (markers.isEmpty)
                Positioned(
                  left: 24,
                  right: 24,
                  top: 16,
                  child: _EmptyMapCard(
                    onTracking: () => context.go('/home/tracking'),
                  ),
                ),
              if (selected != null)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: _DeviceCard(
                    marker: selected,
                    position: state.positions[selected.deviceId],
                    device: state.devices[selected.deviceId],
                    onClose: () => setState(() => _selectedDeviceId = null),
                    onHistory: () => context.push(
                      '/device/${selected.deviceId}/history',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  List<MapDeviceMarker> _markers(RealtimeState state, String uniqueId) {
    final markers = <MapDeviceMarker>[];
    for (final entry in state.positions.entries) {
      final position = entry.value;
      final device = state.devices[entry.key];
      if (position.latitude == 0 && position.longitude == 0) continue;
      markers.add(
        MapDeviceMarker(
          deviceId: entry.key,
          label: device?.name ?? '#${entry.key}',
          point: GeoPoint(position.latitude, position.longitude),
          course: position.course,
          online: device?.isOnline ?? false,
          isSelf: device?.uniqueId == uniqueId && uniqueId.isNotEmpty,
          batteryLevel: position.batteryLevel,
          speedMetersPerSecond: position.speedMetersPerSecond,
        ),
      );
    }
    markers.sort((a, b) {
      if (a.isSelf != b.isSelf) return a.isSelf ? -1 : 1;
      return a.label.compareTo(b.label);
    });
    return markers;
  }

  MapDeviceMarker? _selectedMarker(List<MapDeviceMarker> markers) {
    if (_selectedDeviceId == null) return null;
    for (final marker in markers) {
      if (marker.deviceId == _selectedDeviceId) return marker;
    }
    return null;
  }

  Future<void> _pickDevice(
    RealtimeState? state, {
    List<int>? deviceIds,
  }) async {
    if (state == null || state.devices.isEmpty) return;
    final devices = state.devices.values
        .where(
          (device) =>
              deviceIds == null || deviceIds.contains(device.id),
        )
        .toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return a.name.compareTo(b.name);
      });
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final device in devices)
              ListTile(
                leading: Icon(
                  Icons.circle,
                  size: 12,
                  color: deviceStatusColor(context, device.status),
                ),
                title: Text(device.name),
                subtitle: Text(device.uniqueId),
                trailing: state.positions[device.id] == null
                    ? null
                    : Text(formatRelativeTime(
                        context,
                        state.positions[device.id]!.fixTime,
                      )),
                onTap: () => Navigator.pop(context, device.id),
              ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _selectedDeviceId = selected);
    }
  }
}

class _ConnectionBadge extends ConsumerWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(realtimeProvider).valueOrNull;
    final connected = state?.connected ?? false;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: connected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              connected ? Icons.wifi : Icons.wifi_off,
              size: 14,
              color: connected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              connected ? l10n.mapConnected : l10n.mapDisconnected,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({
    required this.marker,
    required this.position,
    required this.device,
    required this.onClose,
    required this.onHistory,
  });

  final MapDeviceMarker marker;
  final Position? position;
  final Device? device;
  final VoidCallback onClose;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      elevation: 6,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  marker.isSelf
                      ? Icons.my_location
                      : Icons.directions_car_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        marker.label,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        device == null
                            ? l10n.commonUnknown
                            : deviceStatusLabel(context, device!.status),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                _Metric(
                  icon: Icons.speed,
                  text: formatSpeed(marker.speedMetersPerSecond ?? 0),
                ),
                _Metric(
                  icon: Icons.battery_std,
                  text: formatBattery(marker.batteryLevel),
                ),
                _Metric(
                  icon: Icons.schedule,
                  text: formatRelativeTime(context, position?.fixTime),
                ),
                if (position?.altitude != null)
                  _Metric(
                    icon: Icons.terrain,
                    text: '${position!.altitude!.toStringAsFixed(0)} m',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onHistory,
                  icon: const Icon(Icons.timeline),
                  label: Text(l10n.deviceHistory),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/device/${marker.deviceId}'),
                  icon: const Icon(Icons.info_outline),
                  label: Text(l10n.deviceTitle),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _EmptyMapCard extends StatelessWidget {
  const _EmptyMapCard({required this.onTracking});

  final VoidCallback onTracking;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.mapNoDevices, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.mapNoDevicesBody, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onTracking,
                child: Text(l10n.trackingBind),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.text,
    this.icon = Icons.cloud_off,
    this.isError = true,
  });

  final String text;
  final IconData icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = isError
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.surfaceContainerHighest;
    final foreground =
        isError ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSurface;
    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: foreground,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapError extends StatelessWidget {
  const _MapError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.map_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
