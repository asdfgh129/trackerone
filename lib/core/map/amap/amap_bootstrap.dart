import 'package:amap_map/amap_map.dart';
import 'package:flutter/widgets.dart';
import 'package:x_amap_base/x_amap_base.dart';

/// 高德地图 SDK 初始化与合规授权。
///
/// 合规顺序（参考 https://lbs.amap.com/news/sdkhgsy）：
/// 1. 首次启动展示隐私政策，明确「高德地图 SDK」收集的信息；
/// 2. 用户点击同意后调用 [agreePrivacy]；
/// 3. 之后才能调用 [ensureInitialized] 创建地图。
///
/// 顺序错误会被应用商店隐私检测判定为「未经同意提前采集」。
abstract final class AmapBootstrap {
  static bool _privacyAgreed = false;
  static bool _initialized = false;

  static bool get privacyAgreed => _privacyAgreed;
  static bool get initialized => _initialized;

  /// 用户同意隐私政策后调用，可重复调用。
  static void agreePrivacy() {
    AMapInitializer.updatePrivacyAgree(
      AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
    );
    _privacyAgreed = true;
  }

  /// 用户撤回同意时调用。撤回后必须移除地图，并停止一切 SDK 调用。
  static void revokePrivacy() {
    AMapInitializer.updatePrivacyAgree(
      AMapPrivacyStatement(
        hasContains: false,
        hasShow: false,
        hasAgree: false,
      ),
    );
    _privacyAgreed = false;
    _initialized = false;
  }

  /// 必须在 build 中、[AMapWidget] 之前调用。
  ///
  /// [context] 用于插件绑定生命周期，第一个地图页的 context 即可。
  static void ensureInitialized(
    BuildContext context, {
    required String androidKey,
    required String iosKey,
  }) {
    if (!_privacyAgreed) {
      throw StateError('高德地图 SDK 初始化前必须先获得用户隐私授权');
    }
    if (_initialized) {
      return;
    }
    AMapInitializer.init(
      context,
      apiKey: AMapApiKey(androidKey: androidKey, iosKey: iosKey),
    );
    _initialized = true;
  }
}
