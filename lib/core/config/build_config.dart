/// 构建期配置，通过 `--dart-define` 注入。
///
/// 示例：
/// ```bash
/// flutter run \
///   --dart-define=FLAVOR=dev \
///   --dart-define=MAP_PROVIDER=amap \
///   --dart-define=AMAP_ANDROID_KEY=xxx \
///   --dart-define=AMAP_IOS_KEY=yyy \
///   --dart-define=PUSH_PROVIDER=jpush \
///   --dart-define=JPUSH_APP_KEY=zzz
/// ```
abstract final class BuildConfig {
  static const String flavor = String.fromEnvironment(
    'FLAVOR',
    defaultValue: 'dev',
  );

  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const String reportUrl = String.fromEnvironment('REPORT_URL');

  /// 地图供应商：`amap`（中国大陆默认）或 `none`（未接入，显示占位）。
  ///
  /// 腾讯地图作为备选，接入时新增 `tencent` 分支即可，业务层不改。
  static const String mapProvider = String.fromEnvironment(
    'MAP_PROVIDER',
    defaultValue: 'amap',
  );

  /// 高德开放平台 Key，Android 与 iOS 需分别申请（与包名 / Bundle ID 绑定）。
  static const String amapAndroidKey = String.fromEnvironment(
    'AMAP_ANDROID_KEY',
  );
  static const String amapIosKey = String.fromEnvironment('AMAP_IOS_KEY');

  /// 推送通道：
  /// - `jpush`：中国大陆生产（聚合小米/华为/OPPO/vivo 厂商通道）
  /// - `fcm`：海外 / 开发
  /// - `none`：未接入，仅应用内 WebSocket 事件
  static const String pushProvider = String.fromEnvironment(
    'PUSH_PROVIDER',
    defaultValue: 'none',
  );

  static const String jpushAppKey = String.fromEnvironment('JPUSH_APP_KEY');
  static const String jpushChannel = String.fromEnvironment(
    'JPUSH_CHANNEL',
    defaultValue: 'developer-default',
  );

  /// 自建推送网关地址。App 用它在登录后注册别名；Traccar 用它投递事件。
  static const String pushGatewayUrl = String.fromEnvironment(
    'PUSH_GATEWAY_URL',
  );

  /// 崩溃上报：`firebase`（海外/开发）或 `none`（中国大陆默认，接 Bugly 后改）。
  static const String crashReporter = String.fromEnvironment(
    'CRASH_REPORTER',
    defaultValue: 'none',
  );

  static bool get hasApiOverride => apiBaseUrl.isNotEmpty;

  static bool get isProd => flavor == 'prod';

  /// 中国大陆包：使用高德底图 + 国产推送通道。
  static bool get isChinaBuild => mapProvider == 'amap';

  static bool get hasAmapKey =>
      amapAndroidKey.isNotEmpty || amapIosKey.isNotEmpty;
}
