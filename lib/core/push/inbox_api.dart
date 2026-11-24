import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/inbox_message.dart';
import '../../domain/failures.dart';
import '../config/build_config.dart';

/// 一页收件箱消息。
class InboxPage {
  const InboxPage({required this.messages, this.nextCursor});

  final List<InboxMessage> messages;

  /// 下次增量拉取的游标；为空表示服务端没有更多数据。
  final String? nextCursor;
}

/// 收件箱接口。
///
/// 与推送网关约定：
/// - `GET  /v1/messages?since=<cursor>&limit=<n>` → `{"messages":[...],"nextCursor":"..."}`
/// - `POST /v1/messages/{id}/ack`
///
/// 鉴权复用 Traccar Token（`Authorization: Bearer`），网关据此校验用户归属。
abstract interface class InboxApi {
  /// 是否已配置网关地址；未配置时 UI 显示说明而不是报错。
  bool get enabled;

  Future<InboxPage> fetch({
    required String token,
    String? cursor,
    int limit = 50,
  });

  Future<void> ack({required String token, required String id});
}

class GatewayInboxApi implements InboxApi {
  GatewayInboxApi({Dio? client, String? baseUrl})
    : _baseUrl = (baseUrl ?? BuildConfig.pushGatewayUrl).trim(),
      _client = client ?? Dio();

  final String _baseUrl;
  final Dio _client;

  @override
  bool get enabled => _baseUrl.isNotEmpty;

  @override
  Future<InboxPage> fetch({
    required String token,
    String? cursor,
    int limit = 50,
  }) async {
    _requireEnabled();
    try {
      final response = await _client.get<Object?>(
        '$_baseUrl/v1/messages',
        queryParameters: {
          if (cursor != null && cursor.isNotEmpty) 'since': cursor,
          'limit': limit,
        },
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      final body = response.data;
      final map =
          body is Map
              ? body.cast<String, dynamic>()
              : const <String, dynamic>{};
      final raw = map['messages'];
      final messages =
          raw is List
              ? raw
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (item) =>
                        InboxMessage.fromJson(item.cast<String, dynamic>()),
                  )
                  .where((message) => message.id.isNotEmpty)
                  .toList(growable: false)
              : const <InboxMessage>[];
      final next = map['nextCursor']?.toString();
      return InboxPage(
        messages: messages,
        // 网关在「没有更多」时返回空串，统一当成 null，避免重置游标。
        nextCursor: (next == null || next.isEmpty) ? null : next,
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  @override
  Future<void> ack({required String token, required String id}) async {
    _requireEnabled();
    try {
      await _client.post<void>(
        '$_baseUrl/v1/messages/${Uri.encodeComponent(id)}/ack',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
    } on DioException catch (error) {
      throw _mapError(error);
    }
  }

  void _requireEnabled() {
    if (!enabled) {
      throw const AppFailure(
        FailureKind.invalidServer,
        '未配置推送网关',
        messageKey: 'inboxGatewayMissing',
      );
    }
  }

  AppFailure _mapError(DioException error) {
    final status = error.response?.statusCode;
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return AppFailure(
        FailureKind.timeout,
        '连接消息服务超时',
        cause: error,
        messageKey: 'errorTimeout',
      );
    }
    if (error.type == DioExceptionType.connectionError) {
      return AppFailure(
        FailureKind.network,
        '无法连接消息服务',
        cause: error,
        messageKey: 'errorNetwork',
      );
    }
    if (status == 401 || status == 403) {
      return AppFailure(
        FailureKind.unauthorized,
        '消息服务拒绝访问',
        statusCode: status,
        cause: error,
        messageKey: 'errorSessionExpired',
      );
    }
    if (status != null && status >= 500) {
      return AppFailure(
        FailureKind.server,
        '消息服务异常',
        statusCode: status,
        cause: error,
        messageKey: 'errorServer',
        messageArgs: {'status': '$status'},
      );
    }
    return AppFailure(
      FailureKind.unknown,
      '消息服务请求失败',
      statusCode: status,
      cause: error,
      messageKey: 'errorUnrecognizedResponse',
    );
  }
}

/// 本地联调用的假收件箱。
///
/// `--dart-define=INBOX_DEMO=true` 时启用，用于在没有网关的情况下
/// 走通「列表 → 未读 → 执行指令 → 标记已读」的完整交互。
class DemoInboxApi implements InboxApi {
  DemoInboxApi({this.delay = const Duration(milliseconds: 300)});

  final Duration delay;
  final Set<String> _acked = {};
  var _served = false;

  static final List<InboxMessage> _seed = [
    InboxMessage(
      id: 'demo-command-1',
      kind: InboxKind.command,
      title: '指令：单次定位',
      body: '调度要求对设备 #1 立即上报一次位置。',
      data: const {'deviceId': 1, 'command': 'positionSingle'},
      createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
    ),
    InboxMessage(
      id: 'demo-notice-1',
      kind: InboxKind.notice,
      title: '围栏告警：驶出「公司园区」',
      body: '京A12345 于 10:24 驶出围栏。',
      createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
    ),
    InboxMessage(
      id: 'demo-result-1',
      kind: InboxKind.notice,
      data: const {
        'eventType': 'commandResult',
        'deviceId': 1,
        'result': 'success',
        'success': true,
      },
      createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    ),
    InboxMessage(
      id: 'demo-chat-1',
      kind: InboxKind.chat,
      title: '调度员',
      body: '请确认车辆是否已到达仓库。',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    ),
  ];

  @override
  bool get enabled => true;

  @override
  Future<InboxPage> fetch({
    required String token,
    String? cursor,
    int limit = 50,
  }) async {
    await Future<void>.delayed(delay);
    if (_served) return const InboxPage(messages: []);
    _served = true;
    return InboxPage(
      messages: _seed.where((m) => !_acked.contains(m.id)).toList(),
      nextCursor: 'demo-1',
    );
  }

  @override
  Future<void> ack({required String token, required String id}) async {
    _acked.add(id);
  }
}

final inboxApiProvider = Provider<InboxApi>((ref) {
  if (BuildConfig.inboxDemo) return DemoInboxApi();
  return GatewayInboxApi();
});
