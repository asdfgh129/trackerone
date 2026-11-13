import 'dart:convert';
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../../domain/entities/models.dart';
import '../../domain/entities/server_profile.dart';
import '../../domain/failures.dart';

/// Traccar Server REST 客户端。
///
/// 只负责 HTTP 与 DTO 解析；认证状态、持久化与路由由上层 Controller 处理。
class ServerInfo {
  const ServerInfo({
    required this.version,
    this.id = 0,
    this.coordinateFormat,
    this.openIdEnabled = false,
    this.raw = const {},
  });

  final String version;

  /// Traccar 服务端 id（通常为 1），用于推送 alias 隔离。
  final int id;

  final String? coordinateFormat;
  final bool openIdEnabled;
  final Map<String, dynamic> raw;

  factory ServerInfo.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    return ServerInfo(
      version: json['version'] as String? ?? 'unknown',
      id: rawId is num ? rawId.toInt() : int.tryParse('$rawId') ?? 0,
      coordinateFormat: json['coordinateFormat'] as String?,
      openIdEnabled: json['openIdEnabled'] as bool? ?? false,
      raw: json,
    );
  }
}

class AuthResult {
  const AuthResult({required this.account, required this.token});

  final Account account;
  final String token;
}

class TraccarApi {
  TraccarApi({
    required this.server,
    String? token,
    this.onUnauthorized,
  }) : _token = token;

  final ServerProfile server;
  final String? _token;

  /// 认证请求返回 401 时回调，用于全局清理会话。
  ///
  /// 登录/探活等未认证请求不要传，避免把「密码错误」误判为会话失效。
  final void Function()? onUnauthorized;

  Dio _createDio({CookieJar? cookieJar}) {
    final dio = Dio(
      BaseOptions(
        baseUrl: server.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        headers: {
          'Accept': 'application/json',
          if (_token != null && _token.isNotEmpty)
            'Authorization': 'Bearer $_token',
        },
      ),
    );

    if (server.allowSelfSigned) {
      dio.httpClientAdapter = IOHttpClientAdapter(
        createHttpClient: () {
          final client = HttpClient();
          client.badCertificateCallback =
              (certificate, host, port) => true;
          return client;
        },
      );
    }

    if (cookieJar != null) {
      dio.interceptors.add(CookieManager(cookieJar));
    }

    // 认证请求统一拦截 401，避免每个页面重复处理过期 Token。
    if (onUnauthorized != null && _token != null && _token.isNotEmpty) {
      dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) {
            if (error.response?.statusCode == 401) {
              onUnauthorized?.call();
            }
            handler.next(error);
          },
        ),
      );
    }
    return dio;
  }

  /// 服务器信息（无需认证），用于配置页探活。
  Future<ServerInfo> getServerInfo() => _guard(() async {
        final dio = _createDio();
        final response = await dio.get<Object?>('/api/server');
        return _asServerInfo(response.data);
      });

  /// 密码登录：表单登录拿 Cookie → 换 Token → 校验并返回用户。
  Future<AuthResult> loginWithPassword({
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final cookieJar = CookieJar();
      final dio = _createDio(cookieJar: cookieJar);

      await dio.post<Object?>(
        '/api/session',
        data: {'email': email, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          followRedirects: false,
          validateStatus: (status) => status != null && status < 500,
        ),
      ).then((response) {
        if (response.statusCode == 401) {
          throw const AppFailure(
            FailureKind.unauthorized,
            '邮箱或密码错误',
            statusCode: 401,
          );
        }
        if (response.statusCode != null && response.statusCode! >= 400) {
          throw AppFailure(
            FailureKind.unauthorized,
            _messageFromBody(response.data) ?? '登录失败',
            statusCode: response.statusCode,
          );
        }
      });

      final tokenResponse = await dio.post<Object?>(
        '/api/session/token',
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (tokenResponse.statusCode == 401 ||
          tokenResponse.statusCode == 403) {
        throw const AppFailure(
          FailureKind.unauthorized,
          '登录已失效，请重试',
          statusCode: 401,
        );
      }
      final token = _extractToken(tokenResponse.data);
      if (token == null) {
        throw const AppFailure(FailureKind.server, '服务器未返回有效 Token');
      }

      final account = await _fetchAccountWithToken(token);
      return AuthResult(account: account, token: token);
    });
  }

  /// Token 直接登录（企业分发 / 扫码配置 / 测试）。
  Future<AuthResult> loginWithToken(String token) => _guard(() async {
        final trimmed = token.trim();
        if (trimmed.isEmpty) {
          throw const AppFailure(FailureKind.unauthorized, 'Token 不能为空');
        }
        final account = await _fetchAccountWithToken(trimmed);
        return AuthResult(account: account, token: trimmed);
      });

  Future<Account> _fetchAccountWithToken(String token) async {
    final dio = _createDio();
    final response = await dio.get<Object?>(
      '/api/session',
      queryParameters: {'token': token},
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
      ),
    );
    final data = response.data;
    if (data is! Map) {
      throw const AppFailure(FailureKind.invalidServer, '服务器返回的不是 Traccar 会话信息');
    }
    return Account.fromJson(data.cast<String, dynamic>());
  }

  /// 校验当前 Token。
  Future<Account> getSession() => _guard(() async {
        final response =
            await _createDio().get<Object?>('/api/session');
        final data = response.data;
        if (data is! Map) {
          throw const AppFailure(FailureKind.invalidServer, '会话信息格式不正确');
        }
        return Account.fromJson(data.cast<String, dynamic>());
      });

  /// 退出登录时撤销 Token。失败不阻断本地清理。
  Future<void> revokeToken(String token) async {
    try {
      final dio = _createDio();
      await dio.post<Object?>(
        '/api/session/token/revoke',
        data: {'token': token},
        options: Options(contentType: Headers.formUrlEncodedContentType),
      );
    } catch (_) {
      // 撤销失败（离线/Token 已失效）时仍允许本地登出。
    }
  }

  Future<List<Device>> getDevices({String? keyword}) => _guard(() async {
        final response = await _createDio().get<Object?>(
          '/api/devices',
          queryParameters: {
            if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
          },
        );
        return _asList(response.data)
            .map((item) => Device.fromJson(item))
            .toList(growable: false);
      });

  Future<List<Position>> getLatestPositions() => _guard(() async {
        final response = await _createDio().get<Object?>('/api/positions');
        return _asList(response.data)
            .map((item) => Position.fromJson(item))
            .toList(growable: false);
      });

  Future<List<Position>> getHistory({
    required int deviceId,
    required DateTime from,
    required DateTime to,
  }) =>
      _guard(() async {
        final response = await _createDio().get<Object?>(
          '/api/positions',
          queryParameters: {
            'deviceId': deviceId,
            'from': from.toUtc().toIso8601String(),
            'to': to.toUtc().toIso8601String(),
          },
        );
        final positions = _asList(response.data)
            .map((item) => Position.fromJson(item))
            .toList();
        positions.sort((a, b) {
          final left = a.fixTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.fixTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return left.compareTo(right);
        });
        return positions;
      });

  Future<List<DeviceEvent>> getEvents({
    required DateTime from,
    required DateTime to,
    int? deviceId,
    String? type,
  }) =>
      _guard(() async {
        final response = await _createDio().get<Object?>(
          '/api/reports/events',
          queryParameters: {
            'from': from.toUtc().toIso8601String(),
            'to': to.toUtc().toIso8601String(),
            if (deviceId != null) 'deviceId': deviceId,
            if (type != null && type.isNotEmpty) 'type': type,
          },
        );
        return _asList(response.data)
            .map((item) => DeviceEvent.fromJson(item))
            .toList(growable: false);
      });

  Future<DeviceEvent> getEvent(int id) => _guard(() async {
        final response =
            await _createDio().get<Object?>('/api/events/$id');
        final data = response.data;
        if (data is! Map) {
          throw const AppFailure(FailureKind.invalidServer, '事件数据格式不正确');
        }
        return DeviceEvent.fromJson(data.cast<String, dynamic>());
      });

  Future<Device?> findDeviceByUniqueId(String uniqueId) => _guard(() async {        final response = await _createDio().get<Object?>(
          '/api/devices',
          queryParameters: {'uniqueId': uniqueId},
        );
        final devices = _asList(response.data);
        return devices.isEmpty ? null : Device.fromJson(devices.first);
      });

  Future<Device> createDevice({
    required String name,
    required String uniqueId,
    String category = 'phone',
  }) =>
      _guard(() async {
        final response = await _createDio().post<Object?>(
          '/api/devices',
          data: {
            'name': name,
            'uniqueId': uniqueId,
            'category': category,
          },
        );
        final data = response.data;
        if (data is! Map) {
          throw const AppFailure(FailureKind.server, '创建设备失败：服务器未返回设备信息');
        }
        return Device.fromJson(data.cast<String, dynamic>());
      });

  Future<void> sendCommand({
    required int deviceId,
    required String type,
    Map<String, dynamic> attributes = const {},
  }) =>
      _guard(() async {
        await _createDio().post<Object?>(
          '/api/commands/send',
          data: {
            'deviceId': deviceId,
            'type': type,
            'attributes': attributes,
          },
        );
      });

  /// 注销当前用户。
  ///
  /// Traccar 的 `DELETE /api/users/{id}` 通常要求管理员权限；普通用户
  /// 会收到 403，上层需提示联系管理员，不能假装注销成功。
  Future<void> deleteUser(int id) => _guard(() async {
        await _createDio().delete<Object?>('/api/users/$id');
      });

  /// 统一把 Dio 异常转换成 [AppFailure]。
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on AppFailure {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioError(error);
    } on FormatException catch (error) {
      throw AppFailure(FailureKind.invalidServer, error.message, cause: error);
    }
  }

  AppFailure _mapDioError(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;
    final serverMessage = _messageFromBody(body);

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return AppFailure(FailureKind.timeout, '连接服务器超时，请检查地址与网络',
          cause: error);
    }
    if (error.type == DioExceptionType.badCertificate) {
      return AppFailure(FailureKind.tls, '服务器证书不受信任', cause: error);
    }
    if (error.type == DioExceptionType.connectionError) {
      return AppFailure(FailureKind.network, '无法连接服务器，请检查地址与网络',
          cause: error);
    }

    switch (status) {
      case 401:
        return AppFailure(
          FailureKind.unauthorized,
          serverMessage ?? '登录已失效，请重新登录',
          statusCode: status,
          cause: error,
        );
      case 403:
        return AppFailure(
          FailureKind.forbidden,
          serverMessage ?? '没有权限执行该操作',
          statusCode: status,
          cause: error,
        );
      case 404:
        return AppFailure(
          FailureKind.notFound,
          serverMessage ?? '接口或资源不存在，请确认服务器版本',
          statusCode: status,
          cause: error,
        );
      case 400:
        return AppFailure(
          FailureKind.invalidRequest,
          serverMessage ?? '请求参数不正确',
          statusCode: status,
          cause: error,
        );
    }

    if (status != null && status >= 500) {
      return AppFailure(
        FailureKind.server,
        serverMessage ?? '服务器错误（$status）',
        statusCode: status,
        cause: error,
      );
    }
    if (error.type == DioExceptionType.badResponse) {
      return AppFailure(
        FailureKind.invalidServer,
        serverMessage ?? '服务器返回了无法识别的响应',
        statusCode: status,
        cause: error,
      );
    }
    return AppFailure(
      FailureKind.unknown,
      serverMessage ?? '请求失败：${error.message ?? '未知错误'}',
      statusCode: status,
      cause: error,
    );
  }

  static ServerInfo _asServerInfo(Object? data) {
    if (data is Map) {
      final map = data.cast<String, dynamic>();
      if (!map.containsKey('version')) {
        throw const AppFailure(
          FailureKind.invalidServer,
          '未检测到 Traccar API（缺少 version 字段）',
        );
      }
      return ServerInfo.fromJson(map);
    }
    throw const AppFailure(FailureKind.invalidServer, '未检测到 Traccar API');
  }

  static List<Map<String, dynamic>> _asList(Object? data) {
    if (data is List) {
      return data
          .whereType<Map<Object?, Object?>>()
          .map((item) => item.cast<String, dynamic>())
          .toList(growable: false);
    }
    if (data is Map && data['data'] is List) {
      return _asList(data['data']);
    }
    throw const AppFailure(FailureKind.invalidServer, '服务器返回格式不正确');
  }

  static String? _extractToken(Object? data) {
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return null;
      // 少数反代会把纯文本包成 JSON 字符串。
      if (text.startsWith('"') && text.endsWith('"')) {
        try {
          final decoded = jsonDecode(text);
          return decoded is String ? decoded : null;
        } catch (_) {
          return null;
        }
      }
      return text;
    }
    if (data is Map && data['token'] is String) {
      return data['token'] as String;
    }
    return null;
  }

  static String? _messageFromBody(Object? body) {
    if (body is Map) {
      final message = body['message'] ?? body['error'];
      if (message is String && message.isNotEmpty) return message;
    }
    if (body is String && body.isNotEmpty && body.length < 300) {
      return body;
    }
    return null;
  }
}
