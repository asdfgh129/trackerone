import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/map/geo_point.dart';
import '../../../core/map/map_models.dart';
import '../../../core/map/tracker_map_view.dart';
import '../../../domain/entities/models.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../realtime/application/realtime_controller.dart';
import '../application/history_provider.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({required this.deviceId, super.key});

  final int deviceId;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  HistoryRange _range = HistoryRange.today;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final device =
        ref.watch(realtimeProvider).valueOrNull?.devices[widget.deviceId];
    final query = HistoryQuery(deviceId: widget.deviceId, range: _range);
    final history = ref.watch(historyProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: Text(device?.name ?? l10n.historyTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () => ref.invalidate(historyProvider(query)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: SegmentedButton<HistoryRange>(
              segments: [
                ButtonSegment(
                  value: HistoryRange.today,
                  label: Text(l10n.historyToday),
                ),
                ButtonSegment(
                  value: HistoryRange.yesterday,
                  label: Text(l10n.historyYesterday),
                ),
                ButtonSegment(
                  value: HistoryRange.last7Days,
                  label: Text(l10n.historyLast7Days),
                ),
              ],
              selected: {_range},
              onSelectionChanged: (selection) {
                setState(() => _range = selection.first);
              },
            ),
          ),
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error:
                  (error, _) => Center(
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
                            onPressed:
                                () => ref.invalidate(historyProvider(query)),
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    ),
                  ),
              data: (trace) {
                final positions = trace.positions;
                if (positions.isEmpty) {
                  return Center(
                    child: Text(
                      l10n.historyNoData,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  );
                }
                return _HistoryBody(
                  positions: positions,
                  sampled: trace.sampled,
                  deviceId: widget.deviceId,
                  label: device?.name ?? l10n.deviceTitle,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.positions,
    required this.deviceId,
    required this.label,
    this.sampled = false,
  });

  final List<Position> positions;
  final int deviceId;
  final String label;

  /// 服务端点数超过上限时已抽稀，界面需要说明。
  final bool sampled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final points = _thin(
      positions
          .map((position) => GeoPoint(position.latitude, position.longitude))
          .toList(growable: false),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        SizedBox(
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: TrackerMapView(
              markers: [
                MapDeviceMarker(
                  deviceId: deviceId,
                  label: label,
                  point: points.last,
                ),
              ],
              trails: [MapTrail(deviceId: deviceId, points: points)],
              initialTarget: points.last,
              initialZoom: 14,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.historyPoints(positions.length),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '${formatDateTime(positions.first.fixTime)} → ${formatDateTime(positions.last.fixTime)}',
                  style: theme.textTheme.bodySmall,
                ),
                if (sampled) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.historySampled,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final position in positions.reversed.take(100))
          ListTile(
            dense: true,
            leading: const Icon(Icons.place_outlined, size: 18),
            title: Text(formatDateTime(position.fixTime)),
            subtitle: Text(
              '${position.latitude.toStringAsFixed(5)}, '
              '${position.longitude.toStringAsFixed(5)} · '
              '${formatSpeed(position.speedMetersPerSecond)}',
            ),
          ),
      ],
    );
  }

  /// 渲染抽稀：超过 1000 点时按步长采样，首尾点始终保留。
  static List<GeoPoint> _thin(List<GeoPoint> points) {
    const maxPoints = 1000;
    if (points.length <= maxPoints) return points;
    final step = (points.length / maxPoints).ceil();
    final result = <GeoPoint>[];
    for (var i = 0; i < points.length; i += step) {
      result.add(points[i]);
    }
    if (result.last != points.last) result.add(points.last);
    return result;
  }
}
