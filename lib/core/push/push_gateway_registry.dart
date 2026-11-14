import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/build_config.dart';

/// 推送网关的别名注册客户端。
///
/// 作用：把「用户 → 别名」的关系同步给自建推送网关，
/// 使网关知道该往哪个 alias 投递事件。
///
/// 未配置 `PUSH_GATEWAY_URL` 时全部操作都是空操作，
/// 应用仍可只依赖极光 SDK 自带的别名注册工作。
class PushGatewayRegistry {
  PushGatewayRegistry({Dio? client, String? baseUrl})
    : _baseUrl = (baseUrl ?? BuildConfig.pushGatewayUrl).trim(),
      _client = client ?? Dio();

  final String _baseUrl;
  final Dio _client;

  bool get enabled => _baseUrl.isNotEmpty;

  /// 注册别名。
  ///
  /// 失败只记录日志，不阻断登录：推送不可用时应用内仍能通过 WebSocket 收事件。
  Future<bool> registerAlias({
    required String alias,
    required String token,
    String platform = 'android',
    String vendor = '',
    String appVersion = '',
    String deviceModel = '',
  }) async {
    if (!enabled) return false;
    try {
      await _client.post<void>(
        '$_baseUrl/v1/aliases',
        data: <String, dynamic>{
          'alias': alias,
          'platform': platform,
          'vendor': vendor,
          'appVersion': appVersion,
          'deviceModel': deviceModel,
        },
        options: Options(
          headers: <String, dynamic>{'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      return true;
    } catch (error) {
      debugPrint('推送网关别名注册失败: $error');
      return false;
    }
  }

  /// 解绑别名（退出登录 / 注销账号）。
  Future<void> unregisterAlias({
    required String alias,
    required String token,
  }) async {
    if (!enabled) return;
    try {
      await _client.delete<void>(
        '$_baseUrl/v1/aliases/$alias',
        options: Options(
          headers: <String, dynamic>{'Authorization': 'Bearer $token'},
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
    } catch (error) {
      debugPrint('推送网关别名解绑失败: $error');
    }
  }
}

final pushGatewayRegistryProvider = Provider<PushGatewayRegistry>((ref) {
  return PushGatewayRegistry();
});

/// 记录最近一次注册到网关的别名。
///
/// 退出登录 / 注销账号时需要用同一个别名去解绑，
/// 这里避免让 session 与 push 两个模块互相依赖。
class PushAliasHolder {
  String? alias;
  String? token;

  void remember({required String alias, required String token}) {
    this.alias = alias;
    this.token = token;
  }

  void clear() {
    alias = null;
    token = null;
  }
}

final pushAliasHolderProvider = Provider<PushAliasHolder>((ref) {
  return PushAliasHolder();
});
