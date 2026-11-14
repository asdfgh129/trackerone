import 'package:url_launcher/url_launcher.dart';

/// 用系统浏览器打开外部链接。
///
/// 返回 `false` 表示设备上没有可处理该链接的应用，调用方自行提示。
Future<bool> openExternalUrl(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.hasScheme) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 部分定制 ROM 会抛 PlatformException，统一按失败处理。
    return false;
  }
}
