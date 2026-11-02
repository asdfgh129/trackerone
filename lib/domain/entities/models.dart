/// 与 Traccar API 对应的领域模型。
///
/// 只保留 v1 需要的字段，未知字段进入 `attributes` 或 `raw`，避免服务端升级时崩溃。
library;

class Device {
  const Device({
    required this.id,
    required this.name,
    required this.uniqueId,
    required this.status,
    this.lastUpdate,
    this.category,
    this.attributes = const {},
  });

  final int id;
  final String name;
  final String uniqueId;
  final String status;
  final DateTime? lastUpdate;
  final String? category;
  final Map<String, dynamic> attributes;

  bool get isOnline => status == 'online';

  factory Device.fromJson(Map<String, dynamic> json) {
    return Device(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '',
      uniqueId: json['uniqueId'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      lastUpdate: _asDate(json['lastUpdate']),
      category: json['category'] as String?,
      attributes: _asMap(json['attributes']),
    );
  }
}

class Position {
  const Position({
    required this.id,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    this.fixTime,
    this.speedKnots = 0,
    this.course = 0,
    this.altitude,
    this.accuracy,
    this.attributes = const {},
  });

  final int id;
  final int deviceId;
  final double latitude;
  final double longitude;
  final DateTime? fixTime;

  /// Traccar 以节（knots）存储速度。
  final double speedKnots;
  final double course;
  final double? altitude;
  final double? accuracy;
  final Map<String, dynamic> attributes;

  double get speedMetersPerSecond => speedKnots * 0.514444;

  double? get batteryLevel {
    final value = attributes['batteryLevel'];
    return value is num ? value.toDouble() : null;
  }

  factory Position.fromJson(Map<String, dynamic> json) {
    return Position(
      id: _asInt(json['id']),
      deviceId: _asInt(json['deviceId']),
      latitude: _asDouble(json['latitude']) ?? 0,
      longitude: _asDouble(json['longitude']) ?? 0,
      fixTime: _asDate(json['fixTime'] ?? json['deviceTime']),
      speedKnots: _asDouble(json['speed']) ?? 0,
      course: _asDouble(json['course']) ?? 0,
      altitude: _asDouble(json['altitude']),
      accuracy: _asDouble(json['accuracy']),
      attributes: _asMap(json['attributes']),
    );
  }
}

class DeviceEvent {
  const DeviceEvent({
    required this.id,
    required this.deviceId,
    required this.type,
    this.eventTime,
    this.positionId,
    this.geofenceId,
    this.attributes = const {},
  });

  final int id;
  final int deviceId;
  final String type;
  final DateTime? eventTime;
  final int? positionId;
  final int? geofenceId;
  final Map<String, dynamic> attributes;

  factory DeviceEvent.fromJson(Map<String, dynamic> json) {
    return DeviceEvent(
      id: _asInt(json['id']),
      deviceId: _asInt(json['deviceId']),
      type: json['type'] as String? ?? 'unknown',
      eventTime: _asDate(json['eventTime']),
      positionId: json['positionId'] == null ? null : _asInt(json['positionId']),
      geofenceId: json['geofenceId'] == null ? null : _asInt(json['geofenceId']),
      attributes: _asMap(json['attributes']),
    );
  }
}

class Account {
  const Account({
    required this.id,
    required this.name,
    required this.email,
    this.administrator = false,
    this.attributes = const {},
  });

  final int id;
  final String name;
  final String email;
  final bool administrator;
  final Map<String, dynamic> attributes;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      administrator: json['administrator'] as bool? ?? false,
      attributes: _asMap(json['attributes']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? _asDate(Object? value) {
  if (value is String) return DateTime.tryParse(value);
  return null;
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}
