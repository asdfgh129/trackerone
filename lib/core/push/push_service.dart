import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/build_config.dart';
import 'fcm_push_gateway.dart';
import 'jpush_push_gateway.dart';
import 'push_gateway.dart';

/// 按构建配置选择推送通道。
///
/// 中国大陆生产包：`--dart-define=PUSH_PROVIDER=jpush`
/// 海外 / 开发包：`--dart-define=PUSH_PROVIDER=fcm`
final pushGatewayProvider = Provider<PushGateway>((ref) {
  final gateway = switch (BuildConfig.pushProvider) {
    'fcm' => FcmPushGateway(),
    'jpush' => JpushPushGateway(),
    _ => NoopPushGateway(),
  };
  ref.onDispose(gateway.dispose);
  return gateway;
});

final pushServiceProvider = Provider<PushService>(
  (ref) => PushService(ref.watch(pushGatewayProvider)),
);

/// 推送服务门面：把 alias 规则、注册时机、消息路由集中在一处。
///
/// 推送链路（中国大陆）：
/// ```
/// Traccar 事件
///   -> NotificatorWebhook（服务端插件）
///   -> 自建推送网关（鉴权 / 去重 / 模板 / 限流）
///   -> JPush REST（按 alias）
///   -> 厂商通道 -> App
/// ```
class PushService {
  const PushService(this._gateway);

  final PushGateway _gateway;

  /// alias 规范：`u{userId}@{serverId}`。
  ///
  /// 带 serverId 是为了支持一个用户连接多个 Traccar 服务器时不串消息。
  static String aliasFor({required int userId, required int serverId}) =>
      'u$userId@$serverId';

  Future<void> initialize({required int userId, required int serverId}) {
    return _gateway.initialize(
      alias: aliasFor(userId: userId, serverId: serverId),
    );
  }

  Future<void> updateAlias({required int userId, required int serverId}) {
    return _gateway.updateAlias(aliasFor(userId: userId, serverId: serverId));
  }

  Stream<PushMessage> get messages => _gateway.messages;

  /// 冷启动点击通知：登录完成后再调用，避免路由竞态。
  Future<PushMessage?> takeInitialMessage() => _gateway.takeInitialMessage();
}
