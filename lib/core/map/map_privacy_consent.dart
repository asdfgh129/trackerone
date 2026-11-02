import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 地图 SDK 隐私授权状态。
///
/// 高德 / 腾讯等国内地图 SDK 都要求「先展示隐私政策、用户同意后才能初始化」。
/// 这个状态必须持久化，否则每次冷启动都会重复弹窗。
abstract interface class MapPrivacyConsentStore {
  Future<bool> read(String providerId);
  Future<void> write(String providerId, bool agreed);
}

/// 基于 SharedPreferences 的实现。键按供应商隔离：
/// `map.privacy.agreed.amap`
class PrefsMapPrivacyConsentStore implements MapPrivacyConsentStore {
  const PrefsMapPrivacyConsentStore();

  String _key(String providerId) => 'map.privacy.agreed.$providerId';

  @override
  Future<bool> read(String providerId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(providerId)) ?? false;
  }

  @override
  Future<void> write(String providerId, bool agreed) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(providerId), agreed);
  }
}

final mapPrivacyConsentStoreProvider = Provider<MapPrivacyConsentStore>(
  (ref) => const PrefsMapPrivacyConsentStore(),
);

class MapPrivacyConsentNotifier extends AsyncNotifier<bool> {
  /// 目前只有高德；接入腾讯时改成多供应商 map。
  static const String providerId = 'amap';

  @override
  Future<bool> build() =>
      ref.watch(mapPrivacyConsentStoreProvider).read(providerId);

  Future<void> agree() async {
    await ref.read(mapPrivacyConsentStoreProvider).write(providerId, true);
    state = const AsyncData(true);
  }

  Future<void> revoke() async {
    await ref.read(mapPrivacyConsentStoreProvider).write(providerId, false);
    state = const AsyncData(false);
  }
}

final mapPrivacyConsentProvider =
    AsyncNotifierProvider<MapPrivacyConsentNotifier, bool>(
  MapPrivacyConsentNotifier.new,
);
