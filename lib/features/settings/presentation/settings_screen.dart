import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/brand.dart';
import '../../../core/links/external_link.dart';
import '../../../core/localization/app_languages.dart';
import '../../../core/map/map_privacy_consent.dart';
import '../../../core/privacy/background_location_consent.dart';
import '../../../core/privacy/privacy_consent.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/storage/local_data_cleaner.dart';
import '../../../core/storage/token_store.dart';
import '../../../domain/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/session_controller.dart';
import '../../server/application/server_profiles_controller.dart';
import '../../tracking/application/tracking_controller.dart';
import '../../tracking/presentation/background_location_consent_sheet.dart';
import '../application/locale_controller.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider).valueOrNull;
    final consent = ref.watch(mapPrivacyConsentProvider);
    final locale = ref.watch(localeProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            l10n.settingsServerSection,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(
                    (session?.account?.name.isNotEmpty ?? false)
                        ? session!.account!.name
                        : l10n.settingsAccount,
                  ),
                  subtitle: Text(
                    (session?.account?.email.isNotEmpty ?? false)
                        ? session!.account!.email
                        : l10n.trackingNeedLogin,
                  ),
                  trailing: session?.offline == true
                      ? Chip(
                          label: Text(l10n.offline),
                          visualDensity: VisualDensity.compact,
                        )
                      : null,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(
                    session?.server?.name ?? l10n.settingsServer,
                  ),
                  subtitle: Text(
                    session?.server?.apiBaseUrl ?? l10n.trackingNeedServer,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/server'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: Text(l10n.logout),
                  onTap: () => _logout(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.settingsMapSection,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.map_outlined),
                  title: Text(l10n.settingsMapConsent),
                  subtitle: Text(l10n.settingsMapConsentBody),
                  trailing: Switch(
                    value: consent.valueOrNull ?? false,
                    onChanged: (value) {
                      final notifier =
                          ref.read(mapPrivacyConsentProvider.notifier);
                      if (value) {
                        notifier.agree();
                      } else {
                        notifier.revoke();
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.construction_outlined),
                  title: Text(l10n.settingsDiagnostics),
                  subtitle: Text(l10n.diagnosticsBody),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/diagnostics'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.settingsPrivacySection,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(l10n.settingsPrivacyConsent),
                  subtitle: Text(l10n.settingsPrivacyConsentBody),
                  trailing: Switch(
                    value: ref.watch(privacyConsentProvider).valueOrNull ?? false,
                    onChanged: (value) {
                      if (value) {
                        unawaited(
                          ref.read(privacyConsentProvider.notifier).agree(),
                        );
                      } else {
                        unawaited(_revokePrivacy(context, ref));
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.location_searching_outlined),
                  title: Text(l10n.settingsBackgroundLocationConsent),
                  subtitle: Text(l10n.settingsBackgroundLocationConsentBody),
                  trailing: Switch(
                    value: ref
                            .watch(backgroundLocationConsentProvider)
                            .valueOrNull ??
                        false,
                    onChanged: (value) {
                      if (value) {
                        unawaited(_grantBackgroundLocation(context, ref));
                      } else {
                        unawaited(_revokeBackgroundLocation(context, ref));
                      }
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: Text(l10n.privacyConsentPolicy),
                  subtitle: Text(Brand.privacyUrl),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openUrl(context, Brand.privacyUrl),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: Text(l10n.privacyConsentTerms),
                  subtitle: Text(Brand.termsUrl),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => _openUrl(context, Brand.termsUrl),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.settingsDataSection,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: Text(l10n.settingsClearData),
                  subtitle: Text(l10n.settingsClearDataConfirm),
                  onTap: () => _clearData(context, ref),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(
                    Icons.person_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(
                    l10n.settingsDeleteAccount,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  subtitle: Text(l10n.settingsDeleteAccountBody),
                  onTap: () => _deleteAccount(context, ref),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.settingsAbout,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.translate),
                  title: Text(l10n.settingsLanguage),
                  subtitle: Text(
                    locale == null
                        ? l10n.settingsLanguageSystem
                        : languageForTag(tagFromLocale(locale))?.nativeName ??
                            locale.languageCode,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickLanguage(
                    context,
                    ref,
                    locale == null ? 'system' : tagFromLocale(locale),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(Brand.appName),
                  subtitle: FutureBuilder<PackageInfo>(
                    future: PackageInfo.fromPlatform(),
                    builder: (context, snapshot) {
                      final info = snapshot.data;
                      final version = info == null
                          ? '…'
                          : '${info.version}+${info.buildNumber}';
                      return Text('${l10n.settingsVersion} $version');
                    },
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.verified_user_outlined),
                  title: Text(l10n.settingsChinaCompliance),
                  subtitle: const Text(
                    'APP 备案号 / 地图审图号 / 第三方 SDK 清单',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => _LanguageDialog(
        title: l10n.settingsLanguage,
        systemLabel: l10n.settingsLanguageSystem,
        searchHint: l10n.settingsLanguageSearch,
        cancelLabel: l10n.commonCancel,
        current: current,
      ),
    );
    if (selected == null) return;
    await ref.read(localeProvider.notifier).setLocale(
          selected == 'system' ? null : localeFromTag(selected),
        );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.settingsLogoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stopTrackingIfNeeded(ref);
    await ref.read(sessionProvider.notifier).logout();
    if (context.mounted) context.go('/login');
  }

  /// 退出登录 / 注销 / 清数据前先停止后台上报，避免继续产生位置数据。
  Future<void> _stopTrackingIfNeeded(WidgetRef ref) async {
    final running = ref.read(trackingProvider).valueOrNull?.running ?? false;
    if (!running) return;
    await ref.read(trackingProvider.notifier).stop();
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteAccount),
        content: Text(l10n.settingsDeleteAccountConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsDeleteAccountAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _stopTrackingIfNeeded(ref);
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
    } on AppFailure catch (failure) {
      if (!context.mounted) return;
      final message = failure.kind == FailureKind.forbidden
          ? l10n.settingsDeleteAccountForbidden
          : failure.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.settingsDeleteAccountFailed)),
      );
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.settingsDeleteAccountSuccess)),
    );
    context.go('/login');
  }

  Future<void> _clearData(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsClearData),
        content: Text(l10n.settingsClearDataConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stopTrackingIfNeeded(ref);
    // 先清业务缓存（设备 / 位置 / 事件 / 指令），再清会话与账号。
    try {
      await ref.read(localDataCleanerProvider).clearAll();
    } catch (_) {
      // 缓存清理失败也要继续清 Token，避免留下可用的登录态。
    }
    await ref.read(tokenStoreProvider).deleteAll();
    await ref.read(appPreferencesProvider).clearAccountCaches();
    final server = ref.read(activeServerProvider);
    if (server != null) {
      await ref.read(sessionProvider.notifier).invalidate();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonDone)),
      );
    }
  }

  Future<void> _openUrl(BuildContext context, String url) async {
    final opened = await openExternalUrl(url);
    if (opened || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.privacyConsentLinkFailed)),
    );
  }

  /// 同意后台定位（行踪轨迹属于敏感个人信息，需单独授权）。
  Future<void> _grantBackgroundLocation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final agreed = await showBackgroundLocationConsentSheet(context, ref);
    if (!agreed || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context).backgroundConsentGranted)),
    );
  }

  /// 撤回后台定位授权：停止后台上报并清除授权状态。
  Future<void> _revokeBackgroundLocation(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsBackgroundLocationRevokeTitle),
        content: Text(l10n.settingsBackgroundLocationRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsBackgroundLocationRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stopTrackingIfNeeded(ref);
    await ref.read(backgroundLocationConsentProvider.notifier).revoke();
  }

  /// 撤回隐私授权：停止跟踪、解绑推送、清地图授权，并回到授权页。
  Future<void> _revokePrivacy(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsPrivacyRevokeTitle),
        content: Text(l10n.settingsPrivacyRevokeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.settingsPrivacyRevokeAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _stopTrackingIfNeeded(ref);
    await ref.read(backgroundLocationConsentProvider.notifier).revoke();
    await ref.read(privacyConsentProvider.notifier).revoke();
  }
}

/// 语言选择：35 种语言可搜索，避免长列表难以定位。
class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({
    required this.title,
    required this.systemLabel,
    required this.searchHint,
    required this.cancelLabel,
    required this.current,
  });

  final String title;
  final String systemLabel;
  final String searchHint;
  final String cancelLabel;
  final String current;

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final languages = appLanguages
        .where((language) => language.matches(_query))
        .toList(growable: false);

    return AlertDialog(
      title: Text(widget.title),
      contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: false,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: widget.searchHint,
                  isDense: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  if (_query.isEmpty)
                    ListTile(
                      title: Text(widget.systemLabel),
                      trailing: widget.current == 'system'
                          ? const Icon(Icons.check, size: 20)
                          : null,
                      onTap: () => Navigator.pop(context, 'system'),
                    ),
                  for (final language in languages)
                    ListTile(
                      title: Text(language.nativeName),
                      subtitle: language.nativeName == language.englishName
                          ? null
                          : Text(language.englishName),
                      trailing: widget.current == language.tag
                          ? const Icon(Icons.check, size: 20)
                          : null,
                      onTap: () => Navigator.pop(context, language.tag),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
      ],
    );
  }
}
