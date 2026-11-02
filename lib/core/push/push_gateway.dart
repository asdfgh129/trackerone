/// 推送抽象。
///
/// 中国大陆不能用 FCM（无 GMS、长连接易被清理），因此推送必须可替换：
/// - [FcmPushGateway]：海外 / 开发
/// - [JpushPushGateway]：中国大陆生产（聚合小米 / 华为 / OPPO / vivo 厂商通道）
///
/// 业务层只消费 [PushMessage]，不关心底层通道。
library;

/// 归一化后的推送消息。
///
/// 服务端（Traccar 自定义 notificator）与推送网关约定以下字段：
/// - `eventId`：事件 id，点击后跳转 `/event/:id`
/// - `command`：远程指令类型，如 `positionSingle`
/// - `title` / `body`：通知文案
class PushMessage {
  const PushMessage({
    this.eventId,
    this.command,
    this.title,
    this.body,
    this.data = const {},
  });

  final int? eventId;
  final String? command;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;

  bool get isCommand => command != null && command!.isNotEmpty;

  factory PushMessage.fromData(Map<String, dynamic> data) {
    return PushMessage(
      eventId: _asInt(data['eventId']),
      command: _asString(data['command']),
      title: _asString(data['title']),
      body: _asString(data['body']),
      data: data,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static String? _asString(Object? value) {
    final text = value?.toString();
    return text == null || text.isEmpty ? null : text;
  }
}

/// 推送通道接口。
///
/// [alias] 用于把设备映射到用户，推荐格式 `u{userId}@{serverId}`。
/// 服务端只按 alias 推送，不直接持有设备 Token。
abstract interface class PushGateway {
  /// 通道标识：`fcm` / `jpush` / `none`。
  String get id;

  /// 初始化 SDK、申请通知权限、注册 [alias]。
  Future<void> initialize({required String alias});

  /// 登录用户或服务器变化时更新别名。
  Future<void> updateAlias(String alias);

  /// 前台 / 点击通知产生的消息流。
  Stream<PushMessage> get messages;

  /// 冷启动点击通知时携带的消息（消费一次后清空）。
  Future<PushMessage?> takeInitialMessage();

  Future<void> dispose();
}

/// 不做任何事的实现：未配置推送时使用，应用内仍可通过 WebSocket 收事件。
class NoopPushGateway implements PushGateway {
  @override
  String get id => 'none';

  @override
  Future<void> initialize({required String alias}) async {}

  @override
  Future<void> updateAlias(String alias) async {}

  @override
  Stream<PushMessage> get messages => const Stream<PushMessage>.empty();

  @override
  Future<PushMessage?> takeInitialMessage() async => null;

  @override
  Future<void> dispose() async {}
}
