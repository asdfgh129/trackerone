# 10 · 环境搭建与 M0 执行手册

> 面向「Flutter 刚装好、还没生成平台工程」的状态。
> 目标：一天内跑通 `flutter doctor` → 平台工程 → `pub get` → `analyze/test` →
> 高德地图真机 → 登录/WebSocket → 后台定位。

## 1. 当前环境快照

| 项 | 现状 | 结论 |
|---|---|---|
| macOS | 13.6.7 Ventura（Intel x86_64） | ⚠️ 见 3.1 |
| Homebrew | 6.0.22 | ✅ |
| Flutter / Dart | 用户安装中 | 待验证 |
| Android SDK | `~/Library/Android/sdk`，adb 可用 | ✅ |
| Java | Temurin 17.0.20 | ✅ |
| Xcode | 仅 Command Line Tools | ❌ 需完整 Xcode |
| CocoaPods | 未安装 | ❌ |
| 磁盘 | 剩余约 300 GB | ✅ |

---

## 2. 验证 Flutter

```bash
flutter --version
dart --version
which flutter dart
```

期望：当前 Flutter stable（≥ 3.29，Dart 3.x），路径可执行。

若用 Homebrew 安装，默认在 `/usr/local/share/flutter`；若用官方 zip，
建议解压到 `~/development/flutter` 并把 `bin` 加入 `~/.zshrc`：

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
```

然后：

```bash
flutter doctor -v
```

逐项处理 `doctor` 的 `[!]`。下面的顺序能减少来回折腾：

```
Flutter → Android toolchain → Xcode → CocoaPods → 设备
```

---

## 3. 补齐 iOS 工具链

### 3.1 先看 macOS 版本（重要）

- Xcode 16+ 需要 macOS 14.5+；macOS 13.6 最高只能装 Xcode 15.x。
- 而 App Store 对新提交通常要求「用当年最新 Xcode / iOS SDK 构建」。
- 结论：**这台 Ventura 机器不适合作为 iOS 发布机**。可选：
  1. 升级 macOS 到当前最新（Intel 机型需确认支持）；
  2. iOS 构建交给云端 CI（Codemagic / GitHub Actions `macos-latest`）；
  3. 另备一台 Apple Silicon Mac 做 iOS 发布。
- Android 开发不受影响，可先在当前机器推进。

### 3.2 安装 Xcode

```bash
# 从 App Store 安装完整 Xcode 后：
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
xcodebuild -version
```

### 3.3 安装 CocoaPods

```bash
# Intel Mac 推荐 Homebrew（避免系统 Ruby 权限问题）
brew install cocoapods
pod --version
```

> 若项目后续用 Swift Package Manager（Flutter 3.29+ 可选），仍建议保留 CocoaPods 兼容。

### 3.4 模拟器

```bash
xcodebuild -downloadPlatform iOS
open -a Simulator
flutter devices
```

---

## 4. Android 环境

```bash
flutter doctor --android-licenses    # 全部 y
sdkmanager --list | head             # 确认 platforms;android-37 可装
sdkmanager "platforms;android-37" "build-tools;37.0.0"
```

`traccar_client_sdk` 要求（以 pub.dev README 为准）：

| 项 | 要求 |
|---|---|
| minSdk | 24 |
| compileSdk | 37 |
| Kotlin | 2.4.20+ |
| Java | 17 |

真机调试：

```bash
adb devices
# 打开开发者选项 → USB 调试 → 授权
```

---

## 5. 生成平台工程

### 5.1 用脚本（推荐）

```bash
cd trackerone
tool/bootstrap.sh
```

脚本会在临时目录执行 `flutter create`，只把 `android/`、`ios/` 复制回来，
不会覆盖 `lib/`、`docs/`、`pubspec.yaml`。

### 5.2 手动等价命令

```bash
cd trackerone
TMP=$(mktemp -d)
flutter create --platforms=android,ios --org com.example \
  --project-name trackerone --no-pub "$TMP/platform"
cp -R "$TMP/platform/android" "$TMP/platform/ios" .
rm -rf "$TMP"
```

### 5.3 校验包名

```bash
grep -r "applicationId" android/app/build.gradle*
grep -r "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj | head -2
```

期望：`com.example.trackerone`。

> **发布前必须改**：`com.example.*` 无法作为正式上架包名（部分商店直接拒绝，
> 且发布后不可更改）。改名涉及包名、Bundle ID、高德 Key、极光 AppKey、Firebase
> 应用注册。建议在 M0 结束前就换成真实反向域名。

---

## 6. 依赖与代码生成

```bash
flutter pub get
flutter analyze
flutter test
```

或直接运行：

```bash
tool/verify.sh
```

脚本会依次执行依赖解析、`gen-l10n`、`analyze`、`test`，任一硬步骤失败即退出。

若 `pub get` 报版本冲突，按顺序处理：

1. 先注释掉 `amap_map` / `jpush_flutter`，确认基础依赖可解析；
2. 再逐个加回，看冲突来源；
3. `flutter pub deps --style=compact` 查传递依赖。

`drift` 代码生成（表结构落地后）：

```bash
dart run build_runner build --delete-conflicting-outputs
```

多语言：

```bash
flutter gen-l10n
```

---

## 7. 原生配置

### 7.1 Android

`android/app/src/main/AndroidManifest.xml`：

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

  <uses-permission android:name="android.permission.INTERNET" />
  <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
  <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
  <uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
  <uses-permission android:name="android.permission.ACTIVITY_RECOGNITION" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
  <uses-permission android:name="android.permission.FOREGROUND_SERVICE_LOCATION" />
  <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
  <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
  <uses-permission android:name="android.permission.WAKE_LOCK" />
  <uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />

  <application
      android:label="TrackerOne"
      android:allowNativeHeapPointerTagging="false">   <!-- 高德地图 targetSdk>=30 必需 -->
    <!-- ... -->
  </application>
</manifest>
```

`android/app/build.gradle.kts`（Kotlin DSL，3.29+ 默认）：

```kotlin
android {
    namespace = "com.example.trackerone"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.example.trackerone"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["JPUSH_PKGNAME"] = applicationId
        manifestPlaceholders["JPUSH_APPKEY"] = "替换为极光 AppKey"
        manifestPlaceholders["JPUSH_CHANNEL"] = "developer-default"
    }

    compileOptions {
        isCoreLibraryDesugaringEnabled = true  // flutter_local_notifications 需要
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

> 若 `flutter create` 仍生成 `build.gradle`（Groovy），语法改为
> `manifestPlaceholders = [JPUSH_PKGNAME: applicationId, ...]`。

JPush 厂商通道点击白屏（Flutter 3.29+）需在 `MainActivity` 关闭自动深链：

```kotlin
class MainActivity : FlutterActivity() {
    override fun shouldHandleDeeplinking(): Boolean = false
}
```

或 Manifest：

```xml
<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
```

### 7.2 iOS

`ios/Runner/Info.plist`：

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>用于在地图上显示您的位置。</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>用于在后台持续上报位置，您可以随时停止。</string>
<key>NSMotionUsageDescription</key>
<string>用于判断是否静止，以减少耗电。</string>
<key>UIBackgroundModes</key>
<array>
  <string>location</string>
  <string>fetch</string>
  <string>remote-notification</string>
</array>
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
  <string>org.traccar.client.heartbeat</string>
</array>
```

`ios/Podfile` 首行取消注释并改为：

```ruby
platform :ios, '15.0'
```

Xcode 中为 Runner 开启：

- Signing & Capabilities → **Push Notifications**
- Background Modes → Location updates / Background fetch / Remote notifications

---

## 8. 配置高德地图

```bash
flutter run \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY=你的AndroidKey \
  --dart-define=AMAP_IOS_KEY=你的iOSKey
```

- Android Key 绑定「包名 + SHA1」，debug/release 各一个；
- iOS Key 绑定 Bundle ID；
- 首次进地图会展示合规卡片，同意后才初始化 SDK；
- 看不到地图时先查 Key 与包名，再查 `allowNativeHeapPointerTagging`。

### 8.1 已核对的高德 API（amap_map 1.0.15）

以下签名来自包源码，接入时按此写，升级版本后需重新核对：

| 用途 | 签名 |
|---|---|
| 隐私授权 | `AMapInitializer.updatePrivacyAgree(AMapPrivacyStatement(hasContains:, hasShow:, hasAgree:))` |
| 初始化 | `AMapInitializer.init(context, apiKey: AMapApiKey(androidKey:, iosKey:))` |
| 地图 | `AMapWidget(initialCameraPosition:, markers: Set<Marker>, polylines: Set<Polyline>, onTap:, onMapCreated:)` |
| 标记 | `Marker(position: LatLng, infoWindow: InfoWindow, onTap: (String id) {})` |
| 线 | `Polyline(points: List<LatLng>, color: Color, width: double)` |

注意：

- `AMapApiKey` 与 `AMapPrivacyStatement` 定义在 `x_amap_base`，必须**额外 import**：
  `import 'package:x_amap_base/x_amap_base.dart';`
- `LatLng` / `CameraPosition` 虽经 `amap_map` 导出，但 `LatLng` 仍来自 `x_amap_base`；
- `Marker.onTap` 是 `void Function(String id)`，不是无参回调；
- `Polyline.width` 是 `double`，传 `int` 变量需 `.toDouble()`；
- 隐私声明必须在 `AMapWidget` 首次 build 前设置，否则白屏。

---

## 9. 配置推送

```bash
flutter run \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY=你的AppKey
```

验收：登录后 `setAlias("u1@1")` 成功 → 服务端调网关 → 手机收到通知。

未配置推送时用 `PUSH_PROVIDER=none`，应用内仍可通过 WebSocket 收事件。

### 9.1 已核对的极光 API（jpush_flutter 3.6.0）

| 用途 | 签名 |
|---|---|
| 创建 | `JPush.newJPush()` → `JPushFlutterInterface` |
| 初始化 | `setup({appKey, channel, production, debug})`，**同步方法，不能 await** |
| 别名 | `Future<Map<dynamic, dynamic>> setAlias(String alias)` |
| 事件 | `addEventHandler({onReceiveNotification, onOpenNotification, ...})` |
| 冷启动 | `Future<Map<dynamic, dynamic>> getLaunchAppNotification()` |
| 角标 | `setBadge(int)` |

注意：

- 3.6.0 没有 `getLaunchApp()`，旧示例里的这个名字会编译失败；
- 业务字段统一放在通知的 `extras`，代码从 `message['extras']` 解析；
- 厂商通道点击在 Flutter 3.29+ 会触发深链白屏，必须关闭自动深链（见 7.1）。

---

## 10. 服务端

```bash
# 1) 把补丁文件放进 Traccar
cp server/traccar-plugin/src/main/java/org/traccar/notificators/NotificatorWebhook.java \
   ../traccar/src/main/java/org/traccar/notificators/

# 2) 编辑 NotificatorManager 注册 "webhook"（见 server/README.md）

# 3) 配置 conf/traccar.xml 并重启
```

自检：

```bash
curl -s http://localhost:8082/api/server | jq .version
```

---

## 11. M0 验收清单（1 周）

| # | 验证项 | 通过标准 | 方法 |
|---|---|---|---|
| 0.1 | 工程可构建 | `analyze` 0 error，`test` 全绿 | CI / 本地 |
| 0.2 | 高德地图 | 真机显示底图、标记、轨迹，无闪退 | 真机 |
| 0.3 | 登录 + Token | 密码登录 → Token → `GET /api/session` 成功 | 测试服务器 |
| 0.4 | WebSocket | 连接成功，收到 `positions` 快照与增量 | 日志 |
| 0.5 | 本机上报 | 服务端出现位置，24h 心跳 ≥ 95% | Traccar 报表 |
| 0.6 | 后台存活 | 锁屏 2h 不断档（小米/华为/OPPO 各一台） | 真机 |
| 0.7 | 推送 | 后台/冷启动点击直达事件 | 极光后台 |
| 0.8 | 坐标 | 高德地图位置与真实位置偏差 < 20m | 实地对比 |

**Gate：** 0.2 / 0.5 / 0.6 任一失败，先解决再进入 M1。

### 建议日程

| 天 | 任务 |
|---|---|
| D1 | `flutter doctor` 全绿、生成平台工程、`pub get` / `analyze` / `test` |
| D2 | 高德 Key、地图真机、坐标校验 |
| D3 | 登录 + Token + WebSocket 最小闭环 |
| D4 | `TrackingEngine` 接入、开始/停止上报 |
| D5 | 国产 ROM 后台 2h 验证、诊断日志 |
| D6 | 推送网关联调（可先用 curl 模拟） |
| D7 | 汇总数据、更新 ADR、决定是否进入 M1 |

---

## 12. 常见问题

| 现象 | 原因 | 处理 |
|---|---|---|
| `flutter: command not found` | PATH 未生效 | 重开终端或 `source ~/.zshrc` |
| `CocoaPods not installed` | 未装 pod | `brew install cocoapods` |
| `Xcode not set up properly` | 只装了 CLT | `sudo xcode-select -s /Applications/Xcode.app/...` |
| Android license 未接受 | 首次使用 | `flutter doctor --android-licenses` |
| 高德地图白屏 | Key/包名/SHA1 不匹配 | 重新申请 Key，核对签名 |
| 地图页返回闪退 | targetSdk ≥ 30 | `allowNativeHeapPointerTagging="false"` |
| 收不到极光推送 | 厂商通道未开/别名未注册 | 查极光后台状态 + `setAlias` 日志 |
| `pub get` 版本冲突 | 依赖版本过新 | 降级 `amap_map` / `jpush_flutter` 或先移除 |
| iOS 真机无法运行 | 签名/描述文件 | Xcode 登录 Apple ID，配置 Team |
| 后台上报 10 分钟断 | 厂商省电策略 | 加入白名单，见 `docs/05` 6.3 |

---

## 13. 下一步

M0 通过后按 [`docs/06-roadmap.md`](06-roadmap.md) 进入 M1：

1. 服务器档案 + 二维码 + 测试连接；
2. 登录 / Token / Secure Storage / 生物识别；
3. drift 缓存 + Repository；
4. 引导流程与权限向导；
5. 把 `TrackerMapView` 接到真实设备数据。
