import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../domain/entities/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../realtime/application/realtime_controller.dart';

final eventDetailProvider =
    FutureProvider.autoDispose.family<DeviceEvent, int>((ref, id) async {
  final api = ref.watch(traccarApiProvider);
  if (api == null) {
    throw StateError('Not authenticated');
  }
  return api.getEvent(id);
});

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({required this.eventId, super.key});

  final int eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final event = ref.watch(eventDetailProvider(eventId));
    final realtime = ref.watch(realtimeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.eventDetailTitle)),
      body: event.when(
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
                  onPressed: () =>
                      ref.invalidate(eventDetailProvider(eventId)),
                  child: Text(l10n.retry),
                ),
              ],
            ),
          ),
        ),
        data: (data) {
          final device = realtime?.devices[data.deviceId];
          final position = realtime?.positions[data.deviceId];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(eventIcon(data.type)),
                  ),
                  title: Text(humanizeEventType(data.type)),
                  subtitle: Text(formatDateTime(data.eventTime)),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.devices_other),
                      title: Text(device?.name ?? '#${data.deviceId}'),
                      subtitle: device == null
                          ? null
                          : Text(device.uniqueId),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          context.push('/device/${data.deviceId}'),
                    ),
                    if (position != null) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.place_outlined),
                        title: Text(
                          '${position.latitude.toStringAsFixed(5)}, '
                          '${position.longitude.toStringAsFixed(5)}',
                        ),
                        subtitle: Text(formatDateTime(position.fixTime)),
                      ),
                    ],
                  ],
                ),
              ),
              if (data.attributes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Attributes',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (final entry in data.attributes.entries)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${entry.key}: ${entry.value}',
                              style:
                                  Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
