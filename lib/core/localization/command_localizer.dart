import '../../domain/entities/device_command.dart';
import '../../l10n/app_localizations.dart';

/// 指令类型的本地化名称。
///
/// 指令选择面板、队列与消息中心共用，避免各自复制同一份 switch。
String commandTypeLabel(AppLocalizations l10n, DeviceCommandType type) =>
    switch (type) {
      DeviceCommandType.positionSingle => l10n.commandPositionSingle,
      DeviceCommandType.positionPeriodic => l10n.commandPositionPeriodic,
      DeviceCommandType.engineStop => l10n.commandEngineStop,
      DeviceCommandType.engineResume => l10n.commandEngineResume,
      DeviceCommandType.alarmArm => l10n.commandAlarmArm,
      DeviceCommandType.alarmDisarm => l10n.commandAlarmDisarm,
      DeviceCommandType.rebootDevice => l10n.commandReboot,
      DeviceCommandType.factoryReset => l10n.commandFactoryReset,
      DeviceCommandType.message => l10n.commandMessage,
    };

/// 指令类型的说明文案（用于选择面板）。
String commandTypeDescription(AppLocalizations l10n, DeviceCommandType type) =>
    switch (type) {
      DeviceCommandType.positionSingle => l10n.commandPositionSingleDesc,
      DeviceCommandType.positionPeriodic => l10n.commandPositionPeriodicDesc,
      DeviceCommandType.engineStop => l10n.commandEngineStopDesc,
      DeviceCommandType.engineResume => l10n.commandEngineResumeDesc,
      DeviceCommandType.alarmArm => l10n.commandAlarmArmDesc,
      DeviceCommandType.alarmDisarm => l10n.commandAlarmDisarmDesc,
      DeviceCommandType.rebootDevice => l10n.commandRebootDesc,
      DeviceCommandType.factoryReset => l10n.commandFactoryResetDesc,
      DeviceCommandType.message => l10n.commandMessageDesc,
    };
