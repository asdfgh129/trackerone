import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/brand.dart';
import '../../../core/links/external_link.dart';
import '../../../core/privacy/privacy_consent.dart';
import '../../../l10n/app_localizations.dart';

/// 全局隐私授权闸门。
///
/// 挂在 `MaterialApp.router` 的 `builder` 上，未同意隐私政策时整个 App
/// （包括服务器配置、登录、地图）都不可用，从而保证地图 / 推送 / 崩溃上报
/// 等第三方 SDK 不会被提前初始化。
class PrivacyConsentGate extends ConsumerWidget {
  const PrivacyConsentGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consent = ref.watch(privacyConsentProvider);

    return consent.when(
      loading: () => const _ConsentLoading(),
      // 读取失败时按「未同意」处理，绝不默认放行。
      error: (_, _) => PrivacyConsentScreen(
        onAgree: () => ref.read(privacyConsentProvider.notifier).agree(),
      ),
      data: (agreed) => agreed
          ? child
          : PrivacyConsentScreen(
              onAgree: () => ref.read(privacyConsentProvider.notifier).agree(),
            ),
    );
  }
}

class _ConsentLoading extends StatelessWidget {
  const _ConsentLoading();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.transparent,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

/// 首次启动 / 撤回授权后展示的隐私政策同意页。
class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({required this.onAgree, super.key});

  final Future<void> Function() onAgree;

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool _submitting = false;

  Future<void> _agree() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      await widget.onAgree();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openLink(String url) async {
    final opened = await openExternalUrl(url);
    if (opened || !mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.privacyConsentLinkFailed)),
    );
  }

  Future<void> _disagree() async {
    final l10n = AppLocalizations.of(context);
    final exit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.privacyConsentDisagreeTitle),
        content: Text(l10n.privacyConsentDisagreeBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.privacyConsentReconsider),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.privacyConsentExit),
          ),
        ],
      ),
    );
    if (exit == true) {
      // Android 上直接退出；iOS 不允许程序自杀，调用无副作用。
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(
                          Icons.shield_outlined,
                          size: 40,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        Brand.appName,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      l10n.privacyConsentTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.privacyConsentIntro(Brand.appName),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.privacyConsentBody,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => _openLink(Brand.privacyUrl),
                          child: Text(l10n.privacyConsentPolicy),
                        ),
                        TextButton(
                          onPressed: () => _openLink(Brand.termsUrl),
                          child: Text(l10n.privacyConsentTerms),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    onPressed: _submitting ? null : _agree,
                    child: _submitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.privacyConsentAgree),
                  ),
                  const SizedBox(height: 4),
                  TextButton(
                    onPressed: _submitting ? null : _disagree,
                    child: Text(l10n.privacyConsentDisagree),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
