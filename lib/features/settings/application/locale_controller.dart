import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/app_languages.dart';
import '../../../core/storage/app_preferences.dart';

/// 应用语言覆盖：`null` 表示跟随系统。
///
/// 支持 35 种语言（见 [appLanguages]），持久化完整 BCP-47 标签，
/// 例如 `pt_BR` / `zh_TW`，以便区分巴西葡萄牙语与繁体中文。
class LocaleController extends Notifier<Locale?> {
  @override
  Locale? build() {
    unawaited(_restore());
    return null;
  }

  Future<void> _restore() async {
    final code = await ref.read(appPreferencesProvider).loadLocale();
    if (code == null || code.isEmpty || code == 'system') return;
    state = localeFromTag(code);
  }

  Future<void> setLocale(Locale? locale) async {
    state = locale;
    await ref
        .read(appPreferencesProvider)
        .saveLocale(locale == null ? null : tagFromLocale(locale));
  }
}

final localeProvider =
    NotifierProvider<LocaleController, Locale?>(LocaleController.new);
