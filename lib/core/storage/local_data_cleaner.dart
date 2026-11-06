import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'command_queue.dart';
import 'realtime_cache.dart';

/// 统一清理本机业务数据。
///
/// 只负责 drift 中的设备、位置、事件与指令队列；Token、账号 JSON 与
/// SharedPreferences 由调用方处理，避免把「会话」与「业务缓存」耦合在一起。
class LocalDataCleaner {
  const LocalDataCleaner({
    required RealtimeCache cache,
    required CommandQueue queue,
  })  : _cache = cache,
        _queue = queue;

  final RealtimeCache _cache;
  final CommandQueue _queue;

  /// 清理指定服务器（切换账号 / 删除服务器时使用）。
  Future<void> clearServer(String serverId) async {
    await _cache.clear(serverId);
    await _queue.clearServer(serverId);
  }

  /// 清理本机全部服务器的数据（“清除本地数据”与账号注销时使用）。
  Future<void> clearAll() async {
    await _cache.clearAll();
    await _queue.clearAll();
  }
}

final localDataCleanerProvider = Provider<LocalDataCleaner>((ref) {
  return LocalDataCleaner(
    cache: ref.watch(realtimeCacheProvider),
    queue: ref.watch(commandQueueProvider),
  );
});
