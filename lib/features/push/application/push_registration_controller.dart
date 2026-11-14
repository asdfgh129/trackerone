import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/traccar_api.dart';
import '../../../core/privacy/privacy_consent.dart';
import '../../../core/push/push_gateway.dart';
import '../../../core/push/push_gateway_registry.dart';
import '../../../core/push/push_service.dart';
import '../../auth/application/session_controller.dart';

/// 推送注册状态，用于诊断页与排障。
class PushRegistrationState {
  const PushRegistrationState({
    required this.providerId,
    this.alias,
    this.registered = false,
    this.lastError,
    this.lastMessage,
    this.lastMessageAt,
  });

  /// `jpush` / `fcm` / `none`。
  final String providerId;

  /// 注册到推送服务的别名；未登录时为 null。
  final String? alias;

  final bool registered;
  final String? lastError;
  final PushMessage? lastMessage;
  final DateTime? lastMessageAt;

  bool get enabled => providerId != 'none';

  PushRegistrationState copyWith({
    String? alias,
    bool? registered,
    String? lastError,
    PushMessage? lastMessage,
    DateTime? lastMessageAt,
    bool clearError = false,
  }) {
    return PushRegistrationState(
      providerId: providerId,
      alias: alias ?? this.alias,
      registered: registered ?? this.registered,
      lastError: clearError ? null : (lastError ?? this.lastError),
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
    );
  }
}

/// 登录后把当前用户注册为推送目标。
///
/// alias 规则：`u{userId}@{serverId}`，其中 `serverId` 来自 Traccar
/// `/api/server`，这样同一用户在多个服务器上不会串消息。
///
/// 推送失败（未配置 AppKey、无网络、服务端版本过旧）只记录到
/// [PushRegistrationState.lastError]，不阻断登录。
class PushRegistrationController extends AsyncNotifier<PushRegistrationState> {
  @override
  Future<PushRegistrationState> build() async {
    final gateway = ref.watch(pushGatewayProvider);
    final service = ref.watch(pushServiceProvider);
    final base = PushRegistrationState(providerId: gateway.id);

    // 未同意隐私政策 / 正在读取授权状态时，绝不初始化推送 SDK。
    final consentValue = ref.watch(privacyConsentProvider).valueOrNull;
    if (consentValue != true) {
      return base;
    }

    final subscription = service.messages.listen((message) {
      final current = state.valueOrNull;
      if (current == null) return;
      state = AsyncData(
        current.copyWith(
          lastMessage: message,
          lastMessageAt: DateTime.now(),
        ),
      );
    });
    ref.onDispose(subscription.cancel);

    final session = await ref.watch(sessionProvider.future);
    if (!session.isAuthenticated) return base;

    final server = session.server;
    final account = session.account;
    if (server == null || account == null) return base;

    try {
      final info = await TraccarApi(
        server: server,
        token: session.token,
      ).getServerInfo();
      final alias = PushService.aliasFor(
        userId: account.id,
        serverId: info.id,
      );
      await service.initialize(userId: account.id, serverId: info.id);

      // 同步别名到自建推送网关（未配置 PUSH_GATEWAY_URL 时自动跳过）。
      final registered = await ref.read(pushGatewayRegistryProvider).registerAlias(
            alias: alias,
            token: session.token ?? '',
            platform: defaultTargetPlatform == TargetPlatform.iOS
                ? 'ios'
                : 'android',
          );
      if (registered) {
        ref.read(pushAliasHolderProvider).remember(
              alias: alias,
              token: session.token ?? '',
            );
      }

      return base.copyWith(
        alias: alias,
        registered: base.enabled,
        clearError: true,
      );
    } catch (error) {
      return base.copyWith(
        registered: false,
        lastError: error.toString(),
      );
    }
  }

  /// 手动重试注册（例如用户刚打开通知权限）。
  Future<void> retry() async {
    ref.invalidateSelf();
    await ref.read(pushRegistrationProvider.future);
  }
}

final pushRegistrationProvider =
    AsyncNotifierProvider<PushRegistrationController, PushRegistrationState>(
  PushRegistrationController.new,
);
