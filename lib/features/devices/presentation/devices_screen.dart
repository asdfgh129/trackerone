import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../realtime/application/realtime_controller.dart';

class DevicesScreen extends ConsumerStatefulWidget {
  const DevicesScreen({super.key});

  @override
  ConsumerState<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends ConsumerState<DevicesScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final realtime = ref.watch(realtimeProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.devicesTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () => ref.read(realtimeProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: realtime.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 12),
                Text(error.toString(), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(realtimeProvider),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (state) {
          final devices = state.devices.values.toList()
            ..sort((a, b) {
              if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
              return a.name.compareTo(b.name);
            });
          final filtered = _query.isEmpty
              ? devices
              : devices
                  .where((device) =>
                      device.name.toLowerCase().contains(_query) ||
                      device.uniqueId.toLowerCase().contains(_query))
                  .toList(growable: false);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: l10n.devicesSearchHint,
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? _EmptyDevices(hasDevices: devices.isNotEmpty)
                    : RefreshIndicator(
                        onRefresh: () =>
                            ref.read(realtimeProvider.notifier).refresh(),
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final device = filtered[index];
                            return _DeviceTile(
                              device: device,
                              position: state.positions[device.id],
                              onTap: () =>
                                  context.push('/device/${device.id}'),
                            );
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.position,
    required this.onTap,
  });

  final Device device;
  final Position? position;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: const Icon(Icons.directions_car_outlined),
            ),
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: deviceStatusColor(context, device.status),
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ],
        ),
        title: Text(device.name),
        subtitle: Text(
          '${device.uniqueId} · ${formatRelativeTime(context, position?.fixTime ?? device.lastUpdate)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (position != null)
              Text(
                formatSpeed(position!.speedMetersPerSecond),
                style: theme.textTheme.labelSmall,
              ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _EmptyDevices extends StatelessWidget {
  const _EmptyDevices({required this.hasDevices});

  final bool hasDevices;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasDevices ? Icons.search_off : Icons.devices_other,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              hasDevices ? l10n.commonSearch : l10n.devicesEmpty,
              style: theme.textTheme.titleMedium,
            ),
            if (!hasDevices) ...[
              const SizedBox(height: 8),
              Text(
                l10n.devicesEmptyBody,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
