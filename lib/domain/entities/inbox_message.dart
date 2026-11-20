/// 服务端下发的消息类型。
enum InboxKind {
  /// 需要用户执行/确认的设备指令（断油、重启等）。
  command,

  /// 一般通知（告警、运营公告）。
  notice,

  /// 人与人之间的消息（调度、客服回复）。
  chat,

  /// 未知类型：保留展示，不提供操作。
  unknown;

  static InboxKind parse(Object? value) {
    return switch (value?.toString()) {
      'command' => InboxKind.command,
      'notice' => InboxKind.notice,
      'chat' => InboxKind.chat,
      _ => InboxKind.unknown,
    };
  }
}

/// 收件箱消息。
///
/// 契约（网关 `POST /v1/messages` 与 `GET /v1/messages`）：
/// ```json
/// {
///   "id": "msg_123",
///   "kind": "command",
///   "title": "指令：断油",
///   "body": "调度要求对京A12345 断油",
///   "data": {"deviceId": 12, "command": "engineStop", "attributes": {}},
///   "createdAt": "2026-11-19T10:00:00Z",
///   "expiresAt": "2026-11-19T11:00:00Z"
/// }
/// ```
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.kind,
    this.title,
    this.body,
    this.data = const {},
    this.createdAt,
    this.expiresAt,
  });

  final String id;
  final InboxKind kind;
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  final DateTime? createdAt;
  final DateTime? expiresAt;

  int? get deviceId => _asInt(data['deviceId']);

  /// 指令类型（Traccar `type`），例如 `engineStop`。
  String? get command => _asString(data['command']);

  Map<String, dynamic> get commandAttributes {
    final value = data['attributes'];
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  bool get hasCommand =>
      kind == InboxKind.command &&
      deviceId != null &&
      (command?.isNotEmpty ?? false);

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && expiry.isBefore(DateTime.now());
  }

  factory InboxMessage.fromJson(Map<String, dynamic> json) {
    return InboxMessage(
      id: json['id']?.toString() ?? '',
      kind: InboxKind.parse(json['kind']),
      title: _asString(json['title']),
      body: _asString(json['body']),
      data: _asMap(json['data']),
      createdAt: _asDate(json['createdAt']),
      expiresAt: _asDate(json['expiresAt']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    if (title != null) 'title': title,
    if (body != null) 'body': body,
    if (data.isNotEmpty) 'data': data,
    if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
    if (expiresAt != null) 'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };

  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
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

  static DateTime? _asDate(Object? value) {
    if (value is DateTime) return value;
    final text = _asString(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }
}
