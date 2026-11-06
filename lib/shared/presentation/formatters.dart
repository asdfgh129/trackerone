import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';

String formatRelativeTime(BuildContext context, DateTime? time) {
  if (time == null) return AppLocalizations.of(context).commonNever;
  final l10n = AppLocalizations.of(context);
  final diff = DateTime.now().difference(time.toLocal());
  if (diff.isNegative || diff.inMinutes < 1) return l10n.commonJustNow;
  if (diff.inMinutes < 60) return l10n.commonMinutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.commonHoursAgo(diff.inHours);
  return l10n.commonDaysAgo(diff.inDays);
}

String formatDateTime(DateTime? time) {
  if (time == null) return '—';
  return DateFormat('MM-dd HH:mm:ss').format(time.toLocal());
}

String formatSpeed(double metersPerSecond) {
  return '${(metersPerSecond * 3.6).toStringAsFixed(0)} km/h';
}

String formatBattery(double? level) {
  if (level == null) return '—';
  return '${level.toStringAsFixed(0)}%';
}

String deviceStatusLabel(BuildContext context, String status) {
  final l10n = AppLocalizations.of(context);
  return switch (status) {
    'online' => l10n.commonOnline,
    'offline' => l10n.commonOfflineState,
    _ => status.isEmpty ? l10n.commonUnknown : status,
  };
}

Color deviceStatusColor(BuildContext context, String status) {
  final scheme = Theme.of(context).colorScheme;
  return switch (status) {
    'online' => const Color(0xFF2E7D32),
    'offline' => scheme.outline,
    _ => scheme.tertiary,
  };
}

IconData eventIcon(String type) {
  if (type.startsWith('geofenceEnter')) return Icons.login;
  if (type.startsWith('geofenceExit')) return Icons.logout;
  if (type == 'deviceOnline') return Icons.wifi;
  if (type == 'deviceOffline') return Icons.wifi_off;
  if (type == 'alarm') return Icons.warning_amber_outlined;
  if (type == 'sos') return Icons.sos_outlined;
  if (type == 'speed') return Icons.speed;
  if (type.startsWith('ignition')) return Icons.power_settings_new;
  if (type == 'maintenance') return Icons.build_outlined;
  return Icons.notifications_none;
}

/// 把 `geofenceEnter` 之类转换成可读文本；未收录的保留原值。
String humanizeEventType(String type) {
  final buffer = StringBuffer();
  for (var i = 0; i < type.length; i++) {
    final char = type[i];
    if (i > 0 && char.toUpperCase() == char && char.toLowerCase() != char) {
      buffer.write(' ');
    }
    buffer.write(char);
  }
  final text = buffer.toString();
  return text.isEmpty ? type : text[0].toUpperCase() + text.substring(1);
}
