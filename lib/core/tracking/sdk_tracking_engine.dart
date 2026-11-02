import 'dart:async';

import 'package:traccar_client_sdk/traccar_client_sdk.dart' as sdk;

import 'tracking_engine.dart';

/// `traccar_client_sdk` 适配器。
///
/// 注意：
/// - SDK 的 `serverUrl` 是位置上报入口，不是 Web 控制台地址。
/// - iOS 需要在 `main()` 尽早初始化，以便系统后台唤醒时重建 tracker。
class SdkTrackingEngine implements TrackingEngine {
  SdkTrackingEngine({sdk.TraccarClientSdk? client})
      : _client = client ?? sdk.TraccarClientSdk();

  final sdk.TraccarClientSdk _client;
  final StreamController<TrackingEvent> _events =
      StreamController<TrackingEvent>.broadcast();

  @override
  Stream<TrackingEvent> get events => _events.stream;

  @override
  Future<void> init(TrackingConfig config) async {
    await _client.init(_toSdk(config));
  }

  @override
  Future<void> applyConfig(TrackingConfig config) async {
    await _client.setConfig(_toSdk(config));
  }

  @override
  Future<void> start() async {
    await _client.start();
    _events.add(const TrackingEvent(TrackingEventType.started));
  }

  @override
  Future<void> stop() async {
    await _client.stop();
    _events.add(const TrackingEvent(TrackingEventType.stopped));
  }

  @override
  Future<bool> requestPosition({String? alarm}) async {
    final ok = await _client.requestPosition(alarm: alarm);
    _events.add(
      TrackingEvent(
        ok ? TrackingEventType.positionUploaded : TrackingEventType.uploadFailed,
      ),
    );
    return ok;
  }

  @override
  Future<bool> isTracking() => _client.isTracking();

  @override
  Future<List<TrackingLogEntry>> getLogs() async {
    final entries = await _client.getLogs();
    return entries
        .map(
          (entry) => TrackingLogEntry(
            time: DateTime.fromMillisecondsSinceEpoch(entry.time),
            message: entry.message,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> clearLogs() => _client.clearLogs();

  void dispose() {
    _events.close();
  }

  sdk.Config _toSdk(TrackingConfig config) {
    return sdk.Config(
      serverUrl: config.reportUrl,
      deviceId: config.deviceId,
      headers: config.headers,
      wakeLock: config.wakeLock,
      buffer: config.buffer,
      preferPlatformProviders: config.preferPlatformProviders,
      notification: sdk.NotificationConfig(text: config.notificationText),
      location: sdk.LocationConfig(
        accuracy: switch (config.accuracy) {
          TrackingAccuracy.highest => sdk.Accuracy.highest,
          TrackingAccuracy.high => sdk.Accuracy.high,
          TrackingAccuracy.medium => sdk.Accuracy.medium,
          TrackingAccuracy.low => sdk.Accuracy.low,
        },
        distanceMeters: config.distanceMeters,
        intervalSeconds: config.intervalSeconds,
        angleDegrees: config.angleDegrees,
        heartbeatIntervalSeconds: config.heartbeatIntervalSeconds,
        stopDetection: config.stopDetection,
      ),
    );
  }
}
