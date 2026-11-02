import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:jpush_flutter/jpush_flutter.dart';
import 'package:jpush_flutter/jpush_interface.dart';

import '../config/build_config.dart';
import 'push_gateway.dart';

/// 极光推送（JPush）通道，面向中国大陆生产环境。
///
/// 为什么用 JPush：
/// - 聚合小米 / 华为 / OPPO / vivo / 荣耀厂商通道，避免保活问题；
/// - 服务端只需调用一次 REST API，由极光负责路由到各厂商；
/// - 支持别名（alias），可直接用 `u{userId}@{serverId}` 定位用户。
///
/// 平台配置（必须在原生工程完成，否则收不到推送）：
/// - Android：`manifestPlaceholders = [JPUSH_PKGNAME, JPUSH_APPKEY, JPUSH_CHANNEL]`；
///   厂商通道还需各自 AppKey 与签名校验。
/// - iOS：开启 Push Notifications capability，上传 APNs 证书/密钥到极光后台。
///
/// 注意：厂商通道（小米/华为/OPPO/vivo）申请需要企业资质，周期约 1–2 周。
class JpushPushGateway implements PushGateway {
  JpushPushGateway();

  final JPushFlutterInterface _jpush = JPush.newJPush();
  final StreamController<PushMessage> _messages =
      StreamController<PushMessage>.broadcast();

  PushMessage? _initialMessage;
  bool _initialized = false;

  @override
  String get id => 'jpush';

  @override
  Stream<PushMessage> get messages => _messages.stream;

  @override
  Future<void> initialize({required String alias}) async {
    if (_initialized) {
      await updateAlias(alias);
      return;
    }
    if (BuildConfig.jpushAppKey.isEmpty) {
      debugPrint('JPUSH_APP_KEY 未配置，极光推送不可用');
      return;
    }
    _initialized = true;

    // `setup` 是同步方法（内部走 MethodChannel），不能 await。
    _jpush.setup(
      appKey: BuildConfig.jpushAppKey,
      channel: BuildConfig.jpushChannel,
      production: BuildConfig.isProd,
      debug: kDebugMode,
    );

    _jpush.addEventHandler(
      onReceiveNotification: (Map<String, dynamic> message) async {
        _messages.add(_toMessage(message));
      },
      onOpenNotification: (Map<String, dynamic> message) async {
        _messages.add(_toMessage(message));
        await _jpush.setBadge(0);
      },
    );

    try {
      // jpush_flutter 3.6.0 的接口名是 getLaunchAppNotification()。
      final launch = await _jpush.getLaunchAppNotification();
      final initial = _toMessageOrNull(launch);
      if (initial != null) {
        _initialMessage = initial;
      }
    } catch (error) {
      // 冷启动接口在部分 ROM 上可能失败，不影响后续推送。
      debugPrint('JPush getLaunchAppNotification failed: $error');
    }

    await updateAlias(alias);
  }

  @override
  Future<void> updateAlias(String alias) async {
    if (!_initialized) return;
    try {
      await _jpush.setAlias(alias);
    } catch (error) {
      // alias 注册失败通常是网络或 AppKey 未配置；记录后等待下次登录重试。
      debugPrint('JPush setAlias failed: $error');
    }
  }

  @override
  Future<PushMessage?> takeInitialMessage() async {
    final message = _initialMessage;
    _initialMessage = null;
    return message;
  }

  @override
  Future<void> dispose() async {
    await _messages.close();
  }

  PushMessage _toMessage(Map<String, dynamic> message) {
    final extras = message['extras'];
    final data = <String, dynamic>{};
    if (extras is Map) {
      for (final entry in extras.entries) {
        data[_keyToString(entry.key)] = entry.value;
      }
    }
    return PushMessage(
      eventId: PushMessage.fromData(data).eventId,
      command: PushMessage.fromData(data).command,
      title: (message['title'] as Object?)?.toString() ??
          (data['title'] as Object?)?.toString(),
      body: (message['alert'] as Object?)?.toString() ??
          (data['body'] as Object?)?.toString(),
      data: data,
    );
  }

  PushMessage? _toMessageOrNull(Map<dynamic, dynamic>? message) {
    if (message == null || message.isEmpty) return null;
    final data = message.map(
      (key, value) => MapEntry(_keyToString(key), value),
    );
    // 极光冷启动返回的是通知对象，extras 才是业务字段。
    final extras = data['extras'];
    if (extras is Map) {
      return PushMessage.fromData(
        extras.map((key, value) => MapEntry(_keyToString(key), value)),
      );
    }
    return PushMessage.fromData(data);
  }

  /// 避免对 `dynamic` 直接调用方法（analysis_options 开启 avoid_dynamic_calls）。
  static String _keyToString(Object? key) => key?.toString() ?? '';
}
