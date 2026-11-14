import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/brand.dart';
import '../../../core/links/external_link.dart';
import '../../../core/privacy/background_location_consent.dart';
import '../../../l10n/app_localizations.dart';

/// 后台定位单独授权说明面板。
///
/// 返回 `true` 表示用户同意，调用方才可以申请系统权限并开始后台上报。
Future<bool> showBackgroundLocationConsentSheet(
  BuildContext context,
  WidgetRef ref,
) async {
  final l10n = AppLocalizations.of(context);
  final agreed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _BackgroundLocationConsentSheet(
      onOpenPolicy: () async {
        final opened = await openExternalUrl(Brand.privacyUrl);
        if (opened || !sheetContext.mounted) return;
        ScaffoldMessenger.of(sheetContext).showSnackBar(
          SnackBar(content: Text(l10n.privacyConsentLinkFailed)),
        );
      },
    ),
  );
  if (agreed != true) return false;
  await ref.read(backgroundLocationConsentProvider.notifier).agree();
  return true;
}

class _BackgroundLocationConsentSheet extends StatelessWidget {
  const _BackgroundLocationConsentSheet({required this.onOpenPolicy});

  final VoidCallback onOpenPolicy;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.backgroundConsentTitle,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.backgroundConsentBody,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.backgroundConsentDetail,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onOpenPolicy,
              child: Text(l10n.privacyConsentPolicy),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(l10n.backgroundConsentLater),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(l10n.backgroundConsentAgree),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
