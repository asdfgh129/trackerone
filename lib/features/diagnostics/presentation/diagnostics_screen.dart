import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../auth/application/session_controller.dart';
import '../../push/application/push_registration_controller.dart';
import '../application/diagnostics_controller.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final snapshot = ref.watch(diagnosticsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.diagnosticsTitle),
        actions: [
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () =>
                ref.read(diagnosticsProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          message: error.toString(),
          onRetry: () => ref.read(diagnosticsProvider.notifier).refresh(),
        ),
        data: (data) => _DiagnosticsBody(snapshot: data),
      ),
    );
  }
}

class _DiagnosticsBody extends ConsumerWidget {
  const _DiagnosticsBody({required this.snapshot});

  final DiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _OverallCard(snapshot: snapshot),
        const SizedBox(height: 20),
        _SectionTitle(l10n.diagnosticsSectionPermissions),
        Card(
          child: Column(
            children: [
              _PermissionTile(
                icon: Icons.my_location,
                title: l10n.diagnosticsLocation,
                status: snapshot.location,
              ),
              const Divider(height: 1),
              _PermissionTile(
                icon: Icons.gps_fixed,
                title: l10n.diagnosticsBackgroundLocation,
                status: snapshot.backgroundLocation,
              ),
              const Divider(height: 1),
              _PermissionTile(
                icon: Icons.notifications_active_outlined,
                title: l10n.diagnosticsNotifications,
                status: snapshot.notifications,
              ),
              if (snapshot.activityRecognition != null) ...[
                const Divider(height: 1),
                _PermissionTile(
                  icon: Icons.directions_run,
                  title: l10n.diagnosticsMotion,
                  status: snapshot.activityRecognition,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.diagnosticsSectionBackground),
        Card(
          child: Column(
            children: [
              if (snapshot.batteryOptimizationIgnored != null)
                ListTile(
                  leading: Icon(
                    snapshot.batteryOptimizationIgnored!
                        ? Icons.battery_saver
                        : Icons.battery_alert_outlined,
                  ),
                  title: Text(l10n.diagnosticsBatteryOptimization),
                  subtitle: Text(
                    snapshot.batteryOptimizationIgnored!
                        ? l10n.diagnosticsBatteryExempt
                        : l10n.diagnosticsBatteryRestricted,
                  ),
                  trailing: snapshot.batteryOptimizationIgnored!
                      ? null
                      : TextButton(
                          onPressed: () => ref
                              .read(diagnosticsProvider.notifier)
                              .requestBatteryExemption(),
                          child: Text(l10n.diagnosticsFix),
                        ),
                ),
              if (snapshot.batteryOptimizationIgnored != null)
                const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.battery_saver_outlined),
                title: Text(l10n.diagnosticsBatteryGuideAction),
                subtitle: Text(l10n.batteryGuideIntro),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/diagnostics/battery'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.memory),
                title: Text(l10n.diagnosticsForegroundService),
                subtitle: Text(
                  snapshot.trackingRunning
                      ? l10n.diagnosticsForegroundRunning
                      : l10n.diagnosticsForegroundStopped,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.diagnosticsSectionReporting),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  snapshot.trackingRunning
                      ? Icons.play_circle_outline
                      : Icons.pause_circle_outline,
                ),
                title: Text(l10n.diagnosticsTracking),
                subtitle: Text(
                  snapshot.trackingRunning
                      ? l10n.diagnosticsTrackingRunning
                      : l10n.diagnosticsTrackingStopped,
                ),
                trailing: TextButton(
                  onPressed: () => context.go('/home/tracking'),
                  child: Text(l10n.diagnosticsOpenTracking),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(l10n.lastUpload),
                subtitle: Text(
                  snapshot.lastLogTime == null
                      ? l10n.diagnosticsNoLogs
                      : formatDateTime(snapshot.lastLogTime!),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.diagnosticsSectionNetwork),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(l10n.diagnosticsNetwork),
                subtitle: Text(_networkLabel(l10n, snapshot.network)),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  snapshot.socketConnected ? Icons.bolt : Icons.bolt_outlined,
                ),
                title: Text(l10n.diagnosticsLiveConnection),
                subtitle: Text(
                  snapshot.socketConnected
                      ? l10n.diagnosticsLiveConnected
                      : l10n.diagnosticsLiveDisconnected,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.diagnosticsSectionServer),
        Card(
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.dns_outlined),
                title: Text(l10n.serverAddress),
                subtitle: Text(
                  ref.watch(sessionProvider).valueOrNull?.server?.apiBaseUrl ??
                      l10n.diagnosticsServerNotConfigured,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  snapshot.restReachable
                      ? Icons.cloud_done_outlined
                      : Icons.cloud_off_outlined,
                ),
                title: Text(l10n.diagnosticsServerConnection),
                subtitle: Text(
                  snapshot.restReachable
                      ? l10n.diagnosticsServerReachable(
                          snapshot.serverVersion ?? l10n.commonUnknown,
                        )
                      : (snapshot.restError ??
                          l10n.diagnosticsServerUnreachable),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(l10n.diagnosticsSession),
                subtitle: Text(
                  snapshot.offline
                      ? l10n.diagnosticsOfflineMode
                      : snapshot.authenticated
                          ? l10n.diagnosticsSignedIn
                          : l10n.diagnosticsSignedOut,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _SectionTitle(l10n.diagnosticsPushTitle),
        const _PushCard(),
        const SizedBox(height: 20),
        Row(
          children: [
            _SectionTitle(l10n.diagnosticsSectionLogs),
            const Spacer(),
            TextButton.icon(
              onPressed: snapshot.trackingLogs.isEmpty
                  ? null
                  : () => _copyLogs(context, snapshot),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text(l10n.diagnosticsCopyLogs),
            ),
            IconButton(
              tooltip: l10n.trackingClearLogs,
              onPressed: snapshot.trackingLogs.isEmpty
                  ? null
                  : () => ref.read(diagnosticsProvider.notifier).clearLogs(),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        if (snapshot.trackingLogs.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Center(child: Text(l10n.diagnosticsNoLogs)),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final entry in snapshot.trackingLogs.take(20))
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.notes, size: 18),
                    title: Text(
                      entry.message,
                      style: theme.textTheme.bodySmall,
                    ),
                    subtitle: Text(formatDateTime(entry.time)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => context.push('/onboarding/permissions'),
          icon: const Icon(Icons.admin_panel_settings_outlined),
          label: Text(l10n.diagnosticsOpenPermissions),
        ),
      ],
    );
  }

  String _networkLabel(AppLocalizations l10n, ConnectivityResult result) {
    return switch (result) {
      ConnectivityResult.wifi => l10n.diagnosticsNetworkWifi,
      ConnectivityResult.mobile => l10n.diagnosticsNetworkMobile,
      ConnectivityResult.ethernet => l10n.diagnosticsNetworkEthernet,
      ConnectivityResult.none => l10n.diagnosticsNetworkNone,
      _ => l10n.diagnosticsNetworkOther,
    };
  }

  Future<void> _copyLogs(
    BuildContext context,
    DiagnosticsSnapshot snapshot,
  ) async {
    final l10n = AppLocalizations.of(context);
    final text = snapshot.trackingLogs
        .map((entry) => '${formatDateTime(entry.time)}  ${entry.message}')
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.diagnosticsLogsCopied)),
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.snapshot});

  final DiagnosticsSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (color, icon, title) = switch (snapshot.level) {
      DiagnosticsLevel.ok => (
          theme.colorScheme.primaryContainer,
          Icons.check_circle_outline,
          l10n.diagnosticsOverallOk,
        ),
      DiagnosticsLevel.warning => (
          theme.colorScheme.tertiaryContainer,
          Icons.warning_amber_outlined,
          l10n.diagnosticsOverallWarning,
        ),
      DiagnosticsLevel.error => (
          theme.colorScheme.errorContainer,
          Icons.error_outline,
          l10n.diagnosticsOverallError,
        ),
    };

    return Card(
      color: color,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    l10n.diagnosticsCheckedAt(
                      formatDateTime(snapshot.checkedAt),
                    ),
                    style: theme.textTheme.bodySmall,
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

class _PermissionTile extends ConsumerWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.status,
  });

  final IconData icon;
  final String title;
  final PermissionStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final status = this.status;
    final allowed = status?.isGrantedOrLimited ?? false;
    return ListTile(
      leading: Icon(
        allowed ? Icons.check_circle_outline : Icons.cancel_outlined,
        color: allowed ? null : Theme.of(context).colorScheme.error,
      ),
      title: Text(title),
      subtitle: Text(_statusLabel(l10n, status)),
      trailing: status == null || allowed
          ? null
          : TextButton(
              onPressed: () =>
                  ref.read(diagnosticsProvider.notifier).openSystemSettings(),
              child: Text(l10n.openSettings),
            ),
      onTap: status == null || allowed
          ? null
          : () =>
              ref.read(diagnosticsProvider.notifier).openSystemSettings(),
    );
  }

  String _statusLabel(AppLocalizations l10n, PermissionStatus? status) {
    if (status == null) return l10n.diagnosticsNotApplicable;
    return switch (status) {
      PermissionStatus.granted => l10n.diagnosticsAllowed,
      PermissionStatus.limited => l10n.diagnosticsLimited,
      PermissionStatus.provisional => l10n.diagnosticsProvisional,
      PermissionStatus.denied => l10n.diagnosticsDenied,
      PermissionStatus.restricted => l10n.diagnosticsRestricted,
      PermissionStatus.permanentlyDenied => l10n.diagnosticsPermanentlyDenied,
    };
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _PushCard extends ConsumerWidget {
  const _PushCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final registration = ref.watch(pushRegistrationProvider);
    final state = registration.valueOrNull;
    if (state == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!state.enabled) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(l10n.diagnosticsPushNotConfigured),
          subtitle: Text(l10n.diagnosticsPushNone),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              state.registered
                  ? Icons.notifications_active
                  : Icons.notifications_paused_outlined,
            ),
            title: Text(l10n.diagnosticsPushProvider),
            subtitle: Text(
              '${state.providerId} · '
              '${state.registered ? l10n.diagnosticsPushRegistered : l10n.diagnosticsPushNotRegistered}',
            ),
            trailing: TextButton(
              onPressed: registration.isLoading
                  ? null
                  : () => ref.read(pushRegistrationProvider.notifier).retry(),
              child: Text(l10n.retry),
            ),
          ),
          if (state.alias != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alternate_email),
              title: Text(l10n.diagnosticsPushAlias),
              subtitle: Text(state.alias!),
            ),
          ],
          if (state.lastError != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: Icon(
                Icons.error_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(l10n.diagnosticsPushError),
              subtitle: Text(state.lastError!),
            ),
          ],
          if (state.lastMessage != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.mark_email_unread_outlined),
              title: Text(l10n.diagnosticsPushLastMessage),
              subtitle: Text(
                [
                  if (state.lastMessageAt != null)
                    formatDateTime(state.lastMessageAt!),
                  state.lastMessage!.title ?? state.lastMessage!.body ?? '',
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
            ),
          ],
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: const Icon(Icons.info_outline, size: 18),
            title: Text(l10n.diagnosticsPushHint),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
