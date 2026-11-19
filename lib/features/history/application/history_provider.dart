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

/// 历史轨迹查询结果。
///
/// Traccar 的 `/api/positions` 一次返回整个区间且不分页，长时间范围（7 天、
/// 高频率上报）可能返回数万个点。这里按天分段请求，并在超过
/// [historyMaxPoints] 时均匀抽稀：地图与列表只需要轨迹形状，
/// 原始点数由 [sampled] 标识，界面据此提示用户。
class HistoryTrace {
  const HistoryTrace({required this.positions, this.sampled = false});

  static const HistoryTrace empty = HistoryTrace(positions: <Position>[]);

  final List<Position> positions;

  /// true 表示点数超过上限，已抽稀。
  final bool sampled;
}

/// 单次查询保留的最大点数。超过后按步长采样。
const int historyMaxPoints = 20000;

/// 历史轨迹按设备与时间范围缓存；切换范围时自动重新请求。
final historyProvider = FutureProvider.autoDispose
    .family<HistoryTrace, HistoryQuery>((ref, query) async {
      final api = ref.watch(traccarApiProvider);
      if (api == null) return HistoryTrace.empty;

      final window = query.window;
      final positions = <Position>[];
      var cursor = window.from;
      // 分段请求：单次响应过大时更容易超时，也便于在极端情况下提前止损。
      while (cursor.isBefore(window.to)) {
        final next = cursor.add(const Duration(days: 1));
        final chunkEnd = next.isAfter(window.to) ? window.to : next;
        final chunk = await api.getHistory(
          deviceId: query.deviceId,
          from: cursor,
          to: chunkEnd,
        );
        _appendUnique(positions, chunk);
        cursor = chunkEnd;
        if (positions.length >= historyMaxPoints * 2) break;
      }

      final sampled = positions.length > historyMaxPoints;
      return HistoryTrace(
        positions: sampled ? samplePositions(positions, historyMaxPoints) : positions,
        sampled: sampled,
      );
    });

/// 分段边界可能重复返回同一个点，按时间与坐标去重。
void _appendUnique(List<Position> target, List<Position> chunk) {
  for (final position in chunk) {
    final last = target.isEmpty ? null : target.last;
    if (last != null &&
        last.fixTime == position.fixTime &&
        last.latitude == position.latitude &&
        last.longitude == position.longitude) {
      continue;
    }
    target.add(position);
  }
}

/// 均匀抽稀，保留首尾点，保证轨迹首尾完整。
///
/// 公开以便单测；调用方应保证 [positions] 已按时间升序。
List<Position> samplePositions(List<Position> positions, int maxPoints) {
  if (positions.length <= maxPoints) return positions;
  final step = (positions.length / maxPoints).ceil();
  final result = <Position>[];
  for (var i = 0; i < positions.length; i += step) {
    result.add(positions[i]);
  }
  if (!identical(result.last, positions.last)) result.add(positions.last);
  return result;
}
