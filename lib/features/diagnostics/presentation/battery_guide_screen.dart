import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../l10n/app_localizations.dart';
import '../application/device_vendor.dart';

/// 厂商保活引导：解释系统为什么会杀后台，并给出可执行入口。
///
/// 不同厂商设置路径差异大，无法可靠地直接跳转到对应页面，
/// 因此这里展示厂商专属路径 + 通用的应用设置 / 电池优化入口。
class BatteryGuideScreen extends ConsumerWidget {
  const BatteryGuideScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final vendor = ref.watch(deviceVendorProvider).valueOrNull ??
        DeviceVendor.other;
    final isAndroid = !kIsWeb && Platform.isAndroid;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.batteryGuideTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(l10n.batteryGuideIntro),
            ),
          ),
          const SizedBox(height: 16),
          _StepCard(
            index: 1,
            icon: Icons.location_on_outlined,
            title: l10n.batteryGuideStepPermissions,
          ),
          _StepCard(
            index: 2,
            icon: Icons.battery_saver_outlined,
            title: l10n.batteryGuideStepBattery,
          ),
          _StepCard(
            index: 3,
            icon: Icons.restart_alt,
            title: l10n.batteryGuideStepAutostart,
          ),
          const SizedBox(height: 8),
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.phone_android),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isAndroid
                          ? _vendorHint(l10n, vendor)
                          : l10n.batteryGuideIos,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (isAndroid) ...[
            FilledButton.icon(
              onPressed: () => _requestBatteryExemption(context),
              icon: const Icon(Icons.battery_charging_full),
              label: Text(l10n.batteryGuideOpenBattery),
            ),
            const SizedBox(height: 8),
          ],
          OutlinedButton.icon(
            onPressed: openAppSettings,
            icon: const Icon(Icons.settings_outlined),
            label: Text(l10n.batteryGuideOpenSettings),
          ),
        ],
      ),
    );
  }

  String _vendorHint(AppLocalizations l10n, DeviceVendor vendor) {
    return switch (vendor) {
      DeviceVendor.xiaomi => l10n.batteryGuideVendorXiaomi,
      DeviceVendor.huawei => l10n.batteryGuideVendorHuawei,
      DeviceVendor.oppo => l10n.batteryGuideVendorOppo,
      DeviceVendor.vivo => l10n.batteryGuideVendorVivo,
      DeviceVendor.samsung => l10n.batteryGuideVendorSamsung,
      DeviceVendor.other => l10n.batteryGuideVendorOther,
    };
  }

  Future<void> _requestBatteryExemption(BuildContext context) async {
    final status = await Permission.ignoreBatteryOptimizations.status;
    if (status.isGranted) {
      await openAppSettings();
      return;
    }
    final result = await Permission.ignoreBatteryOptimizations.request();
    if (!context.mounted) return;
    if (result.isPermanentlyDenied) {
      await openAppSettings();
    }
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.index,
    required this.icon,
    required this.title,
  });

  final int index;
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: theme.colorScheme.primaryContainer,
          child: Text(
            '$index',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        title: Text(title),
        subtitle: const SizedBox.shrink(),
        trailing: Icon(icon),
      ),
    );
  }
}
