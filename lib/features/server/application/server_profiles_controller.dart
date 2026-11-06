import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/app_preferences.dart';
import '../../../core/storage/local_data_cleaner.dart';
import '../../../core/storage/token_store.dart';
import '../../../domain/entities/server_profile.dart';

class ServerProfilesState {
  const ServerProfilesState({
    this.servers = const [],
    this.activeId,
  });

  final List<ServerProfile> servers;
  final String? activeId;

  ServerProfile? get active {
    if (servers.isEmpty) return null;
    for (final server in servers) {
      if (server.id == activeId) return server;
    }
    return servers.first;
  }

  bool get isEmpty => servers.isEmpty;

  ServerProfilesState copyWith({
    List<ServerProfile>? servers,
    String? activeId,
    bool clearActive = false,
  }) {
    return ServerProfilesState(
      servers: servers ?? this.servers,
      activeId: clearActive ? null : (activeId ?? this.activeId),
    );
  }
}

class ServerProfilesController extends AsyncNotifier<ServerProfilesState> {
  @override
  Future<ServerProfilesState> build() async {
    final prefs = ref.watch(appPreferencesProvider);
    final servers = await prefs.loadServers();
    var activeId = await prefs.loadActiveServerId();

    // 档案可能被删除，回退到第一个可用服务器。
    if (servers.isNotEmpty &&
        !servers.any((server) => server.id == activeId)) {
      activeId = servers.first.id;
      await prefs.saveActiveServerId(activeId);
    }
    if (servers.isEmpty && activeId != null) {
      activeId = null;
      await prefs.saveActiveServerId(null);
    }

    return ServerProfilesState(servers: servers, activeId: activeId);
  }

  /// 新增或更新档案（按归一化 URL 去重）。
  Future<void> save(ServerProfile profile, {bool activate = true}) async {
    final current = state.valueOrNull ?? const ServerProfilesState();
    final servers = [...current.servers];
    final index = servers.indexWhere((item) => item.id == profile.id);
    if (index >= 0) {
      servers[index] = profile;
    } else {
      servers.add(profile);
    }

    final activeId = activate ? profile.id : current.activeId;
    state = AsyncData(
      ServerProfilesState(servers: servers, activeId: activeId),
    );

    final prefs = ref.read(appPreferencesProvider);
    await prefs.saveServers(servers);
    if (activate) await prefs.saveActiveServerId(activeId);
  }

  Future<void> setActive(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (!current.servers.any((server) => server.id == id)) return;

    state = AsyncData(current.copyWith(activeId: id));
    await ref.read(appPreferencesProvider).saveActiveServerId(id);
  }

  Future<void> remove(String id) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final servers =
        current.servers.where((server) => server.id != id).toList();
    String? activeId = current.activeId;
    if (activeId == id) {
      activeId = servers.isEmpty ? null : servers.first.id;
    }

    state = AsyncData(
      ServerProfilesState(servers: servers, activeId: activeId),
    );
    final prefs = ref.read(appPreferencesProvider);
    await prefs.saveServers(servers);
    await prefs.saveActiveServerId(activeId);
    await ref.read(tokenStoreProvider).delete(id);
    await prefs.saveAccountJson(id, null);
    // 删除服务器档案时同步清掉该服务器的轨迹、事件与指令记录。
    try {
      await ref.read(localDataCleanerProvider).clearServer(id);
    } catch (_) {
      // 清理失败不阻断档案删除。
    }
  }
}

final serverProfilesProvider =
    AsyncNotifierProvider<ServerProfilesController, ServerProfilesState>(
  ServerProfilesController.new,
);

/// 当前激活服务器；未配置时为 null。
final activeServerProvider = Provider<ServerProfile?>((ref) {
  final state = ref.watch(serverProfilesProvider);
  return state.valueOrNull?.active;
});
