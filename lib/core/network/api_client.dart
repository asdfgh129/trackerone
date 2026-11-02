import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 一个服务器档案同时描述 API 与位置上报入口。
///
/// 用户只需输入一个地址，剩余端口按 Traccar 默认规则推导。
class ServerProfile {
  const ServerProfile({
    required this.name,
    required this.apiBaseUrl,
    required this.reportUrl,
  });

  final String name;
  final String apiBaseUrl;
  final String reportUrl;

  /// 支持：
  /// - `https://host`
  /// - `https://host:8082`
  /// - `https://host/custom-path`
  factory ServerProfile.fromInput(String name, String input) {
    final uri = Uri.parse(input.trim());
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw const FormatException('请输入完整的服务器地址，例如 https://track.example.com');
    }

    final api = uri.replace(fragment: '').toString();
    final reportPort = uri.hasPort && uri.port != 8082 ? uri.port : 5055;
    final report = uri.replace(port: reportPort, path: '').toString();

    return ServerProfile(name: name, apiBaseUrl: api, reportUrl: report);
  }
}

/// 当前激活的服务器。实现时改为持久化 + 多档案。
final activeServerProvider = StateProvider<ServerProfile?>((ref) => null);

/// 会话 Token 由实现方从 Secure Storage 注入。
final authTokenProvider = StateProvider<String?>((ref) => null);

final dioProvider = Provider<Dio>((ref) {
  final profile = ref.watch(activeServerProvider);
  final token = ref.watch(authTokenProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: profile?.apiBaseUrl ?? '',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 20),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ),
  );

  // TODO(core): AuthInterceptor（401 登出）、RetryInterceptor（仅 GET）、
  // ErrorInterceptor（DioException -> AppFailure）、脱敏日志。
  return dio;
});
