import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../map/map_privacy_consent.dart';
import '../push/push_service.dart';

/// 全局隐私政策授权状态。
///
/// 合规要求：用户同意隐私政策前，不得初始化地图、推送、统计等第三方 SDK，
/// 也不得采集位置信息。因此这个状态必须在任何业务 SDK 之前读取：
/// - `main()` 用它决定是否初始化崩溃上报；
/// - `PrivacyConsentGate` 用它决定是否放行 App；
/// - `PushRegistrationController` 用它决定是否注册推送别名。
///
/// 持久化的是「已同意的政策版本号」而不是布尔值：隐私政策有实质变更时
/// 递增 [PrivacyConsentNotifier.policyVersion]，即可让所有用户重新确认。
abstract interface class PrivacyConsentStore {
  Future<int> readAcceptedVersion();
  Future<void> writeAcceptedVersion(int version);
  Future<void> clear();
}

/// 基于 SharedPreferences 的实现。键名带 `v1`，避免与其他模块冲突。
class PrefsPrivacyConsentStore implements PrivacyConsentStore {
  const PrefsPrivacyConsentStore();

  static const String _versionKey = 'privacy.policy.acceptedVersion.v1';

  @override
  Future<int> readAcceptedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_versionKey) ?? 0;
  }

  @override
  Future<void> writeAcceptedVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_versionKey, version);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_versionKey);
  }
}

final privacyConsentStoreProvider = Provider<PrivacyConsentStore>(
  (ref) => const PrefsPrivacyConsentStore(),
);

class PrivacyConsentNotifier extends AsyncNotifier<bool> {
  /// 隐私政策版本。条款发生实质变更时递增，强制所有用户重新同意。
  static const int policyVersion = 1;

  @override
  Future<bool> build() async {
    final accepted =
        await ref.watch(privacyConsentStoreProvider).readAcceptedVersion();
    return accepted >= policyVersion;
  }

  Future<void> agree() async {
    await ref
        .read(privacyConsentStoreProvider)
        .writeAcceptedVersion(policyVersion);
    state = const AsyncData(true);
  }

  /// 撤回同意：停止一切依赖授权的 SDK，并清理推送别名。
  ///
  /// 即使某个清理步骤失败，也必须回到「未授权」状态，否则界面会继续
  /// 放行，造成合规问题。
  Future<void> revoke() async {
    try {
      await ref.read(privacyConsentStoreProvider).clear();
      // 地图 SDK 有独立的授权记录，撤回总授权时必须一并失效。
      await ref.read(mapPrivacyConsentStoreProvider).write(
            MapPrivacyConsentNotifier.providerId,
            false,
          );
      ref.invalidate(mapPrivacyConsentProvider);
      // 解绑推送别名，避免撤回后仍收到推送。
      await ref.read(pushServiceProvider).deleteAlias();
    } finally {
      state = const AsyncData(false);
    }
  }
}

final privacyConsentProvider =
    AsyncNotifierProvider<PrivacyConsentNotifier, bool>(
  PrivacyConsentNotifier.new,
);
