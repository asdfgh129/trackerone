import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/command_localizer.dart';
import '../../../core/localization/failure_localizer.dart';
import '../../../core/storage/command_queue.dart';
import '../../../domain/entities/device_command.dart';
import '../../../domain/entities/inbox_message.dart';
import '../../../domain/failures.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/presentation/formatters.dart';
import '../../commands/application/command_controller.dart';
import '../application/inbox_controller.dart';

/// 消息中心：展示服务端下发的通知、消息与指令。
///
/// 入口：设置页「消息中心」、推送通知点击（`inboxId`）、深链 `/inbox`。
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  @override
  void initState() {
    super.initState();
    // provider 正在首次 build 时跳过，避免并发重复请求；
    // 已有数据（含上次失败）时做一次增量刷新。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(inboxProvider) is AsyncData<InboxState>) {
        unawaited(ref.read(inboxProvider.notifier).sync());
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(inboxProvider);
    final state = inbox.valueOrNull;
    final unread = state?.unread ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.inboxTitle),
        actions: [
          if (unread > 0)
            IconButton(
              tooltip: l10n.inboxMarkAllRead,
              onPressed: () => ref.read(inboxProvider.notifier).markAllRead(),
              icon: const Icon(Icons.done_all),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(inboxProvider.notifier).sync(force: true),
        child: switch (inbox) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError(:final error) => _InboxError(
            message:
                error is AppFailure
                    ? failureMessage(l10n, error)
                    : error.toString(),
            onRetry: () => ref.read(inboxProvider.notifier).sync(force: true),
          ),
          _ => _InboxList(state: state ?? const InboxState()),
        },
      ),
    );
  }
}

class _InboxList extends ConsumerWidget {
  const _InboxList({required this.state});

  final InboxState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    if (state.gatewayMissing) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.inboxGatewayMissing,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    if (state.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * 0.18),
          Icon(
            Icons.inbox_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            l10n.inboxEmpty,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            l10n.inboxEmptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (state.error != null) ...[
            const SizedBox(height: 16),
            Text(
              state.error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: state.messages.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == 0) {
          if (state.error == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              state.error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          );
        }
        final message = state.messages[index - 1];
        return _MessageCard(message: message, unread: state.isUnread(message));
      },
    );
  }
}

class _MessageCard extends ConsumerWidget {
  const _MessageCard({required this.message, required this.unread});

  final InboxMessage message;
  final bool unread;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final title =
        message.title ??
        (message.isCommandResult
            ? l10n.inboxCommandResultTitle
            : message.isCommandPending
            ? l10n.inboxCommandPendingTitle
            : _kindLabel(l10n, message.kind));
    final body =
        message.isCommandPending
            ? (message.body ??
                (message.deviceId != null
                    ? l10n.inboxCommandPendingBody(message.deviceId!)
                    : null))
            : message.isCommandResult
            ? (message.commandResult ?? message.body)
            : message.body;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap:
            message.isCommandPending
                ? null
                : () => ref.read(inboxProvider.notifier).markRead(message.id),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Icon(_icon(message), size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (unread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (body != null && body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                    if (message.isCommandResult) ...[
                      const SizedBox(height: 6),
                      _ResultChip(message: message),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (message.createdAt != null)
                          Text(
                            formatRelativeTime(context, message.createdAt),
                            style: theme.textTheme.labelSmall,
                          ),
                        const Spacer(),
                        if (message.isCommandPending) ...[
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ] else if (message.isCommandResult)
                          TextButton(
                            onPressed:
                                message.deviceId == null
                                    ? null
                                    : () => context.push(
                                      '/device/${message.deviceId}',
                                    ),
                            child: Text(l10n.inboxViewDevice),
                          )
                        else if (message.hasCommand && message.isExpired)
                          Text(
                            l10n.inboxExpired,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          )
                        else if (message.hasCommand)
                          FilledButton.tonal(
                            onPressed: () => _runCommand(context, ref, message),
                            child: Text(l10n.inboxExecute),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _icon(InboxMessage message) {
    if (message.isCommandPending) return Icons.hourglass_top;
    if (message.isCommandResult) {
      return switch (message.commandSucceeded) {
        true => Icons.check_circle_outline,
        false => Icons.error_outline,
        null => Icons.task_alt,
      };
    }
    return _kindIcon(message.kind);
  }

  Future<void> _runCommand(
    BuildContext context,
    WidgetRef ref,
    InboxMessage message,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final type = DeviceCommandType.tryParse(message.command);
    final deviceId = message.deviceId;
    if (type == null || deviceId == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.inboxCommandUnsupported)),
      );
      return;
    }

    if (type.needsConfirmation) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(l10n.inboxCommandConfirmTitle),
              content: Text(
                '${l10n.inboxCommandConfirmBody(commandTypeLabel(l10n, type), deviceId)}\n\n'
                '${l10n.inboxCommandDestructiveWarning}',
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
                  child: Text(l10n.inboxExecute),
                ),
              ],
            ),
      );
      if (confirmed != true) return;
    }

    try {
      final dispatch = await ref
          .read(commandProvider.notifier)
          .send(
            deviceId: deviceId,
            type: type,
            attributes: message.commandAttributes,
          );
      await ref.read(inboxProvider.notifier).markRead(message.id);
      ref
          .read(inboxProvider.notifier)
          .noteCommandDispatched(deviceId: deviceId, command: type.apiType);
      unawaited(ref.read(inboxProvider.notifier).sync());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            dispatch == CommandDispatch.sent
                ? l10n.inboxCommandSent
                : l10n.inboxCommandQueued,
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
    }
  }

  static IconData _kindIcon(InboxKind kind) => switch (kind) {
    InboxKind.command => Icons.terminal,
    InboxKind.notice => Icons.campaign_outlined,
    InboxKind.chat => Icons.chat_bubble_outline,
    InboxKind.unknown => Icons.mail_outline,
  };

  static String _kindLabel(AppLocalizations l10n, InboxKind kind) =>
      switch (kind) {
        InboxKind.command => l10n.inboxKindCommand,
        InboxKind.notice => l10n.inboxKindNotice,
        InboxKind.chat => l10n.inboxKindChat,
        InboxKind.unknown => l10n.inboxTitle,
      };
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({required this.message});

  final InboxMessage message;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (label, color) = switch (message.commandSucceeded) {
      true => (l10n.inboxCommandResultSuccess, Colors.green),
      false => (l10n.inboxCommandResultFailure, theme.colorScheme.error),
      null => (l10n.inboxCommandResultUnknown, theme.colorScheme.outline),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

class _InboxError extends StatelessWidget {
  const _InboxError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.cloud_off_outlined, size: 48),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
        ),
      ],
    );
  }
}
