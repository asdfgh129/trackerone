import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/traccar_api.dart';
import '../../../core/push/push_gateway_registry.dart';
import '../../../core/push/push_service.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/storage/local_data_cleaner.dart';
import '../../../core/storage/token_store.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/entities/server_profile.dart';
import '../../../domain/failures.dart';
import '../../server/application/server_profiles_controller.dart';

class SessionState {
  const SessionState({
    this.server,
    this.token,
    this.account,
    this.offline = false,
  });

  final ServerProfile? server;
  final String? token;
  final Account? account;

  /// 冷启动时网络不可用，使用本地缓存的账号信息。
  final bool offline;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  bool get hasAccount => account != null;

  SessionState copyWith({
    ServerProfile? server,
    String? token,
    Account? account,
    bool? offline,
  }) {
    return SessionState(
      server: server ?? this.server,
      token: token ?? this.token,
      account: account ?? this.account,
      offline: offline ?? this.offline,
    );
  }
}

class SessionController extends AsyncNotifier<SessionState> {
  @override
  Future<SessionState> build() async {
    // 服务器档案变化（新增 / 切换 / 删除）时自动重建会话。
    final profiles = await ref.watch(serverProfilesProvider.future);
    final server = profiles.active;
    if (server == null) return const SessionState();

    final tokens = ref.watch(tokenStoreProvider);
    final token = await tokens.read(server.id);
    if (token == null || token.isEmpty) {
      return SessionState(server: server);
    }

    final prefs = ref.read(appPreferencesProvider);
    final cachedAccount = _parseAccount(
      await prefs.loadAccountJson(server.id),
    );

    try {
      final account =
          await TraccarApi(server: server, token: token).getSession();
      await prefs.saveAccountJson(
        server.id,
        jsonEncode(account.toJson()),
      );
      return SessionState(
        server: server,
        token: token,
        account: account,
      );
    } on AppFailure catch (failure) {
      if (failure.isUnauthorized) {
        await _clearLocal(server);
        return SessionState(server: server);
      }
      // 离线时保留 Token 与缓存账号，进入只读模式。
      return SessionState(
        server: server,
        token: token,
        account: cachedAccount,
        offline: true,
      );
    }
  }

  ServerProfile _requireServer() {
    final server = state.valueOrNull?.server ?? ref.read(activeServerProvider);
    if (server == null) {
      throw const AppFailure(
        FailureKind.invalidServer,
        '请先配置服务器',
        messageKey: 'errorServerRequired',
      );
    }
    return server;
  }

  Future<void> loginWithPassword({
    required String email,
    required String password,
  }) async {
    final server = _requireServer();
    final result = await TraccarApi(server: server).loginWithPassword(
      email: email,
      password: password,
    );
    await _persist(server, result);
    state = AsyncData(
      SessionState(
        server: server,
        token: result.token,
        account: result.account,
      ),
    );
  }

  Future<void> loginWithToken(String token) async {
    final server = _requireServer();
    final result =
        await TraccarApi(server: server).loginWithToken(token);
    await _persist(server, result);
    state = AsyncData(
      SessionState(
        server: server,
        token: result.token,
        account: result.account,
      ),
    );
  }

  Future<void> logout() async {
    final current = state.valueOrNull;
    final server = current?.server ?? ref.read(activeServerProvider);
    final token = current?.token;
    if (server != null && token != null) {
      await TraccarApi(server: server, token: token).revokeToken(token);
      await _clearLocal(server);
    }
    state = AsyncData(SessionState(server: server));
  }

  /// 注销当前 Traccar 账号，并清理本机全部业务数据。
  ///
  /// 普通用户可能没有 `DELETE /api/users/{id}` 权限；此时抛出 403，
  /// 由 UI 提示联系管理员，不能把失败伪装成成功。
  Future<void> deleteAccount() async {
    final current = state.valueOrNull;
    final server = current?.server ?? ref.read(activeServerProvider);
    final token = current?.token;
    final account = current?.account;
    if (server == null ||
        token == null ||
        token.isEmpty ||
        account == null) {
      throw const AppFailure(
        FailureKind.unauthorized,
        '登录已失效，无法注销账号',
        messageKey: 'errorDeleteAccountSessionExpired',
      );
    }

    await TraccarApi(server: server, token: token).deleteUser(account.id);
    await ref.read(localDataCleanerProvider).clearAll();
    await _clearLocal(server);
    state = AsyncData(SessionState(server: server));
  }

  /// 401 时由网络层/WebSocket 调用的强制登出。
  Future<void> invalidate() async {
    final current = state.valueOrNull;
    final server = current?.server ?? ref.read(activeServerProvider);
    if (server != null) await _clearLocal(server);
    state = AsyncData(SessionState(server: server));
  }

  /// 离线恢复后重新校验。
  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> _persist(ServerProfile server, AuthResult result) async {
    await ref
        .read(tokenStoreProvider)
        .write(server.id, result.token);
    await ref.read(appPreferencesProvider).saveAccountJson(
          server.id,
          jsonEncode(result.account.toJson()),
        );
  }

  Future<void> _clearLocal(ServerProfile server) async {
    final token = state.valueOrNull?.token ?? '';
    await ref.read(tokenStoreProvider).delete(server.id);
    await ref
        .read(appPreferencesProvider)
        .saveAccountJson(server.id, null);

    // 业务缓存与指令队列同样属于个人信息，退出登录 / 401 / 注销时一并清理。
    try {
      await ref.read(localDataCleanerProvider).clearServer(server.id);
    } catch (_) {
      // 清理失败不应阻断登出；下次“清除本地数据”会再次清理。
    }

    // 解绑推送别名，避免旧账号继续收到事件。
    try {
      await ref.read(pushServiceProvider).deleteAlias();
    } catch (_) {
      // 推送 SDK 未初始化或网络异常时忽略。
    }

    // 同步解绑自建推送网关里的别名。
    final holder = ref.read(pushAliasHolderProvider);
    final alias = holder.alias;
    if (alias != null && alias.isNotEmpty && token.isNotEmpty) {
      await ref.read(pushGatewayRegistryProvider).unregisterAlias(
            alias: alias,
            token: token,
          );
    }
    holder.clear();
  }

  static Account? _parseAccount(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map
          ? Account.fromJson(decoded.cast<String, dynamic>())
          : null;
    } catch (_) {
      return null;
    }
  }
}

final sessionProvider =
    AsyncNotifierProvider<SessionController, SessionState>(
  SessionController.new,
);
