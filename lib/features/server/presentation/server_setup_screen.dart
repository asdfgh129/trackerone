import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/traccar_api.dart';
import '../../../domain/entities/server_profile.dart';
import '../../../domain/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/application/session_controller.dart';
import '../application/server_profiles_controller.dart';
import 'qr_scanner_screen.dart';

class ServerSetupScreen extends ConsumerWidget {
  const ServerSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final profiles = ref.watch(serverProfilesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.serverTitle),
        actions: [
          IconButton(
            tooltip: l10n.serverScanQr,
            onPressed: () => _scan(context, ref),
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: profiles.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorView(
          message: error is AppFailure ? error.message : error.toString(),
          onRetry: () => ref.invalidate(serverProfilesProvider),
        ),
        data: (state) {
          if (state.servers.isEmpty) {
            return _EmptyServers(
              onAdd: () => _openForm(context, ref),
              onScan: () => _scan(context, ref),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                l10n.serverEmptyBody,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              for (final server in state.servers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ServerCard(
                    server: server,
                    active: server.id == state.active?.id,
                    onUse: () async {
                      await ref
                          .read(serverProfilesProvider.notifier)
                          .setActive(server.id);
                      if (!context.mounted) return;
                      final authenticated = ref
                              .read(sessionProvider)
                              .valueOrNull
                              ?.isAuthenticated ??
                          false;
                      context.go(authenticated ? '/home/map' : '/login');
                    },
                    onEdit: () =>
                        _openForm(context, ref, initial: server),
                    onScan: () => _scan(context, ref),
                    onDelete: () => _delete(context, ref, server),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _openForm(context, ref),
                icon: const Icon(Icons.add),
                label: Text(l10n.serverAdd),
              ),
              if (state.active != null) ...[
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () {
                    final authenticated = ref
                            .read(sessionProvider)
                            .valueOrNull
                            ?.isAuthenticated ??
                        false;
                    context.go(authenticated ? '/home/map' : '/login');
                  },
                  child: Text(l10n.commonContinue),
                ),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(context, ref),
        icon: const Icon(Icons.add),
        label: Text(l10n.serverAdd),
      ),
    );
  }

  Future<void> _scan(BuildContext context, WidgetRef ref) async {
    final profile = await Navigator.of(context).push<ServerProfile>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (profile == null || !context.mounted) return;
    await _openForm(context, ref, initial: profile);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ServerProfile server,
  ) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.commonDelete),
        content: Text(l10n.serverDeleteConfirm(server.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(serverProfilesProvider.notifier).remove(server.id);
  }

  Future<void> _openForm(
    BuildContext context,
    WidgetRef ref, {
    ServerProfile? initial,
  }) async {
    final saved = await showModalBottomSheet<ServerProfile>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _ServerFormSheet(initial: initial),
    );
    if (saved == null || !context.mounted) return;
    await ref.read(serverProfilesProvider.notifier).save(saved);
    // 编辑时修改了地址：旧的档案（含其 Token）需要移除，避免重复。
    if (initial != null && initial.id != saved.id) {
      await ref.read(serverProfilesProvider.notifier).remove(initial.id);
    }
    if (!context.mounted) return;
    final authenticated =
        ref.read(sessionProvider).valueOrNull?.isAuthenticated ?? false;
    context.go(authenticated ? '/home/map' : '/login');
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.active,
    required this.onUse,
    required this.onEdit,
    required this.onScan,
    required this.onDelete,
  });

  final ServerProfile server;
  final bool active;
  final VoidCallback onUse;
  final VoidCallback onEdit;
  final VoidCallback onScan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.check_circle : Icons.dns_outlined,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(server.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        server.apiBaseUrl,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (active)
                  Chip(
                    label: Text(l10n.serverActive),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${l10n.serverReportAddress}: ${server.reportUrl}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: active ? null : onUse,
                  icon: const Icon(Icons.login),
                  label: Text(l10n.serverUse),
                ),
                IconButton(
                  tooltip: l10n.commonEdit,
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: l10n.serverScanQr,
                  onPressed: onScan,
                  icon: const Icon(Icons.qr_code_scanner),
                ),
                const Spacer(),
                IconButton(
                  tooltip: l10n.commonDelete,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServerFormSheet extends StatefulWidget {
  const _ServerFormSheet({this.initial});

  final ServerProfile? initial;

  @override
  State<_ServerFormSheet> createState() => _ServerFormSheetState();
}

class _ServerFormSheetState extends State<_ServerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _report;
  late bool _allowSelfSigned;

  bool _testing = false;
  bool _showAdvanced = false;
  String? _testResult;
  bool _testSuccess = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(text: initial?.name ?? '');
    _address = TextEditingController(
      text: initial?.apiBaseUrl ?? '',
    );
    _report = TextEditingController(text: initial?.reportUrl ?? '');
    _allowSelfSigned = initial?.allowSelfSigned ?? false;
    _showAdvanced = (initial?.reportUrl.isNotEmpty ?? false) ||
        (initial?.allowSelfSigned ?? false);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _report.dispose();
    super.dispose();
  }

  ServerProfile? _buildProfile() {
    try {
      return ServerProfile.fromInput(
        _name.text.trim(),
        _address.text.trim(),
        reportUrl: _report.text.trim(),
        allowSelfSigned: _allowSelfSigned,
      );
    } on FormatException catch (error) {
      setState(() => _submitError = error.message);
      return null;
    }
  }

  Future<void> _test() async {
    final profile = _buildProfile();
    if (profile == null) return;
    setState(() {
      _testing = true;
      _testResult = null;
      _submitError = null;
    });
    try {
      final info = await TraccarApi(server: profile).getServerInfo();
      if (!mounted) return;
      setState(() {
        _testSuccess = true;
        _testResult =
            AppLocalizations.of(context).serverReachable(info.version);
      });
    } on AppFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testResult = failure.message;
      });
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final profile = _buildProfile();
    if (profile == null) return;
    Navigator.of(context).pop(profile);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, bottomInset + 16),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null
                          ? l10n.serverAdd
                          : l10n.serverTitle,
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.serverName,
                  hintText: l10n.serverNameHint,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l10n.serverAddress,
                  hintText: l10n.serverAddressHint,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.serverInvalidAddress;
                  }
                  try {
                    ServerProfile.fromInput('', value);
                    return null;
                  } on FormatException {
                    return l10n.serverInvalidAddress;
                  }
                },
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.serverAdvanced),
                value: _showAdvanced,
                onChanged: (value) => setState(() => _showAdvanced = value),
              ),
              if (_showAdvanced) ...[
                TextFormField(
                  controller: _report,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: l10n.serverReportAddress,
                    hintText: l10n.serverReportHint,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.serverAllowSelfSigned),
                  value: _allowSelfSigned,
                  onChanged: (value) =>
                      setState(() => _allowSelfSigned = value),
                ),
                const SizedBox(height: 8),
              ],
              if (_testResult != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _testSuccess
                            ? Icons.check_circle
                            : Icons.error_outline,
                        color: _testSuccess
                            ? theme.colorScheme.primary
                            : theme.colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testResult!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_submitError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _submitError!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _testing ? null : _test,
                      child: _testing
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(l10n.serverTestConnection),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _testing ? null : _save,
                      child: Text(l10n.serverSaveAndContinue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyServers extends StatelessWidget {
  const _EmptyServers({required this.onAdd, required this.onScan});

  final VoidCallback onAdd;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.dns_outlined, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.serverEmptyTitle,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.serverEmptyBody,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(l10n.serverAdd),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: Text(l10n.serverScanQr),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

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
            FilledButton(
              onPressed: onRetry,
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}
