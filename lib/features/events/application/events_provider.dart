import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../domain/entities/models.dart';

/// 事件历史的时间范围。
enum EventRange {
  last24Hours(Duration(hours: 24)),
  last7Days(Duration(days: 7)),
  last30Days(Duration(days: 30));

  const EventRange(this.duration);

  final Duration duration;
}

/// 事件历史查询：范围 + 条数上限。
///
/// Traccar 的 `/api/reports/events` 不支持分页，因此客户端只拉取时间窗口，
/// 再按时间倒序截断到 [limit]，避免 30 天全量事件拖慢列表。
class EventHistoryQuery {
  const EventHistoryQuery({
    this.range = EventRange.last24Hours,
    this.limit = 300,
  });

  final EventRange range;
  final int limit;

  @override
  bool operator ==(Object other) =>
      other is EventHistoryQuery &&
      other.range == range &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(range, limit);
}

/// 历史事件。实时事件由 [realtimeProvider] 提供。
final eventHistoryProvider = FutureProvider.autoDispose
    .family<List<DeviceEvent>, EventHistoryQuery>((ref, query) async {
      final api = ref.watch(traccarApiProvider);
      if (api == null) return const [];
      final now = DateTime.now();
      final events = await api.getEvents(
        from: now.subtract(query.range.duration),
        to: now,
      );
      events.sort((a, b) {
        final left = a.eventTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.eventTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      return events.take(query.limit).toList(growable: false);
    });
