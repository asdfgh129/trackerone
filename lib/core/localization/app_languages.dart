import 'dart:ui';

/// 应用支持的语言。顺序与 Traccar Client 的 35 个 ARB 保持一致。
///
/// 语言名称使用本地写法（native name），不参与翻译。
class AppLanguage {
  const AppLanguage({
    required this.tag,
    required this.nativeName,
    required this.englishName,
  });

  /// ARB 文件名后缀，例如 `pt_BR`。
  final String tag;
  final String nativeName;
  final String englishName;

  bool matches(String query) {
    final value = query.trim().toLowerCase();
    if (value.isEmpty) return true;
    return nativeName.toLowerCase().contains(value) ||
        englishName.toLowerCase().contains(value) ||
        tag.toLowerCase().contains(value);
  }
}

const appLanguages = <AppLanguage>[
  AppLanguage(tag: 'ar', nativeName: 'العربية', englishName: 'Arabic'),
  AppLanguage(tag: 'ca', nativeName: 'Català', englishName: 'Catalan'),
  AppLanguage(tag: 'cs', nativeName: 'Čeština', englishName: 'Czech'),
  AppLanguage(tag: 'de', nativeName: 'Deutsch', englishName: 'German'),
  AppLanguage(tag: 'el', nativeName: 'Ελληνικά', englishName: 'Greek'),
  AppLanguage(tag: 'en', nativeName: 'English', englishName: 'English'),
  AppLanguage(tag: 'es', nativeName: 'Español', englishName: 'Spanish'),
  AppLanguage(tag: 'et', nativeName: 'Eesti', englishName: 'Estonian'),
  AppLanguage(tag: 'fa', nativeName: 'فارسی', englishName: 'Persian'),
  AppLanguage(tag: 'fi', nativeName: 'Suomi', englishName: 'Finnish'),
  AppLanguage(tag: 'fr', nativeName: 'Français', englishName: 'French'),
  AppLanguage(tag: 'he', nativeName: 'עברית', englishName: 'Hebrew'),
  AppLanguage(tag: 'hr', nativeName: 'Hrvatski', englishName: 'Croatian'),
  AppLanguage(
    tag: 'id',
    nativeName: 'Bahasa Indonesia',
    englishName: 'Indonesian',
  ),
  AppLanguage(tag: 'it', nativeName: 'Italiano', englishName: 'Italian'),
  AppLanguage(tag: 'ja', nativeName: '日本語', englishName: 'Japanese'),
  AppLanguage(tag: 'kab', nativeName: 'Taqbaylit', englishName: 'Kabyle'),
  AppLanguage(tag: 'ko', nativeName: '한국어', englishName: 'Korean'),
  AppLanguage(tag: 'lt', nativeName: 'Lietuvių', englishName: 'Lithuanian'),
  AppLanguage(tag: 'lv', nativeName: 'Latviešu', englishName: 'Latvian'),
  AppLanguage(
    tag: 'nb',
    nativeName: 'Norsk bokmål',
    englishName: 'Norwegian Bokmål',
  ),
  AppLanguage(tag: 'nl', nativeName: 'Nederlands', englishName: 'Dutch'),
  AppLanguage(tag: 'pl', nativeName: 'Polski', englishName: 'Polish'),
  AppLanguage(tag: 'pt', nativeName: 'Português', englishName: 'Portuguese'),
  AppLanguage(
    tag: 'pt_BR',
    nativeName: 'Português (Brasil)',
    englishName: 'Portuguese (Brazil)',
  ),
  AppLanguage(tag: 'ru', nativeName: 'Русский', englishName: 'Russian'),
  AppLanguage(tag: 'sk', nativeName: 'Slovenčina', englishName: 'Slovak'),
  AppLanguage(tag: 'sl', nativeName: 'Slovenščina', englishName: 'Slovenian'),
  AppLanguage(tag: 'sr', nativeName: 'Српски', englishName: 'Serbian'),
  AppLanguage(tag: 'th', nativeName: 'ไทย', englishName: 'Thai'),
  AppLanguage(tag: 'tr', nativeName: 'Türkçe', englishName: 'Turkish'),
  AppLanguage(tag: 'uk', nativeName: 'Українська', englishName: 'Ukrainian'),
  AppLanguage(tag: 'vi', nativeName: 'Tiếng Việt', englishName: 'Vietnamese'),
  AppLanguage(tag: 'zh', nativeName: '简体中文', englishName: 'Chinese Simplified'),
  AppLanguage(
    tag: 'zh_TW',
    nativeName: '繁體中文',
    englishName: 'Chinese Traditional',
  ),
];

AppLanguage? languageForTag(String? tag) {
  if (tag == null || tag.isEmpty) return null;
  final normalized = tag.replaceAll('-', '_');
  for (final language in appLanguages) {
    if (language.tag == normalized) return language;
  }
  final languageCode = normalized.split('_').first;
  for (final language in appLanguages) {
    if (language.tag == languageCode) return language;
  }
  return null;
}

/// 将持久化标签（`pt_BR` / `zh-TW`）转换为 [Locale]。
Locale localeFromTag(String tag) {
  final parts = tag.replaceAll('-', '_').split('_');
  if (parts.length >= 3) {
    return Locale.fromSubtags(
      languageCode: parts[0],
      scriptCode: parts[1],
      countryCode: parts[2],
    );
  }
  if (parts.length == 2 && parts[1].isNotEmpty) {
    return Locale(parts[0], parts[1]);
  }
  return Locale(parts[0]);
}

String tagFromLocale(Locale locale) {
  final country = locale.countryCode;
  if (country == null || country.isEmpty) return locale.languageCode;
  return '${locale.languageCode}_$country';
}

/// RTL 语言；Material 会根据 locale 自动切换方向，这里用于需要显式判断的场景。
bool isRtlLanguage(String languageCode) {
  return languageCode == 'ar' || languageCode == 'fa' || languageCode == 'he';
}
