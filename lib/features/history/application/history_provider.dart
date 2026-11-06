import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../domain/entities/models.dart';

enum HistoryRange { today, yesterday, last7Days }

class HistoryQuery {
  const HistoryQuery({required this.deviceId, required this.range});

  final int deviceId;
  final HistoryRange range;

  ({DateTime from, DateTime to}) get window {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return switch (range) {
      HistoryRange.today => (from: startOfToday, to: now),
      HistoryRange.yesterday => (
          from: startOfToday.subtract(const Duration(days: 1)),
          to: startOfToday,
        ),
      HistoryRange.last7Days => (
          from: startOfToday.subtract(const Duration(days: 6)),
          to: now,
        ),
    };
  }

  @override
  bool operator ==(Object other) =>
      other is HistoryQuery &&
      other.deviceId == deviceId &&
      other.range == range;

  @override
  int get hashCode => Object.hash(deviceId, range);
}

/// 历史轨迹按设备与时间范围缓存；切换范围时自动重新请求。
final historyProvider =
    FutureProvider.autoDispose.family<List<Position>, HistoryQuery>(
  (ref, query) async {
    final api = ref.watch(traccarApiProvider);
    if (api == null) return const [];
    final window = query.window;
    return api.getHistory(
      deviceId: query.deviceId,
      from: window.from,
      to: window.to,
    );
  },
);
