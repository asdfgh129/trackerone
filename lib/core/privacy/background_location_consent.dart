import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 后台定位的单独授权状态。
///
/// 合规要求（ADR-014）：行踪轨迹属于敏感个人信息，必须与总隐私政策**分开**取得
/// 用户同意，并且可以随时撤回。系统权限（`ACCESS_BACKGROUND_LOCATION`）与本授权
/// 是两件事：用户可能授予了系统权限，但从未在应用内同意过后台定位用途。
abstract interface class BackgroundLocationConsentStore {
  Future<bool> read();
  Future<void> write(bool agreed);
}

/// SharedPreferences 实现。
class PrefsBackgroundLocationConsentStore
    implements BackgroundLocationConsentStore {
  const PrefsBackgroundLocationConsentStore();

  static const String _key = 'tracking.backgroundLocation.consent.v1';

  @override
  Future<bool> read() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  @override
  Future<void> write(bool agreed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, agreed);
  }
}

final backgroundLocationConsentStoreProvider =
    Provider<BackgroundLocationConsentStore>(
  (ref) => const PrefsBackgroundLocationConsentStore(),
);

class BackgroundLocationConsentNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() =>
      ref.watch(backgroundLocationConsentStoreProvider).read();

  /// 用户明确同意后台定位。
  Future<void> agree() async {
    await ref.read(backgroundLocationConsentStoreProvider).write(true);
    state = const AsyncData(true);
  }

  /// 用户撤回后台定位授权：调用方应同时停止后台上报。
  Future<void> revoke() async {
    await ref.read(backgroundLocationConsentStoreProvider).write(false);
    state = const AsyncData(false);
  }
}

final backgroundLocationConsentProvider =
    AsyncNotifierProvider<BackgroundLocationConsentNotifier, bool>(
  BackgroundLocationConsentNotifier.new,
);
