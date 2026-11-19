import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/application/locale_controller.dart';
import '../../l10n/app_localizations.dart';

/// 不依赖 [BuildContext] 的本地化入口。
///
/// 控制器（例如后台上报的通知文案、首次绑定生成的设备名）也需要按当前语言
/// 取文案，但它们拿不到 context。这里按「用户覆盖语言 → 系统语言」的顺序解析，
/// 与 `MaterialApp` 使用同一套 [AppLocalizations.supportedLocales]。
final appLocalizationsProvider = Provider<AppLocalizations>((ref) {
  final override = ref.watch(localeProvider);
  final resolved = basicLocaleListResolution(
    <Locale>[
      if (override != null) override,
      PlatformDispatcher.instance.locale,
    ],
    AppLocalizations.supportedLocales,
  );
  return lookupAppLocalizations(resolved);
});
