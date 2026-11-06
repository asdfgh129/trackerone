import 'dart:async';
import 'dart:math';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/app_preferences.dart';
import '../../../core/tracking/sdk_tracking_engine.dart';
import '../../../core/tracking/tracking_engine.dart';
import '../../../domain/failures.dart';
import '../../server/application/server_profiles_controller.dart';

final trackingEngineProvider = Provider<TrackingEngine>((ref) {
  final engine = SdkTrackingEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

class TrackingState {
  const TrackingState({
    this.uniqueId = '',
    this.running = false,
    this.busy = false,
    this.boundDeviceId,
    this.serverDeviceName,
    this.logs = const [],
    this.batteryLevel,
    this.error,
    this.initialized = false,
  });

  final String uniqueId;
  final bool running;
  final bool busy;

  /// Traccar 中的设备 id；用于地图高亮与详情跳转。
  final int? boundDeviceId;
  final String? serverDeviceName;

  final List<TrackingLogEntry> logs;
  final int? batteryLevel;
  final String? error;
  final bool initialized;

  TrackingState copyWith({
    String? uniqueId,
    bool? running,
    bool? busy,
    int? boundDeviceId,
    String? serverDeviceName,
    List<TrackingLogEntry>? logs,
    int? batteryLevel,
    String? error,
    bool? initialized,
    bool clearError = false,
    bool clearBoundDevice = false,
  }) {
    return TrackingState(
      uniqueId: uniqueId ?? this.uniqueId,
      running: running ?? this.running,
      busy: busy ?? this.busy,
      boundDeviceId:
          clearBoundDevice ? null : (boundDeviceId ?? this.boundDeviceId),
      serverDeviceName:
          clearBoundDevice ? null : (serverDeviceName ?? this.serverDeviceName),
      logs: logs ?? this.logs,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      error: clearError ? null : (error ?? this.error),
      initialized: initialized ?? this.initialized,
    );
  }
}

/// 本机跟踪门面：设备标识、绑定、开始/停止、单次定位与 SOS。
class TrackingController extends AsyncNotifier<TrackingState> {
  @override
  Future<TrackingState> build() async {
    final prefs = ref.watch(appPreferencesProvider);
    final uniqueId = await _ensureUniqueId(prefs);
    final battery = await _readBattery();

    final server = ref.watch(activeServerProvider);
    int? boundDeviceId;
    if (server != null) {
      boundDeviceId = await prefs.loadBoundDeviceId(server.id);
    }

    // 只在第一次构建时读取 SDK 状态，避免每次切换页面触发 PlatformChannel。
    final engine = ref.watch(trackingEngineProvider);
    var running = false;
    var logs = const <TrackingLogEntry>[];
    var initialized = false;
    try {
      running = await engine.isTracking();
      logs = await engine.getLogs();
      initialized = true;
    } catch (_) {
      // 尚未 init 时部分平台会抛异常，属于正常状态。
    }

    return TrackingState(
      uniqueId: uniqueId,
      running: running,
      boundDeviceId: boundDeviceId,
      logs: logs.reversed.take(50).toList(growable: false),
      batteryLevel: battery,
      initialized: initialized,
    );
  }

  Future<String> _ensureUniqueId(AppPreferences prefs) async {
    final existing = await prefs.loadUniqueId();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final first = 1 + random.nextInt(9);
    final rest = List.generate(7, (_) => random.nextInt(10)).join();
    final uniqueId = '$first$rest';
    await prefs.saveUniqueId(uniqueId);
    return uniqueId;
  }

  Future<int?> _readBattery() async {
    try {
      return await Battery().batteryLevel;
    } catch (_) {
      return null;
    }
  }

  Future<void> refreshBattery() async {
    final level = await _readBattery();
    if (level != null && state.valueOrNull != null) {
      state = AsyncData(state.value!.copyWith(batteryLevel: level));
    }
  }

  TrackingState get _current => state.valueOrNull ?? const TrackingState();

  void _set(TrackingState next) => state = AsyncData(next);

  Future<void> setUniqueId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    await ref.read(appPreferencesProvider).saveUniqueId(trimmed);
    _set(_current.copyWith(uniqueId: trimmed, clearBoundDevice: true));
  }

  /// 登录后绑定本机：先按 uniqueId 查找，不存在则创建。
  Future<void> bindDevice() async {
    final api = ref.read(traccarApiProvider);
    final server = ref.read(activeServerProvider);
    if (api == null || server == null) {
      throw const AppFailure(FailureKind.unauthorized, '请先登录服务器');
    }
    final current = _current;
    _set(current.copyWith(busy: true, clearError: true));

    try {
      final device = await api.findDeviceByUniqueId(current.uniqueId) ??
          await api.createDevice(
            name: '本机 ${current.uniqueId}',
            uniqueId: current.uniqueId,
          );
      await ref
          .read(appPreferencesProvider)
          .saveBoundDeviceId(server.id, device.id);
      _set(
        _current.copyWith(
          busy: false,
          boundDeviceId: device.id,
          serverDeviceName: device.name,
        ),
      );
    } catch (error) {
      _set(
        _current.copyWith(
          busy: false,
          error: error is AppFailure ? error.message : error.toString(),
        ),
      );
      rethrow;
    }
  }

  /// 开始后台上报。首次会申请前台定位权限。
  Future<void> start() async {
    final server = ref.read(activeServerProvider);
    if (server == null) {
      throw const AppFailure(FailureKind.invalidServer, '请先配置服务器');
    }

    _set(_current.copyWith(busy: true, clearError: true));
    try {
      var permission = await Permission.locationWhenInUse.status;
      if (!permission.isGranted) {
        permission = await Permission.locationWhenInUse.request();
      }
      if (!permission.isGranted) {
        throw const AppFailure(
          FailureKind.forbidden,
          '需要定位权限才能开始上报，请在系统设置中开启',
        );
      }

      // 后台上报还依赖通知（前台服务）与“始终允许”定位。
      final background = await Permission.locationAlways.status;
      final notifications = await Permission.notification.status;
      if (!_allowed(background) || !_allowed(notifications)) {
        throw const AppFailure(
          FailureKind.forbidden,
          '请先完成权限向导：后台定位与通知权限缺失',
        );
      }

      final engine = ref.read(trackingEngineProvider);
      final config = TrackingConfig(
        reportUrl: server.reportUrl,
        deviceId: _current.uniqueId,
        intervalSeconds: 60,
        distanceMeters: 20,
        accuracy: TrackingAccuracy.high,
        heartbeatIntervalSeconds: 0,
        notificationText: 'TrackerOne 正在上报位置',
      );
      await engine.init(config);
      await engine.start();
      final logs = await engine.getLogs();
      _set(
        _current.copyWith(
          busy: false,
          running: true,
          initialized: true,
          logs: logs.reversed.take(50).toList(growable: false),
        ),
      );
    } catch (error) {
      _set(
        _current.copyWith(
          busy: false,
          error: error is AppFailure ? error.message : error.toString(),
        ),
      );
      rethrow;
    }
  }

  bool _allowed(PermissionStatus status) {
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited ||
        status == PermissionStatus.provisional;
  }

  Future<void> stop() async {
    _set(_current.copyWith(busy: true, clearError: true));
    try {
      final engine = ref.read(trackingEngineProvider);
      await engine.stop();
      _set(_current.copyWith(busy: false, running: false));
    } catch (error) {
      _set(
        _current.copyWith(
          busy: false,
          error: error is AppFailure ? error.message : error.toString(),
        ),
      );
    }
  }

  Future<bool> requestPosition({bool sos = false}) async {
    try {
      final engine = ref.read(trackingEngineProvider);
      return await engine.requestPosition(alarm: sos ? 'sos' : null);
    } catch (error) {
      _set(
        _current.copyWith(
          error: error is AppFailure ? error.message : error.toString(),
        ),
      );
      return false;
    }
  }

  Future<void> refreshLogs() async {
    try {
      final logs = await ref.read(trackingEngineProvider).getLogs();
      _set(
        _current.copyWith(
          logs: logs.reversed.take(50).toList(growable: false),
        ),
      );
    } catch (_) {
      // 未初始化时忽略。
    }
  }

  Future<void> clearLogs() async {
    try {
      await ref.read(trackingEngineProvider).clearLogs();
      _set(_current.copyWith(logs: const []));
    } catch (_) {
      // 未初始化时忽略。
    }
  }
}

final trackingProvider =
    AsyncNotifierProvider<TrackingController, TrackingState>(
  TrackingController.new,
);
