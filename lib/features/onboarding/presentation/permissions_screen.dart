import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';

/// 三步权限向导：通知 → 前台定位 → 后台定位 + 活动识别。
///
/// 每一步只申请一个（Android 后台步骤额外申请活动识别），并解释“为什么”。
/// 永久拒绝时提供“去设置”，避免用户卡在无法再次弹窗的状态。
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  static const _stepCount = 3;

  int _step = 0;
  bool _busy = false;
  final Map<int, PermissionStatus> _statuses = {};

  @override
  void initState() {
    super.initState();
    _refreshStatuses();
  }

  List<Permission> _permissionsForStep(int step) {
    return switch (step) {
      0 => [Permission.notification],
      1 => [Permission.locationWhenInUse],
      _ => [
          Permission.locationAlways,
          if (!kIsWeb && Platform.isAndroid)
            Permission.activityRecognition,
        ],
    };
  }

  Future<void> _refreshStatuses() async {
    final permissions = _permissionsForStep(_step);
    final results = await Future.wait(
      permissions.map((permission) => permission.status),
    );
    if (!mounted) return;
    setState(() {
      for (var index = 0; index < permissions.length; index++) {
        _statuses[index] = results[index];
      }
    });
  }

  PermissionStatus? get _stepStatus {
    final permissions = _permissionsForStep(_step);
    final statuses = [
      for (var index = 0; index < permissions.length; index++)
        _statuses[index],
    ];
    if (statuses.any((status) => status == PermissionStatus.permanentlyDenied)) {
      return PermissionStatus.permanentlyDenied;
    }
    if (statuses.every(_isAllowed)) return PermissionStatus.granted;
    if (statuses.any((status) => status == PermissionStatus.restricted)) {
      return PermissionStatus.restricted;
    }
    return PermissionStatus.denied;
  }

  bool _isAllowed(PermissionStatus? status) {
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited ||
        status == PermissionStatus.provisional;
  }

  Future<void> _request() async {
    final permissions = _permissionsForStep(_step);
    setState(() => _busy = true);
    try {
      for (final permission in permissions) {
        await permission.request();
      }
      await _refreshStatuses();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _next() async {
    if (_step >= _stepCount - 1) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() {
      _step += 1;
      _statuses.clear();
    });
    await _refreshStatuses();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final status = _stepStatus;
    final allowed = _isAllowed(status);
    final lastStep = _step == _stepCount - 1;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.permissionsTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(value: (_step + 1) / _stepCount),
              const SizedBox(height: 12),
              Text(
                l10n.permissionsStep(_step + 1, _stepCount),
                style: theme.textTheme.labelLarge,
              ),
              const Spacer(),
              Icon(
                allowed ? Icons.verified_user_outlined : _stepIcon(_step),
                size: 72,
                color: allowed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 24),
              Text(
                _stepTitle(l10n, _step),
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _stepBody(l10n, _step),
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (status != null && !allowed)
                Center(
                  child: Chip(
                    avatar: const Icon(Icons.info_outline, size: 18),
                    label: Text(
                      status == PermissionStatus.permanentlyDenied
                          ? l10n.permissionsPermanentlyDenied
                          : l10n.permissionsNeedsAttention,
                    ),
                  ),
                ),
              if (lastStep && allowed)
                Center(
                  child: Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(l10n.permissionsAllDone),
                  ),
                ),
              const Spacer(),
              if (lastStep)
                TextButton.icon(
                  onPressed: () => context.push('/diagnostics/battery'),
                  icon: const Icon(Icons.battery_saver_outlined),
                  label: Text(l10n.diagnosticsBatteryGuideAction),
                ),
              FilledButton(
                onPressed: _busy ? null : _primaryAction(allowed, status),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_primaryLabel(l10n, allowed, status, lastStep)),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _busy ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.permissionsLater),
              ),
            ],
          ),
        ),
      ),
    );
  }

  VoidCallback _primaryAction(bool allowed, PermissionStatus? status) {
    if (allowed) return _next;
    if (status == PermissionStatus.permanentlyDenied) {
      return () async {
        await openAppSettings();
        await _refreshStatuses();
      };
    }
    return _request;
  }

  String _primaryLabel(
    AppLocalizations l10n,
    bool allowed,
    PermissionStatus? status,
    bool lastStep,
  ) {
    if (allowed) {
      return lastStep ? l10n.commonDone : l10n.commonContinue;
    }
    if (status == PermissionStatus.permanentlyDenied) {
      return l10n.openSettings;
    }
    return l10n.permissionsAllow;
  }

  IconData _stepIcon(int step) {
    return switch (step) {
      0 => Icons.notifications_active_outlined,
      1 => Icons.my_location,
      _ => Icons.gps_fixed,
    };
  }

  String _stepTitle(AppLocalizations l10n, int step) {
    return switch (step) {
      0 => l10n.permissionsNotificationTitle,
      1 => l10n.permissionsLocationTitle,
      _ => l10n.permissionsBackgroundTitle,
    };
  }

  String _stepBody(AppLocalizations l10n, int step) {
    return switch (step) {
      0 => l10n.permissionsNotificationBody,
      1 => l10n.permissionsLocationBody,
      _ => l10n.permissionsBackgroundBody,
    };
  }
}
