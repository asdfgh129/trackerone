/// 跟踪引擎抽象。业务层只依赖本接口，不直接依赖任何定位 SDK。
library;

enum TrackingAccuracy { highest, high, medium, low }

class TrackingConfig {
  const TrackingConfig({
    required this.reportUrl,
    required this.deviceId,
    this.headers = const {},
    this.accuracy = TrackingAccuracy.medium,
    this.intervalSeconds = 300,
    this.distanceMeters = 75,
    this.angleDegrees = 0,
    this.heartbeatIntervalSeconds = 0,
    this.buffer = true,
    this.stopDetection = true,
    this.wakeLock = false,
    this.preferPlatformProviders = false,
    this.notificationText = 'Location tracking',
  });

  /// 位置上报地址（不是 Web/API 地址）。
  final String reportUrl;
  final String deviceId;
  final Map<String, String> headers;
  final TrackingAccuracy accuracy;
  final int intervalSeconds;
  final int distanceMeters;
  final int angleDegrees;
  final int heartbeatIntervalSeconds;
  final bool buffer;
  final bool stopDetection;
  final bool wakeLock;
  final bool preferPlatformProviders;
  final String notificationText;

  TrackingConfig copyWith({
    String? reportUrl,
    String? deviceId,
    Map<String, String>? headers,
    TrackingAccuracy? accuracy,
    int? intervalSeconds,
    int? distanceMeters,
    int? angleDegrees,
    int? heartbeatIntervalSeconds,
    bool? buffer,
    bool? stopDetection,
    bool? wakeLock,
    bool? preferPlatformProviders,
    String? notificationText,
  }) {
    return TrackingConfig(
      reportUrl: reportUrl ?? this.reportUrl,
      deviceId: deviceId ?? this.deviceId,
      headers: headers ?? this.headers,
      accuracy: accuracy ?? this.accuracy,
      intervalSeconds: intervalSeconds ?? this.intervalSeconds,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      angleDegrees: angleDegrees ?? this.angleDegrees,
      heartbeatIntervalSeconds:
          heartbeatIntervalSeconds ?? this.heartbeatIntervalSeconds,
      buffer: buffer ?? this.buffer,
      stopDetection: stopDetection ?? this.stopDetection,
      wakeLock: wakeLock ?? this.wakeLock,
      preferPlatformProviders:
          preferPlatformProviders ?? this.preferPlatformProviders,
      notificationText: notificationText ?? this.notificationText,
    );
  }
}

enum TrackingEventType {
  started,
  stopped,
  positionUploaded,
  uploadFailed,
  queueChanged,
}

class TrackingEvent {
  const TrackingEvent(this.type, {this.message, this.queueSize});

  final TrackingEventType type;
  final String? message;
  final int? queueSize;
}

class TrackingLogEntry {
  const TrackingLogEntry({required this.time, required this.message});

  final DateTime time;
  final String message;
}

abstract interface class TrackingEngine {
  Future<void> init(TrackingConfig config);
  Future<void> start();
  Future<void> stop();
  Future<bool> requestPosition({String? alarm});
  Future<bool> isTracking();
  Future<void> applyConfig(TrackingConfig config);
  Stream<TrackingEvent> get events;
  Future<List<TrackingLogEntry>> getLogs();
  Future<void> clearLogs();
}
