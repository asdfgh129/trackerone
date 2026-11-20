import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../push/inbox_store.dart';
import 'command_queue.dart';
import 'realtime_cache.dart';

/// 统一清理本机业务数据。
///
/// 负责 drift 中的设备、位置、事件、指令队列，以及收件箱的游标与已读标记；
/// Token、账号 JSON 与其余 SharedPreferences 由调用方处理，
/// 避免把「会话」与「业务缓存」耦合在一起。
class LocalDataCleaner {
  const LocalDataCleaner({
    required RealtimeCache cache,
    required CommandQueue queue,
    required InboxStore inbox,
  }) : _cache = cache,
       _queue = queue,
       _inbox = inbox;

  final RealtimeCache _cache;
  final CommandQueue _queue;
  final InboxStore _inbox;

  /// 清理指定服务器（切换账号 / 删除服务器时使用）。
  Future<void> clearServer(String serverId) async {
    await _cache.clear(serverId);
    await _queue.clearServer(serverId);
    // 消息可能包含调度内容与位置，按服务器清除时一并清空收件箱缓存。
    await _inbox.clearAll();
  }

  /// 清理本机全部服务器的数据（“清除本地数据”与账号注销时使用）。
  Future<void> clearAll() async {
    await _cache.clearAll();
    await _queue.clearAll();
    await _inbox.clearAll();
  }
}

final localDataCleanerProvider = Provider<LocalDataCleaner>((ref) {
  return LocalDataCleaner(
    cache: ref.watch(realtimeCacheProvider),
    queue: ref.watch(commandQueueProvider),
    inbox: ref.watch(inboxStoreProvider),
  );
});
