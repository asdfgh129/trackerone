import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:trackerone/core/localization/app_languages.dart';

void main() {
  test('supports 35 languages with unique tags', () {
    expect(appLanguages, hasLength(35));
    expect(
      appLanguages.map((language) => language.tag).toSet(),
      hasLength(35),
    );
  });

  test('parses region and script tags', () {
    expect(localeFromTag('pt_BR'), const Locale('pt', 'BR'));
    expect(localeFromTag('zh-TW'), const Locale('zh', 'TW'));
    expect(localeFromTag('de'), const Locale('de'));
    expect(tagFromLocale(const Locale('pt', 'BR')), 'pt_BR');
  });

  test('looks up languages by full tag and language code', () {
    expect(languageForTag('pt_BR')?.nativeName, 'Português (Brasil)');
    expect(languageForTag('zh-TW')?.nativeName, '繁體中文');
    expect(languageForTag('zh')?.nativeName, '简体中文');
    expect(languageForTag('unknown'), isNull);
  });

  test('marks right-to-left languages', () {
    expect(isRtlLanguage('ar'), isTrue);
    expect(isRtlLanguage('fa'), isTrue);
    expect(isRtlLanguage('he'), isTrue);
    expect(isRtlLanguage('en'), isFalse);
  });

  test('search matches native, English and tag', () {
    final german = appLanguages.firstWhere((language) => language.tag == 'de');
    expect(german.matches('deutsch'), isTrue);
    expect(german.matches('german'), isTrue);
    expect(german.matches('de'), isTrue);
    expect(german.matches('japanese'), isFalse);
  });
}
