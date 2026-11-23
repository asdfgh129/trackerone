import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收件箱本地状态：已读标记。
///
/// 按 `serverId:userId` 隔离，切换账号或服务器时不会串消息。
/// 消息正文与增量游标不落盘：冷启动重新拉取最新一页，
/// 避免在本机长期保存调度内容。
abstract interface class InboxStore {
  Future<Set<String>> readReadIds(String scope);
  Future<void> writeReadIds(String scope, Set<String> ids);

  /// 清除全部服务器/账号的收件箱本地状态（退出登录、注销、清除数据）。
  Future<void> clearAll();
}

class PrefsInboxStore implements InboxStore {
  const PrefsInboxStore();

  static const String _prefix = 'inbox.v1';

  /// 已读 id 最多保留 500 条，避免无限增长。
  static const int _maxReadIds = 500;

  String _readKey(String scope) => '$_prefix.$scope.read';

  @override
  Future<Set<String>> readReadIds(String scope) async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_readKey(scope)) ?? const <String>[]).toSet();
  }

  @override
  Future<void> writeReadIds(String scope, Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed =
        ids.length <= _maxReadIds
            ? ids
            : ids.skip(ids.length - _maxReadIds).toSet();
    await prefs.setStringList(_readKey(scope), trimmed.toList());
  }

  @override
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((key) => key.startsWith(_prefix)).toList();
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

final inboxStoreProvider = Provider<InboxStore>(
  (ref) => const PrefsInboxStore(),
);
