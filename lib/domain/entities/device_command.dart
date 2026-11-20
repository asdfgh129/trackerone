import 'package:flutter/material.dart';

/// Traccar 支持的内置指令类型。
///
/// 具体设备支持哪些指令由 `device.attributes.supportedCommands` 决定；
/// 未提供该字段时展示常用指令并提示可能不被设备支持。
enum DeviceCommandType {
  positionSingle('positionSingle'),
  positionPeriodic('positionPeriodic'),
  engineStop('engineStop'),
  engineResume('engineResume'),
  alarmArm('alarmArm'),
  alarmDisarm('alarmDisarm'),
  rebootDevice('rebootDevice'),
  factoryReset('factoryReset'),
  message('message');

  const DeviceCommandType(this.apiType);

  /// 发送给 Traccar `/api/commands/send` 的 `type`。
  final String apiType;

  bool get isDestructive =>
      this == DeviceCommandType.factoryReset ||
      this == DeviceCommandType.rebootDevice;

  bool get needsConfirmation => isDestructive;

  /// 需要用户输入附加参数。
  bool get needsInput =>
      this == DeviceCommandType.positionPeriodic ||
      this == DeviceCommandType.message;

  IconData get icon => switch (this) {
    DeviceCommandType.positionSingle => Icons.my_location,
    DeviceCommandType.positionPeriodic => Icons.timer_outlined,
    DeviceCommandType.engineStop => Icons.power_settings_new,
    DeviceCommandType.engineResume => Icons.play_circle_outline,
    DeviceCommandType.alarmArm => Icons.lock_outline,
    DeviceCommandType.alarmDisarm => Icons.lock_open,
    DeviceCommandType.rebootDevice => Icons.restart_alt,
    DeviceCommandType.factoryReset => Icons.delete_forever_outlined,
    DeviceCommandType.message => Icons.message_outlined,
  };

  /// 把服务端下发的 `type` 还原成枚举；未知类型返回 null。
  static DeviceCommandType? tryParse(String? apiType) {
    for (final value in values) {
      if (value.apiType == apiType) return value;
    }
    return null;
  }

  /// 从 `supportedCommands` 构建可选指令；列表为空时返回常用集合。
  static List<DeviceCommandType> fromSupported(Iterable<Object?>? supported) {
    if (supported == null) return const [];
    final names =
        supported
            .map((item) => item?.toString() ?? '')
            .where((name) => name.isNotEmpty)
            .toSet();
    if (names.isEmpty) return const [];
    return DeviceCommandType.values
        .where((command) => names.contains(command.apiType))
        .toList(growable: false);
  }
}

/// 指令参数构造，集中放在领域层便于单测。
Map<String, dynamic> buildCommandAttributes(
  DeviceCommandType type, {
  int? frequencySeconds,
  String? message,
}) {
  return switch (type) {
    DeviceCommandType.positionPeriodic => {
      if (frequencySeconds != null) 'frequency': frequencySeconds,
    },
    DeviceCommandType.message => {
      if (message != null && message.isNotEmpty) 'message': message,
    },
    _ => const {},
  };
}
