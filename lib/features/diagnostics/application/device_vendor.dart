import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 中国大陆常见会在后台清理应用的厂商。
///
/// 仅用于展示针对性的保活指引；无法真正修改系统设置。
enum DeviceVendor { xiaomi, huawei, oppo, vivo, samsung, other }

/// 通过 `manufacturer` / `brand` 粗略识别厂商。
///
/// 识别失败时返回 [DeviceVendor.other]，页面仍展示通用步骤。
DeviceVendor vendorFromStrings({String? manufacturer, String? brand}) {
  final value = '${manufacturer ?? ''} ${brand ?? ''}'.toLowerCase();
  if (value.isEmpty) return DeviceVendor.other;
  if (value.contains('xiaomi') ||
      value.contains('redmi') ||
      value.contains('poco')) {
    return DeviceVendor.xiaomi;
  }
  if (value.contains('huawei') || value.contains('honor')) {
    return DeviceVendor.huawei;
  }
  if (value.contains('oppo') ||
      value.contains('oneplus') ||
      value.contains('realme')) {
    return DeviceVendor.oppo;
  }
  if (value.contains('vivo') || value.contains('iqoo')) {
    return DeviceVendor.vivo;
  }
  if (value.contains('samsung')) return DeviceVendor.samsung;
  return DeviceVendor.other;
}

final deviceVendorProvider = FutureProvider<DeviceVendor>((ref) async {
  if (kIsWeb || !Platform.isAndroid) return DeviceVendor.other;
  try {
    final info = await DeviceInfoPlugin().androidInfo;
    return vendorFromStrings(
      manufacturer: info.manufacturer,
      brand: info.brand,
    );
  } catch (_) {
    return DeviceVendor.other;
  }
});
