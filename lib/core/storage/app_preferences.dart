import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/server_profile.dart';

/// 非敏感本地配置。
///
/// Token / 密码绝不放在这里，见 `token_store.dart`。
class AppPreferences {
  static const _serversKey = 'servers.v1';
  static const _activeServerKey = 'servers.active.v1';
  static const _uniqueIdKey = 'tracking.uniqueId.v1';
  static const _accountPrefix = 'account.v1.';
  static const _mapConsentPrefix = 'map.privacy.agreed.';
  static const _trackingConfigKey = 'tracking.config.v1';
  static const _localeKey = 'locale.v1';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<List<ServerProfile>> loadServers() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_serversKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<Object?, Object?>>()
          .map((item) => ServerProfile.fromJson(item.cast<String, dynamic>()))
          .where((profile) => profile.apiBaseUrl.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      // 配置损坏时不让应用无法启动，直接当作空列表。
      return const [];
    }
  }

  Future<void> saveServers(List<ServerProfile> servers) async {
    final prefs = await _prefs;
    await prefs.setString(
      _serversKey,
      jsonEncode(servers.map((profile) => profile.toJson()).toList()),
    );
  }

  Future<String?> loadActiveServerId() async {
    final prefs = await _prefs;
    return prefs.getString(_activeServerKey);
  }

  Future<void> saveActiveServerId(String? id) async {
    final prefs = await _prefs;
    if (id == null || id.isEmpty) {
      await prefs.remove(_activeServerKey);
    } else {
      await prefs.setString(_activeServerKey, id);
    }
  }

  Future<String?> loadAccountJson(String serverId) async {
    final prefs = await _prefs;
    return prefs.getString('$_accountPrefix$serverId');
  }

  Future<void> saveAccountJson(String serverId, String? json) async {
    final prefs = await _prefs;
    if (json == null || json.isEmpty) {
      await prefs.remove('$_accountPrefix$serverId');
    } else {
      await prefs.setString('$_accountPrefix$serverId', json);
    }
  }

  Future<String?> loadUniqueId() async {
    final prefs = await _prefs;
    return prefs.getString(_uniqueIdKey);
  }

  Future<void> saveUniqueId(String uniqueId) async {
    final prefs = await _prefs;
    await prefs.setString(_uniqueIdKey, uniqueId);
  }

  Future<int?> loadBoundDeviceId(String serverId) async {
    final prefs = await _prefs;
    return prefs.getInt('tracking.boundDevice.$serverId');
  }

  Future<void> saveBoundDeviceId(String serverId, int? deviceId) async {
    final prefs = await _prefs;
    if (deviceId == null) {
      await prefs.remove('tracking.boundDevice.$serverId');
    } else {
      await prefs.setInt('tracking.boundDevice.$serverId', deviceId);
    }
  }

  Future<bool> readMapConsent(String providerId) async {
    final prefs = await _prefs;
    return prefs.getBool('$_mapConsentPrefix$providerId') ?? false;
  }

  Future<void> writeMapConsent(String providerId, bool agreed) async {
    final prefs = await _prefs;
    await prefs.setBool('$_mapConsentPrefix$providerId', agreed);
  }

  Future<Map<String, dynamic>?> loadTrackingConfig() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_trackingConfigKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTrackingConfig(Map<String, dynamic> config) async {
    final prefs = await _prefs;
    await prefs.setString(_trackingConfigKey, jsonEncode(config));
  }

  Future<String?> loadLocale() async {
    final prefs = await _prefs;
    return prefs.getString(_localeKey);
  }

  /// 传 null 表示跟随系统。
  Future<void> saveLocale(String? languageCode) async {
    final prefs = await _prefs;
    if (languageCode == null || languageCode.isEmpty) {
      await prefs.remove(_localeKey);
    } else {
      await prefs.setString(_localeKey, languageCode);
    }
  }

  Future<void> clearAccountCaches() async {
    final prefs = await _prefs;
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_accountPrefix))
        .toList(growable: false);
    for (final key in keys) {
      await prefs.remove(key);
    }
  }
}

final appPreferencesProvider = Provider<AppPreferences>((ref) {
  return AppPreferences();
});
