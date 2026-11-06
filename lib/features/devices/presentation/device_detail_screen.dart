import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/map/geo_point.dart';
import '../../../core/map/map_models.dart';
import '../../../core/map/tracker_map_view.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../realtime/application/realtime_controller.dart';
import 'device_commands.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  const DeviceDetailScreen({required this.deviceId, super.key});

  final int deviceId;

  @override
  ConsumerState<DeviceDetailScreen> createState() =>
      _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final realtime = ref.watch(realtimeProvider).valueOrNull;
    final device = realtime?.devices[widget.deviceId];
    final position = realtime?.positions[widget.deviceId];

    return Scaffold(
      appBar: AppBar(
        title: Text(device?.name ?? l10n.deviceTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () => ref.read(realtimeProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: device == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.devices_other, size: 48),
                    const SizedBox(height: 12),
                    Text(l10n.devicesEmpty),
                    const SizedBox(height: 8),
                    Text(
                      l10n.devicesEmptyBody,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (position != null)
                        SizedBox(
                          height: 220,
                          child: TrackerMapView(
                            markers: [
                              MapDeviceMarker(
                                deviceId: device.id,
                                label: device.name,
                                point: GeoPoint(
                                  position.latitude,
                                  position.longitude,
                                ),
                                course: position.course,
                                online: device.isOnline,
                                batteryLevel: position.batteryLevel,
                                speedMetersPerSecond:
                                    position.speedMetersPerSecond,
                              ),
                            ],
                            initialTarget: GeoPoint(
                              position.latitude,
                              position.longitude,
                            ),
                            initialZoom: 16,
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: Text(l10n.deviceNoPosition),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 12,
                                  color: deviceStatusColor(
                                    context,
                                    device.status,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(deviceStatusLabel(context, device.status)),
                                const Spacer(),
                                Text(
                                  formatRelativeTime(
                                    context,
                                    position?.fixTime ?? device.lastUpdate,
                                  ),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _InfoRow(
                              label: l10n.deviceUniqueId,
                              value: device.uniqueId,
                            ),
                            _InfoRow(
                              label: l10n.deviceStatus,
                              value: deviceStatusLabel(
                                context,
                                device.status,
                              ),
                            ),
                            if (device.category != null)
                              _InfoRow(
                                label: l10n.deviceCategory,
                                value: device.category!,
                              ),
                            if (device.phone != null)
                              _InfoRow(
                                label: 'Phone',
                                value: device.phone!,
                              ),
                            if (device.model != null)
                              _InfoRow(label: 'Model', value: device.model!),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (position != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.devicePositionTitle,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          _InfoRow(
                            label: 'Lat / Lon',
                            value:
                                '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}',
                          ),
                          _InfoRow(
                            label: l10n.mapSpeed,
                            value: formatSpeed(
                              position.speedMetersPerSecond,
                            ),
                          ),
                          _InfoRow(
                            label: l10n.mapBattery,
                            value: formatBattery(position.batteryLevel),
                          ),
                          _InfoRow(
                            label: l10n.deviceLastUpdate,
                            value: formatDateTime(position.fixTime),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            context.push('/device/${device.id}/history'),
                        icon: const Icon(Icons.timeline),
                        label: Text(l10n.deviceHistory),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            showDeviceCommandSheet(context, ref, device),
                        icon: const Icon(Icons.tune),
                        label: Text(l10n.deviceCommandsTitle),
                      ),
                    ),
                  ],
                ),
                CommandQueueCard(deviceId: device.id),
              ],
            ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
