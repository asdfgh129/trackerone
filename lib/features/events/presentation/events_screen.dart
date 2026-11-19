import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/entities/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../realtime/application/realtime_controller.dart';
import '../application/events_provider.dart';

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  EventRange _range = EventRange.last24Hours;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final realtime = ref.watch(realtimeProvider).valueOrNull;
    final query = EventHistoryQuery(range: _range);
    final history = ref.watch(eventHistoryProvider(query));

    final merged = <int, DeviceEvent>{};
    for (final event in history.valueOrNull ?? const <DeviceEvent>[]) {
      merged[event.id] = event;
    }
    for (final event in realtime?.events ?? const <DeviceEvent>[]) {
      merged[event.id] = event;
    }
    final events =
        merged.values.toList()..sort((a, b) {
          final left = a.eventTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.eventTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.eventsTitle),
        actions: [
          if (realtime?.connected ?? false)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Chip(
                avatar: const Icon(Icons.wifi, size: 14),
                label: Text(l10n.eventsLive),
                visualDensity: VisualDensity.compact,
              ),
            ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () {
              ref.invalidate(eventHistoryProvider(query));
              ref.read(realtimeProvider.notifier).refresh();
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: SegmentedButton<EventRange>(
              segments: [
                ButtonSegment(
                  value: EventRange.last24Hours,
                  label: Text(l10n.eventsRange24h),
                ),
                ButtonSegment(
                  value: EventRange.last7Days,
                  label: Text(l10n.eventsRange7d),
                ),
                ButtonSegment(
                  value: EventRange.last30Days,
                  label: Text(l10n.eventsRange30d),
                ),
              ],
              showSelectedIcon: false,
              selected: {_range},
              onSelectionChanged: (selection) {
                setState(() => _range = selection.first);
              },
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(eventHistoryProvider(query));
                await ref.read(realtimeProvider.notifier).refresh();
              },
              child:
                  events.isEmpty
                      ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: _EmptyEvents(
                              loading: history.isLoading,
                              error: history.error?.toString(),
                              onRetry:
                                  () => ref.invalidate(
                                    eventHistoryProvider(query),
                                  ),
                            ),
                          ),
                        ],
                      )
                      : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        itemCount: events.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final truncated =
                                (history.valueOrNull?.length ?? 0) >=
                                query.limit;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Text(
                                    l10n.eventsHistory,
                                    style:
                                        Theme.of(context).textTheme.labelMedium,
                                  ),
                                  const Spacer(),
                                  if (truncated)
                                    Text(
                                      l10n.eventsLimited(query.limit),
                                      style:
                                          Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                    ),
                                ],
                              ),
                            );
                          }
                          final event = events[index - 1];
                          final device = realtime?.devices[event.deviceId];
                          return Card(
                            child: ListTile(
                              onTap: () => context.push('/event/${event.id}'),
                              leading: CircleAvatar(
                                backgroundColor:
                                    Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerHighest,
                                child: Icon(eventIcon(event.type), size: 20),
                              ),
                              title: Text(humanizeEventType(event.type)),
                              subtitle: Text(
                                '${device?.name ?? '#${event.deviceId}'} · ${formatDateTime(event.eventTime)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.chevron_right),
                            ),
                          );
                        },
                      ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEvents extends StatelessWidget {
  const _EmptyEvents({
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text(error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
            ],
          ),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(l10n.eventsEmpty, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              l10n.eventsEmptyBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
