import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../domain/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../auth/application/session_controller.dart';
import '../../server/application/server_profiles_controller.dart';
import '../application/tracking_controller.dart';

class TrackingScreen extends ConsumerWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tracking = ref.watch(trackingProvider);
    final server = ref.watch(activeServerProvider);
    final authenticated =
        ref.watch(sessionProvider).valueOrNull?.isAuthenticated ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.trackingTitle),
        actions: [
          IconButton(
            tooltip: l10n.permissionRequired,
            onPressed: () => context.push('/onboarding/permissions'),
            icon: const Icon(Icons.admin_panel_settings_outlined),
          ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: () => ref.read(trackingProvider.notifier).refreshLogs(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: tracking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(error.toString()),
          ),
        ),
        data: (state) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              _StatusCard(state: state),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: state.error!),
              ],
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: Text(l10n.trackingUniqueId),
                      subtitle: Text(state.uniqueId),
                      trailing: IconButton(
                        tooltip: l10n.trackingEditId,
                        onPressed: () =>
                            _editUniqueId(context, ref, state.uniqueId),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.dns_outlined),
                      title: Text(l10n.trackingReportAddress),
                      subtitle: Text(
                        server?.reportUrl ?? l10n.trackingNeedServer,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.link),
                      title: Text(l10n.trackingBoundDevice),
                      subtitle: Text(
                        state.boundDeviceId == null
                            ? l10n.trackingNotBound
                            : '${state.serverDeviceName ?? ''} #${state.boundDeviceId}',
                      ),
                      trailing: state.boundDeviceId == null
                          ? TextButton(
                              onPressed: authenticated
                                  ? () => _bind(context, ref)
                                  : () => _message(
                                        context,
                                        l10n.trackingNeedLogin,
                                      ),
                              child: Text(l10n.trackingBind),
                            )
                          : null,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.battery_std),
                      title: Text(l10n.trackingBattery),
                      subtitle: Text(formatBattery(
                        state.batteryLevel?.toDouble(),
                      )),
                      trailing: IconButton(
                        onPressed: () =>
                            ref.read(trackingProvider.notifier).refreshBattery(),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: state.busy
                    ? null
                    : () => state.running
                        ? _stop(context, ref)
                        : _start(context, ref),
                icon: Icon(
                  state.running ? Icons.stop_circle_outlined : Icons.play_arrow,
                ),
                label: Text(
                  state.running ? l10n.trackingStop : l10n.trackingStart,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => _requestPosition(context, ref),
                      icon: const Icon(Icons.my_location),
                      label: Text(l10n.trackingSingle),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: state.busy
                          ? null
                          : () => _sos(context, ref),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      icon: const Icon(Icons.sos_outlined),
                      label: Text(l10n.trackingSos),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    l10n.trackingLogs,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        ref.read(trackingProvider.notifier).clearLogs(),
                    child: Text(l10n.trackingClearLogs),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              if (state.logs.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(l10n.trackingNoLogs)),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: [
                      for (final entry in state.logs.take(30))
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.notes, size: 18),
                          title: Text(
                            entry.message,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          subtitle: Text(formatDateTime(entry.time)),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _start(BuildContext context, WidgetRef ref) async {
    if (!await _hasPermissions()) {
      if (!context.mounted) return;
      final openWizard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(AppLocalizations.of(context).permissionRequired),
          content: Text(AppLocalizations.of(context).permissionsStartBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(AppLocalizations.of(context).permissionsLater),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(AppLocalizations.of(context).permissionsOpenWizard),
            ),
          ],
        ),
      );
      if (openWizard == true && context.mounted) {
        await context.push('/onboarding/permissions');
      }
      return;
    }

    try {
      await ref.read(trackingProvider.notifier).start();
    } on AppFailure catch (failure) {
      if (context.mounted) _message(context, failure.message);
    } catch (error) {
      if (context.mounted) _message(context, error.toString());
    }
  }

  Future<bool> _hasPermissions() async {
    final notification = await Permission.notification.status;
    final location = await Permission.locationWhenInUse.status;
    final background = await Permission.locationAlways.status;
    return _allowed(notification) &&
        _allowed(location) &&
        _allowed(background);
  }

  bool _allowed(PermissionStatus status) {
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited ||
        status == PermissionStatus.provisional;
  }

  Future<void> _stop(BuildContext context, WidgetRef ref) async {
    await ref.read(trackingProvider.notifier).stop();
  }

  Future<void> _bind(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(trackingProvider.notifier).bindDevice();
      if (context.mounted) _message(context, l10n.trackingBindSuccess);
    } on AppFailure catch (failure) {
      if (context.mounted) _message(context, failure.message);
    }
  }

  Future<void> _requestPosition(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final ok = await ref.read(trackingProvider.notifier).requestPosition();
    if (!context.mounted) return;
    _message(
      context,
      ok ? l10n.trackingPositionSent : l10n.trackingPositionFailed,
    );
    await ref.read(trackingProvider.notifier).refreshLogs();
  }

  Future<void> _sos(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.trackingSos),
        content: Text(l10n.trackingSosConfirm),
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
    final ok = await ref
        .read(trackingProvider.notifier)
        .requestPosition(sos: true);
    if (!context.mounted) return;
    _message(
      context,
      ok ? l10n.trackingPositionSent : l10n.trackingPositionFailed,
    );
  }

  Future<void> _editUniqueId(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.trackingEditId),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: l10n.trackingIdHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty) return;
    await ref.read(trackingProvider.notifier).setUniqueId(value);
  }

  void _message(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.state});

  final TrackingState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final running = state.running;
    return Card(
      color: running
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: running
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    running
                        ? l10n.trackingStatusRunning
                        : l10n.trackingStatusStopped,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.busy ? l10n.commonLoading : l10n.trackingTitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (state.busy)
              const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
