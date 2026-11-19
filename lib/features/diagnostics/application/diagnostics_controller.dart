import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/localization/failure_localizer.dart';
import '../../../core/localization/localization.dart';
import '../../../core/network/traccar_api.dart';
import '../../../core/tracking/tracking_engine.dart';
import '../../../domain/failures.dart';
import '../../auth/application/session_controller.dart';
import '../../realtime/application/realtime_controller.dart';
import '../../tracking/application/tracking_controller.dart';

/// 诊断结论等级：用于页面顶部的“结论优先”展示。
enum DiagnosticsLevel { ok, warning, error }

extension DiagnosticsLevelX on DiagnosticsLevel {
  bool get isError => this == DiagnosticsLevel.error;

  bool get isWarning => this == DiagnosticsLevel.warning;
}

/// 一次诊断快照。
///
/// 这是一个纯数据对象：页面负责把 [PermissionStatus] / [ConnectivityResult]
/// 翻译成用户可读文案，方便未来增加更多语言与平台。
class DiagnosticsSnapshot {
  const DiagnosticsSnapshot({
    required this.checkedAt,
    required this.authenticated,
    required this.offline,
    required this.location,
    required this.backgroundLocation,
    required this.notifications,
    required this.activityRecognition,
    required this.batteryOptimizationIgnored,
    required this.trackingRunning,
    required this.trackingLogs,
    required this.restReachable,
    required this.socketConnected,
    required this.network,
    this.serverVersion,
    this.restError,
  });

  final DateTime checkedAt;
  final bool authenticated;
  final bool offline;

  /// Android / iOS 定位权限；桌面或未请求时为 null。
  final PermissionStatus? location;
  final PermissionStatus? backgroundLocation;
  final PermissionStatus? notifications;

  /// Android 活动识别；iOS 不适用时为 null。
  final PermissionStatus? activityRecognition;

  /// null 表示平台不适用（iOS / 桌面）。
  final bool? batteryOptimizationIgnored;

  final bool trackingRunning;
  final List<TrackingLogEntry> trackingLogs;

  final bool restReachable;
  final String? serverVersion;
  final String? restError;

  final bool socketConnected;
  final ConnectivityResult network;

  DateTime? get lastLogTime =>
      trackingLogs.isEmpty ? null : trackingLogs.first.time;

  String? get lastLogMessage =>
      trackingLogs.isEmpty ? null : trackingLogs.first.message;

  /// 总体结论：先报错，再提示风险，最后才是正常。
  DiagnosticsLevel get level {
    if (location != null && !location!.isGrantedOrLimited) {
      return DiagnosticsLevel.error;
    }
    if (!authenticated) return DiagnosticsLevel.warning;
    if (!restReachable && !offline) return DiagnosticsLevel.error;
    if (offline || !restReachable) return DiagnosticsLevel.warning;

    if (backgroundLocation != null &&
        !backgroundLocation!.isGrantedOrLimited) {
      return DiagnosticsLevel.warning;
    }
    if (notifications != null && !notifications!.isGrantedOrLimited) {
      return DiagnosticsLevel.warning;
    }
    if (activityRecognition != null &&
        !activityRecognition!.isGrantedOrLimited) {
      return DiagnosticsLevel.warning;
    }
    if (batteryOptimizationIgnored == false) {
      return DiagnosticsLevel.warning;
    }
    if (!socketConnected) return DiagnosticsLevel.warning;
    if (!trackingRunning) return DiagnosticsLevel.warning;
    return DiagnosticsLevel.ok;
  }
}

extension PermissionStatusX on PermissionStatus {
  /// iOS 的“仅此一次/有限”也应视为可用，只要不是明确拒绝。
  bool get isGrantedOrLimited =>
      this == PermissionStatus.granted ||
      this == PermissionStatus.limited ||
      this == PermissionStatus.provisional;
}

class DiagnosticsController extends AsyncNotifier<DiagnosticsSnapshot> {
  @override
  Future<DiagnosticsSnapshot> build() async {
    return _collect(ref.watch(sessionProvider).valueOrNull);
  }

  Future<DiagnosticsSnapshot> _collect(SessionState? session) async {
    final realtime = ref.read(realtimeProvider).valueOrNull;
    final tracking = ref.read(trackingProvider).valueOrNull;

    final permissions = await _readPermissions();
    final battery = await _readBatteryOptimization();
    final network = await _readNetwork();

    final server = session?.server;
    final token = session?.token;
    var reachable = false;
    String? version;
    String? restError;
    if (server != null) {
      try {
        final info = await TraccarApi(
          server: server,
          token: token,
        ).getServerInfo();
        reachable = true;
        version = info.version;
      } on AppFailure catch (failure) {
        restError = failureMessage(
          ref.read(appLocalizationsProvider),
          failure,
        );
      } catch (error) {
        restError = error.toString();
      }
    }

    final logs = tracking?.logs ?? const <TrackingLogEntry>[];
    return DiagnosticsSnapshot(
      checkedAt: DateTime.now(),
      authenticated: session?.isAuthenticated ?? false,
      offline: session?.offline ?? false,
      location: permissions.$1,
      backgroundLocation: permissions.$2,
      notifications: permissions.$3,
      activityRecognition: permissions.$4,
      batteryOptimizationIgnored: battery,
      trackingRunning: tracking?.running ?? false,
      trackingLogs: logs.take(50).toList(growable: false),
      restReachable: reachable,
      serverVersion: version,
      restError: restError,
      socketConnected: realtime?.connected ?? false,
      network: network,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading<DiagnosticsSnapshot>();
    try {
      state = AsyncData(
        await _collect(ref.read(sessionProvider).valueOrNull),
      );
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  Future<void> requestBatteryExemption() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final status = await Permission.ignoreBatteryOptimizations.request();
    if (status.isGranted) await refresh();
  }

  Future<void> openSystemSettings() => openAppSettings();

  Future<void> clearLogs() async {
    await ref.read(trackingProvider.notifier).clearLogs();
    await refresh();
  }

  Future<(PermissionStatus?, PermissionStatus?, PermissionStatus?, PermissionStatus?)>
      _readPermissions() async {
    if (kIsWeb) return (null, null, null, null);
    return (
      await Permission.locationWhenInUse.status,
      await Permission.locationAlways.status,
      await Permission.notification.status,
      Platform.isAndroid ? await Permission.activityRecognition.status : null,
    );
  }

  Future<bool?> _readBatteryOptimization() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    try {
      final status = await Permission.ignoreBatteryOptimizations.status;
      return status.isGranted;
    } catch (_) {
      return null;
    }
  }

  Future<ConnectivityResult> _readNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (results.isEmpty) return ConnectivityResult.none;
      // 同时存在 Wi-Fi 与移动网络时优先展示 Wi-Fi。
      if (results.contains(ConnectivityResult.wifi)) {
        return ConnectivityResult.wifi;
      }
      if (results.contains(ConnectivityResult.ethernet)) {
        return ConnectivityResult.ethernet;
      }
      if (results.contains(ConnectivityResult.mobile)) {
        return ConnectivityResult.mobile;
      }
      return results.first;
    } catch (_) {
      return ConnectivityResult.none;
    }
  }
}

final diagnosticsProvider =
    AsyncNotifierProvider<DiagnosticsController, DiagnosticsSnapshot>(
  DiagnosticsController.new,
);
