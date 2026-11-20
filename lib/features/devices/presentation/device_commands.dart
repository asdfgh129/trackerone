import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/command_localizer.dart';
import '../../../core/localization/failure_localizer.dart';
import '../../../core/storage/command_queue.dart';
import '../../../domain/entities/device_command.dart';
import '../../../domain/entities/models.dart';
import '../../../domain/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../commands/application/command_controller.dart';

/// 打开设备指令选择面板，按设备能力过滤。
Future<void> showDeviceCommandSheet(
  BuildContext context,
  WidgetRef ref,
  Device device,
) async {
  final l10n = AppLocalizations.of(context);
  final rawSupported = device.attributes['supportedCommands'];
  final supported = DeviceCommandType.fromSupported(
    rawSupported is Iterable ? rawSupported : null,
  );
  final commands = supported.isEmpty ? DeviceCommandType.values : supported;

  final type = await showModalBottomSheet<DeviceCommandType>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder:
        (context) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.deviceCommandsTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.deviceCommandsSubtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (supported.isEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.deviceCommandsUnsupported,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              for (final command in commands)
                ListTile(
                  leading: Icon(
                    command.icon,
                    color:
                        command.isDestructive
                            ? Theme.of(context).colorScheme.error
                            : null,
                  ),
                  title: Text(commandTypeLabel(l10n, command)),
                  subtitle: Text(commandTypeDescription(l10n, command)),
                  onTap: () => Navigator.pop(context, command),
                ),
            ],
          ),
        ),
  );
  if (type == null || !context.mounted) return;

  int? frequency;
  String? message;
  if (type == DeviceCommandType.positionPeriodic) {
    frequency = await _askInterval(context, l10n);
    if (frequency == null) return;
  } else if (type == DeviceCommandType.message) {
    message = await _askMessage(context, l10n);
    if (message == null) return;
  }

  if (type.isDestructive && context.mounted) {
    final confirmed = await _confirmDestructive(context, l10n, type);
    if (confirmed != true) return;
  }
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final result = await ref
        .read(commandProvider.notifier)
        .send(
          deviceId: device.id,
          type: type,
          attributes: buildCommandAttributes(
            type,
            frequencySeconds: frequency,
            message: message,
          ),
        );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result == CommandDispatch.sent
              ? l10n.commandSent
              : l10n.commandQueued,
        ),
      ),
    );
  } on AppFailure catch (failure) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${l10n.deviceCommandFailed}: ${failureMessage(l10n, failure)}',
        ),
      ),
    );
  } catch (error) {
    messenger.showSnackBar(
      SnackBar(content: Text('${l10n.deviceCommandFailed}: $error')),
    );
  }
}

Future<int?> _askInterval(BuildContext context, AppLocalizations l10n) async {
  final controller = TextEditingController(text: '60');
  final result = await showDialog<int>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(l10n.commandPositionPeriodic),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.commandPeriodicInterval,
              helperText: l10n.commandPeriodicIntervalHint,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 10 || value > 86400) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.commandPeriodicInvalid)),
                  );
                  return;
                }
                Navigator.pop(context, value);
              },
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
  );
  controller.dispose();
  return result;
}

Future<String?> _askMessage(BuildContext context, AppLocalizations l10n) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(l10n.commandMessage),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 120,
            decoration: InputDecoration(hintText: l10n.commandMessageHint),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.commandMessageEmpty)),
                  );
                  return;
                }
                Navigator.pop(context, text);
              },
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
  );
  controller.dispose();
  return result;
}

Future<bool?> _confirmDestructive(
  BuildContext context,
  AppLocalizations l10n,
  DeviceCommandType type,
) {
  return showDialog<bool>(
    context: context,
    builder:
        (context) => AlertDialog(
          title: Text(commandTypeLabel(l10n, type)),
          content: Text(
            type == DeviceCommandType.factoryReset
                ? l10n.commandConfirmFactoryReset
                : l10n.commandConfirmReboot,
          ),
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
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
  );
}

/// 设备详情里的指令记录与重试入口。
class CommandQueueCard extends ConsumerWidget {
  const CommandQueueCard({required this.deviceId, super.key});

  final int deviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(commandProvider).valueOrNull;
    if (state == null) return const SizedBox.shrink();
    final items = state.forDevice(deviceId).take(8).toList(growable: false);
    if (items.isEmpty) return const SizedBox.shrink();

    final hasRetryable = items.any((item) => item.canRetry);
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.commandQueueTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (hasRetryable)
                  TextButton(
                    onPressed:
                        state.flushing
                            ? null
                            : () => ref.read(commandProvider.notifier).flush(),
                    child: Text(l10n.commandQueueRetryAll),
                  ),
              ],
            ),
          ),
          for (final item in items)
            _CommandTile(
              item: item,
              onRetry: () => ref.read(commandProvider.notifier).retry(item.id),
              onCancel:
                  () => ref.read(commandProvider.notifier).cancel(item.id),
            ),
          if (items.any((item) => item.status.isFinished))
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton.icon(
                  onPressed:
                      () => ref.read(commandProvider.notifier).clearFinished(),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: Text(l10n.commandQueueClear),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  const _CommandTile({
    required this.item,
    required this.onRetry,
    required this.onCancel,
  });

  final QueuedCommand item;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final type = DeviceCommandType.values.firstWhere(
      (command) => command.apiType == item.type,
      orElse: () => DeviceCommandType.positionSingle,
    );
    final (color, icon) = switch (item.status) {
      CommandStatus.sent => (Colors.green, Icons.check_circle_outline),
      CommandStatus.failed => (theme.colorScheme.error, Icons.error_outline),
      CommandStatus.cancelled => (theme.colorScheme.outline, Icons.block),
      CommandStatus.sending => (theme.colorScheme.primary, Icons.sync),
      CommandStatus.pending => (theme.colorScheme.tertiary, Icons.schedule),
    };

    return ListTile(
      dense: true,
      leading: Icon(icon, color: color),
      title: Text(commandTypeLabel(l10n, type)),
      subtitle: Text(
        [
          _statusLabel(l10n, item.status),
          formatRelativeTime(context, item.updatedAt),
          if (item.attempts > 0) l10n.commandAttempts(item.attempts),
          if (item.lastError != null)
            l10n.commandLastError(commandStatusMessage(l10n, item.lastError!)),
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing:
          item.canRetry
              ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.commandQueueRetry,
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh),
                  ),
                  IconButton(
                    tooltip: l10n.commandQueueCancel,
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                  ),
                ],
              )
              : null,
    );
  }
}

String _statusLabel(AppLocalizations l10n, CommandStatus status) =>
    switch (status) {
      CommandStatus.pending => l10n.commandStatusPending,
      CommandStatus.sending => l10n.commandStatusSending,
      CommandStatus.sent => l10n.commandStatusSent,
      CommandStatus.failed => l10n.commandStatusFailed,
      CommandStatus.cancelled => l10n.commandStatusCancelled,
    };
