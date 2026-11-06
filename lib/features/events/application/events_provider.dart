import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../domain/entities/models.dart';

/// 最近 24 小时的历史事件。实时事件由 [realtimeProvider] 提供。
final eventHistoryProvider =
    FutureProvider.autoDispose<List<DeviceEvent>>((ref) async {
  final api = ref.watch(traccarApiProvider);
  if (api == null) return const [];
  final now = DateTime.now();
  return api.getEvents(
    from: now.subtract(const Duration(hours: 24)),
    to: now,
  );
});
