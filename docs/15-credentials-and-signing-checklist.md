# 15 · Key、签名与资质申请清单

> 适用：TrackerOne `0.4.0`，首发中国大陆，海外可选。
> 目标：把「需要你申请的东西」一次列全，并说明**产物放到项目哪里**、**怎么验证生效**。
> 最后更新：2026-11-06

---

## 0. 先做三个决定（否则后面全部要返工）

| 决定 | 说明 | 影响 |
|---|---|---|
| **正式包名 / Bundle ID** | 例如 `com.yourcompany.trackerone`，必须与营业执照/品牌一致，发布后不可更改 | 高德 Key、极光厂商通道、Firebase、Apple App ID、商店应用全部绑定它 |
| **主体** | 个人 / 企业 | 华为、小米、OPPO、vivo、荣耀厂商通道通常要求**企业认证**；个人只能走极光自有通道，到达率低 |
| **域名** | 例如 `track.example.com`、`push.example.com` | ICP 备案、HTTPS 证书、隐私政策 URL、推送网关、APP 备案都依赖它 |

> **改包名 = 高德 Key、极光厂商通道、Firebase、Apple App ID、商店应用全部重申请。**
> 先把包名定死，再开始申请。

**已定稿（2026-11-06）**：

```text
Android applicationId : com.trackerone.app
iOS Bundle ID         : com.trackerone.app
Deep link scheme      : trackerone
API 域名              : 待定（建议 track.<公司域名>）
推送网关域名          : 待定（建议 push.<公司域名>）
隐私政策 URL          : 待定（Brand.privacyUrl）
支持邮箱              : 待定（Brand.supportUrl）
```

> 如果公司要求使用自有反向域名（如 `com.yourcompany.trackerone`），
> 必须在申请高德/极光 Key **之前**改完。当前代码、Gradle、Xcode 已统一为
> `com.trackerone.app`，改包名需要同步修改：
> `android/app/build.gradle.kts`、`android/app/src/main/kotlin/.../MainActivity.kt`、
> `lib/core/config/brand.dart`、`ios/Runner/Info.plist`、`project.pbxproj`。

---

## 1. 总览：要申请什么

| # | 项目 | 是否阻塞上架 | 主体 | 周期 | 费用 | 产物 |
|---|---|---|---|---|---|---|
| 1 | 高德开放平台 + Android/iOS Key | 是（地图） | 个人/企业 | 1 天 | 免费额度，商用另计 | Android Key、iOS Key、审图号 |
| 2 | 极光 JPush 账号 + AppKey | 是（推送） | 个人/企业 | 1 天 | 免费版 + 付费档 | AppKey、Master Secret |
| 3 | 小米推送通道 | 建议 | 企业 | 3–5 工作日 | 免费 | AppSecret |
| 4 | 华为 Push Kit / AGC | 建议 | 企业 | 5–10 工作日 | 免费 | AppId、AppSecret |
| 5 | 荣耀推送 | 建议 | 企业 | 3–7 工作日 | 免费 | AppId、AppSecret |
| 6 | OPPO 推送 | 建议 | 企业 | 3–7 工作日 | 免费 | AppKey、MasterSecret |
| 7 | vivo 推送 | 建议 | 企业 | 3–7 工作日 | 免费 | AppId、AppKey、AppSecret |
| 8 | Android 上传密钥（keystore） | 是 | — | 10 分钟 | 0 | `.jks` + 密码 |
| 9 | Apple Developer Program | 是（iOS） | 个人/企业 | 1–3 天 | ¥688/年（以官网为准） | Team ID、证书、描述文件、APNs Key |
| 10 | APNs Auth Key（.p8） | 是（iOS 推送） | 同 Apple | 10 分钟 | 含在开发者账号 | `.p8` + Key ID |
| 11 | Firebase 项目（仅海外） | 否（国内不用） | — | 1 天 | 免费 | `google-services.json`、`GoogleService-Info.plist` |
| 12 | 域名 + HTTPS 证书 | 是 | 企业/个人 | 1 天 + 备案 | 域名/证书费用 | 域名、证书 |
| 13 | 域名 ICP 备案 | 是（境内服务器） | 主体 | 1–3 周 | 免费 | ICP 备案号 |
| 14 | **APP 备案** | **是（硬门槛）** | 主体 | 5–20 工作日 | 免费 | APP 备案号 |
| 15 | 软件著作权 | 多数国内商店要求 | 主体 | 30–60 自然日 | 官方免费/代理加急收费 | 软著证书 |
| 16 | 隐私政策 + SDK 清单 | 是 | 产品/法务 | 3–5 天 | 0 | 可访问 URL、清单 |
| 17 | 推送网关 + HMAC Secret | 是（推送联调） | 后端 | 2–5 人日 | 服务器成本 | 网关地址、Secret |
| 18 | 应用商店开发者账号 | 是 | 主体 | 1–7 天 | 多数免费 | 商店后台 |
| 19 | 地图审图号展示 | 是（合规） | 高德提供 | 随 Key | 0 | 审图号文本 |
| 20 | 账号注销服务端接口 | 是（合规） | 后端 | 2–3 人日 | 0 | 删除/匿名化接口 |

---

## 2. 高德地图（必须）

### 2.1 申请地址

- 官网：<https://lbs.amap.com/>
- 控制台：<https://console.amap.com/dev/key/app>
- 文档：<https://lbs.amap.com/api/android-sdk/guide/create-project/get-key>

### 2.2 操作步骤

1. 注册高德开放平台账号，完成**实名认证**（个人/企业）。
2. 控制台 → 应用管理 → 创建新应用：
   - 应用名称：`TrackerOne`
   - 应用类型：出行/导航
3. 为同一应用添加 **Android Key**：
   - Key 名称：`TrackerOne-Android-Release`
   - 绑定包名：`com.trackerone.app`
   - 绑定 SHA1：**release keystore 的 SHA1**
   - 如要支持 debug 包，再建一个 Key 绑定 debug SHA1。
4. 为同一应用添加 **iOS Key**：
   - Key 名称：`TrackerOne-iOS`
   - 绑定 Bundle ID：`com.trackerone.app`
5. 记录：
   - `AMAP_ANDROID_KEY`
   - `AMAP_IOS_KEY`
6. 在控制台/文档获取**地图审图号**，后续展示在「关于」页。

> **当前进度（2026-11-13）**
>
> - Android Key：`3c5cfa8ef73973fb579289710cc2370f`（已写入
>   `lib/core/config/build_config.dart` 默认值，release 构建自动生效）
> - iOS Key：待申请（Bundle ID 使用 `com.trackerone.app`）
> - Release SHA1：`0B:21:56:4F:7E:F3:91:9E:60:35:68:1D:84:88:D9:FD:D6:AB:0E:E9`
> - Debug SHA1（模拟器/调试包需要单独绑定）：
>   `1F:1D:98:73:A1:7B:7B:88:FF:6C:8B:98:BB:71:A4:41:5C:81:39:85`

### 2.3 获取 SHA1

Debug：

```bash
keytool -list -v \
  -keystore ~/.android/debug.keystore \
  -alias androiddebugkey \
  -storepass android -keypass android \
  | grep -E "SHA1|SHA-1"
```

Release（先生成 keystore，见第 7 节）：

```bash
keytool -list -v \
  -keystore android/app/upload-keystore.jks \
  -alias upload \
  | grep -E "SHA1|SHA-1|MD5"
```

### 2.4 项目注入

Android Key 已内置默认值，正常构建无需再传：

```bash
flutter build apk --release
```

需要切换 Key（例如 CI 或多环境）时再覆盖：

```bash
flutter build apk --release \
  --dart-define=AMAP_ANDROID_KEY="$AMAP_ANDROID_KEY" \
  --dart-define=AMAP_IOS_KEY="$AMAP_IOS_KEY"
```

> 代码位置：`lib/core/config/build_config.dart:31-35`、`lib/core/map/amap/amap_bootstrap.dart:48-63`。
> Key 通过运行时 `AMapInitializer.init` 传入，不需要写进 `AndroidManifest.xml` 或 `Info.plist`。

### 2.5 验证

- 安装 release 包，进入地图页；
- 不出现「缺少地图 Key」占位；
- 地图正常加载、可缩放；
- 断网后不崩溃；
- 隐私开关关闭时地图不加载。

---

## 3. 极光 JPush（必须）

### 3.1 申请地址

- 官网：<https://www.jpush.cn/>
- 控制台：<https://www.jpush.cn/common/apps>
- 文档：<https://docs.jpush.cn/>

### 3.2 操作步骤

1. 注册极光账号，完成实名/企业认证。
2. 创建应用：
   - 应用名称：`TrackerOne`
   - Android 包名：`com.trackerone.app`
   - iOS Bundle ID：`com.trackerone.app`
3. 记录：
   - `JPUSH_APP_KEY`（客户端可公开）
   - `JPUSH_MASTER_SECRET`（**只能放服务端/CI，绝不能进 App 或 git**）
4. iOS 配置：
   - 在极光后台 → 应用设置 → iOS → 上传 **APNs Auth Key (.p8)**；
   - 填写 Key ID、Team ID；
   - 区分开发/生产环境。
5. Android 配置：
   - 在极光后台绑定包名与签名；
   - 逐个开通厂商通道（见第 4 节）。

> **当前进度（2026-11-13）**
>
> - AppKey：`2e6135fffb1db1d409ab1d62` 已写入 Dart 默认值与
>   `android/app/build.gradle.kts` 的 `JPUSH_APPKEY` 占位符；
> - `PUSH_PROVIDER` 默认值已改为 `jpush`，release 构建自动启用；
> - 厂商通道与 APNs 仍未配置，锁屏到达率需在配置后实测。

### 3.3 项目注入（注意 Android 有两处）

Dart 层（AppKey 已内置默认值，以下仅用于覆盖）：

```bash
--dart-define=PUSH_PROVIDER=jpush
--dart-define=JPUSH_APP_KEY="$JPUSH_APP_KEY"
--dart-define=JPUSH_CHANNEL="developer-default"
```

Android 原生清单占位符（`android/app/build.gradle.kts:42-46`）已内置同一 AppKey：

```properties
# android/gradle.properties（AppKey 可公开，但仍建议 CI 注入）
jpush.appKey=你的AppKey
jpush.channel=developer-default
```

或构建时：

```bash
ORG_GRADLE_PROJECT_jpush.appKey="$JPUSH_APP_KEY" \
flutter build apk --release ...
```

> 只配置 dart-define 不够：Android 的 JPush SDK 还需要 manifest 占位符 `JPUSH_APPKEY`，否则原生初始化失败。

### 3.4 验证

1. 登录后进入「设置 → 诊断」；
2. 推送卡片应显示 `jpush`、alias `u{userId}@{serverId}`、已注册；
3. 用极光控制台发一条通知：
   - 前台：应用内收到；
   - 后台：系统通知；
   - 锁屏：厂商通道可达；
   - 冷启动：点击直达事件详情。

---

## 4. 厂商推送通道（强烈建议，企业主体）

> 极光聚合只是“调用入口”，真正决定锁屏到达率的是各厂商通道。
> 个人主体通常无法全部开通，需在隐私政策和产品文案中说明「锁屏可能延迟」。

### 4.1 小米

- 开放平台：<https://dev.mi.com/platform/push>
- 控制台：<https://dev.mi.com/console/appservice/push.html>
- 需要：企业开发者认证、应用包名、应用签名（MD5/SHA1/SHA256）
- 产物：`AppSecret`
- 填写到：极光后台 → 厂商通道 → 小米

### 4.2 华为 / 荣耀

- 华为开发者联盟：<https://developer.huawei.com/consumer/cn/>
- AGC 控制台：<https://developer.huawei.com/consumer/cn/service/josp/agc/index.html>
- Push Kit：<https://developer.huawei.com/consumer/cn/hms/huawei-pushkit/>
- 荣耀开发者：<https://developer.honor.com/cn/>
- 需要：企业认证、创建项目/应用、开通 Push Kit、配置签名证书指纹
- 产物：`AppId`、`AppSecret`
- 填写到：极光后台 → 厂商通道 → 华为/荣耀

### 4.3 OPPO

- 开放平台：<https://open.oppomobile.com/>
- 推送文档：<https://open.oppomobile.com/new/developmentDoc/info?id=11220>
- 需要：企业认证、包名、签名
- 产物：`AppKey`、`MasterSecret`
- 填写到：极光后台 → 厂商通道 → OPPO

### 4.4 vivo

- 开放平台：<https://dev.vivo.com.cn/>
- 推送文档：<https://dev.vivo.com.cn/documentCenter/doc/362>
- 需要：企业认证、包名、签名
- 产物：`AppId`、`AppKey`、`AppSecret`
- 填写到：极光后台 → 厂商通道 → vivo

### 4.5 统一注意事项

- 包名、签名必须与最终 release 包完全一致；
- 换 keystore = 厂商通道签名校验失败 = 推送全部失效；
- 厂商通道审核期间，极光自有通道仍可用作兜底；
- 所有 Secret 只填极光后台，不要写进 App。

---

## 5. Apple / iOS 签名（必须，若要上 iOS）

### 5.1 申请地址

- 开发者计划：<https://developer.apple.com/cn/programs/enroll/>
- 开发者账号：<https://developer.apple.com/account>
- App Store Connect：<https://appstoreconnect.apple.com/>
- 证书/标识符/描述文件：<https://developer.apple.com/account/resources/certificates/list>

### 5.2 操作步骤

1. **加入 Apple Developer Program**
   - 个人：身份证 + 人脸验证；
   - 企业：D-U-N-S 编号 + 营业执照，周期更长；
   - 费用：¥688/年（以官网为准）。
2. 记录 **Team ID**（Membership 页面，10 位字母数字）。
3. 创建 **App ID**：
   - Bundle ID：`com.<公司>.trackerone`（必须与 Xcode 一致）；
   - Capabilities 勾选：
     - Push Notifications
     - Background Modes（Location updates、Remote notifications）
4. 创建 **APNs Auth Key**：
   - Keys → “+” → Apple Push Notifications service (APNs)；
   - 下载 `.p8`（**只能下载一次**）；
   - 记录 `Key ID`；
   - 上传到极光后台 iOS 配置，填写 Team ID。
5. 签名方式二选一：
   - **自动签名（推荐）**：Xcode → Runner → Signing & Capabilities → 勾选 Automatically manage signing → 选择 Team；
   - 手动：创建 Development/Distribution 证书 + Provisioning Profile，下载安装。
6. 确认 `ios/Runner/Info.plist` 已包含：
   - `NSLocationWhenInUseUsageDescription`
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `NSMotionUsageDescription`
   - `UIBackgroundModes` → `location`、`remote-notification`
7. 复制签名模板：

```bash
cp ios/ExportOptions.plist.example ios/ExportOptions.plist
```

填入：

```xml
<key>teamID</key>
<string>你的10位TeamID</string>
```

8. 打包：

```bash
flutter build ipa --release \
  --dart-define=FLAVOR=prod \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_IOS_KEY="$AMAP_IOS_KEY" \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY="$JPUSH_APP_KEY"
```

产物：`build/ios/ipa/*.ipa`。

9. 上传 App Store Connect：

```bash
xcrun altool --upload-app --type ios \
  -f build/ios/ipa/*.ipa \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

或在 Xcode → Organizer → Distribute App。

### 5.3 免费 Apple ID 的限制

- 不能使用 Push Notifications；
- 证书 7 天过期；
- 不能上架 App Store；
- 仅适合真机调试。

### 5.4 当前仓库状态

- 无 `DEVELOPMENT_TEAM`；
- 无签名证书/描述文件；
- 已生成 `dist/TrackerOne-0.4.0-unsigned.ipa`，需重签后才能安装。

---

## 6. Firebase（仅海外 / 可选）

> 中国大陆包不使用 Firebase，且当前项目**未应用 `google-services` Gradle 插件**。
> 如果不做海外版，可以跳过本节。

### 6.1 申请地址

- Firebase 控制台：<https://console.firebase.google.com/>
- Google Play 控制台：<https://play.google.com/console>

### 6.2 操作步骤

1. 创建 Firebase 项目；
2. 添加 Android 应用：
   - 包名：`com.<公司>.trackerone`
   - SHA1：release keystore
   - 下载 `google-services.json` → `android/app/`
3. 添加 iOS 应用：
   - Bundle ID：`com.<公司>.trackerone`
   - 下载 `GoogleService-Info.plist` → `ios/Runner/`
4. 开通 Cloud Messaging、Crashlytics；
5. **补 Gradle 插件**（当前缺失）：
   - `android/settings.gradle.kts` 增加 `com.google.gms.google-services`；
   - `android/app/build.gradle.kts` 应用插件；
   - 否则 `Firebase.initializeApp()` 会失败并降级为 noop。
6. 构建：

```bash
--dart-define=PUSH_PROVIDER=fcm
--dart-define=CRASH_REPORTER=firebase
```

> 国内包请保持 `PUSH_PROVIDER=none/jpush`、`CRASH_REPORTER=none`，并拆分依赖，避免 Firebase 进入 CN 包。

---

## 7. Android 签名（必须）

### 7.1 生成上传密钥（只做一次）

```bash
keytool -genkeypair -v \
  -keystore android/app/upload-keystore.jks \
  -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
```

建议填写真实公司/组织信息，并设置强密码。

> **本仓库已生成（2026-11-06）**
>
> - 文件：`android/app/upload-keystore.jks`
> - alias：`upload`
> - 算法：RSA 2048，有效期 10000 天
> - 密码：已写入 `android/key.properties`（随机强密码，已 gitignore）
> - SHA1：`0B:21:56:4F:7E:F3:91:9E:60:35:68:1D:84:88:D9:FD:D6:AB:0E:E9`
> - SHA256：`CC:80:B1:9C:C9:15:4E:D2:E8:DB:87:BD:04:56:C3:35:9F:5E:17:2D:20:17:D2:ED:1E:A7:5E:C6:61:73:B6:B8`
> - MD5：`35:B1:06:C8:63:D6:80:3E:3D:12:EF:B2:73:20:49:86`
>
> **请立即把 `.jks` 与 `key.properties` 离线备份到两个安全位置。**
> 丢失密钥将无法覆盖升级已发布应用。高德 Android Key 使用上面的 SHA1。

### 7.2 配置

```bash
cp android/key.properties.example android/key.properties
```

```properties
storePassword=你的Store密码
keyPassword=你的Key密码
keyAlias=upload
storeFile=upload-keystore.jks
```

> `android/key.properties` 与 `*.jks` 已在 `.gitignore` 中，确认不要提交。

### 7.3 备份（非常重要）

- keystore 文件至少备份 2 个离线位置；
- 密码存入团队密码库（1Password/Bitwarden）；
- 丢失 keystore = 无法覆盖升级已发布应用。

### 7.4 Google Play（如出海）

- 使用 Play App Signing；
- 上传 `.aab`，不要上传 APK；
- 上传密钥与 Play 托管密钥分开保管。

### 7.5 构建与校验

```bash
flutter build appbundle --release \
  --dart-define=FLAVOR=prod \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY="$AMAP_ANDROID_KEY" \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY="$JPUSH_APP_KEY"

apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

> 当前 `android/app/build.gradle.kts:68-74` 在缺少 `key.properties` 时会回退 debug 签名。
> **正式发布前必须改成“缺失即失败”**，否则会误传 debug 包。

---

## 8. 服务端与推送网关

| 项 | 说明 | 申请/配置 |
|---|---|---|
| 服务器 | 境内云主机，部署 Traccar 6.x | 阿里云/腾讯云/华为云 |
| 域名 | `track.example.com` | 云厂商域名服务 |
| HTTPS 证书 | 免费 Let's Encrypt 或云厂商证书 | 自动续期 |
| 域名 ICP 备案 | 境内服务器必须 | 云厂商备案系统 |
| Traccar Webhook 补丁 | `server/traccar-plugin/.../NotificatorWebhook.java` | 按 `server/README.md` 打补丁 |
| 推送网关 | 接收 Traccar webhook → 调极光 REST | 自研，2–5 人日 |
| 网关 Secret | HMAC / Bearer Token | 随机 32 字节，仅服务端 |
| 极光 Master Secret | 调极光 REST | **仅服务端** |

> `PUSH_GATEWAY_URL` 在当前 App 代码中**只是预留常量，未被使用**（`lib/core/config/build_config.dart:52-55`）。
> 客户端通过极光 SDK 注册 alias，网关通过极光 REST 推送，不需要 App 直连网关。
> 不要误以为配置了该变量就完成联调。

### 8.1 建议的服务器检查

```bash
curl -I https://track.example.com/api/server
curl -I https://push.example.com/health
```

- 必须 HTTPS；
- 证书链完整；
- 不支持明文 HTTP（当前 App 允许输入 `http://`，但平台会拦截，见审计 P0-1）。

---

## 9. 合规与备案材料

### 9.1 APP 备案（硬门槛）

- 官方入口：<https://beian.miit.gov.cn/>
- 实际办理：通过**云服务商备案系统**或应用商店代备案
  - 阿里云：<https://beian.aliyun.com/>
  - 腾讯云：<https://console.cloud.tencent.com/beian>
  - 华为云：<https://www.huaweicloud.com/product/beian.html>
- 需要材料：
  - 主体证件（营业执照/身份证）；
  - 负责人身份与联系方式；
  - App 名称、包名、Bundle ID；
  - 域名与服务器 IP；
  - 隐私政策 URL；
  - 承诺书。
- 产物：APP 备案号，例如 `京ICP备xxxxxxxx号-1A`。
- **必须在 App「关于」页展示**（当前代码尚未接入，需要新增字段）。

### 9.2 域名 ICP 备案

- 境内服务器必须先完成 ICP 备案；
- 域名实名认证；
- 周期 1–3 周；
- 备案号展示在官网/隐私政策页。

### 9.3 软件著作权

- 中国版权保护中心：<https://www.ccopyright.com.cn/>
- 登记系统：<https://register.ccopyright.com.cn/>
- 周期：30–60 自然日（可加急）；
- 国内多数商店要求，建议第 1 周就提交。

### 9.4 隐私政策与 SDK 清单

必须覆盖：

- 收集的信息：位置（含后台）、设备型号、系统版本、推送标识、崩溃日志；
- 第三方 SDK：
  - 高德地图（定位/地图）
  - 极光推送 + 小米/华为/荣耀/OPPO/vivo 厂商通道
  - Firebase（**仅海外版**）
  - Flutter 插件（按实际清单）
- 数据用途、保存期限、共享方、跨境情况；
- 用户权利：查询、更正、删除、撤回同意、注销账号；
- 联系方式与响应时限；
- 儿童/未成年人条款；
- 地图审图号；
- APP 备案号。

### 9.5 地图审图号

- 从高德开放平台获取；
- 在「关于」页展示；
- 当前 `Brand` 无该字段，需要新增。

### 9.6 账号注销

- 商店会实际测试；
- 需要服务端提供删除/匿名化接口；
- App 内入口 + 二次确认 + 结果反馈；
- 当前项目**未实现**（审计 P0-4）。

---

## 10. 应用商店账号

| 商店 | 地址 | 备注 |
|---|---|---|
| 华为应用市场 | <https://developer.huawei.com/consumer/cn/> | 审核最严，需备案号/软著 |
| 小米应用商店 | <https://dev.mi.com/> | 对后台定位敏感 |
| OPPO 软件商店 | <https://open.oppomobile.com/> | 自动化隐私检测 |
| vivo 应用商店 | <https://dev.vivo.com.cn/> | 需测试账号 |
| 应用宝 | <https://open.qq.com/> | 需软著 |
| 荣耀应用市场 | <https://developer.honor.com/cn/> | 类似华为 |
| App Store | <https://appstoreconnect.apple.com/> | 需 Apple Developer |
| Google Play | <https://play.google.com/console> | 仅海外 |

商店通用材料：

- 应用图标、截图、描述、关键词；
- 隐私政策 URL；
- 测试账号 + 测试服务器；
- 后台定位录屏（开启 → 锁屏 → 服务端收到位置）；
- 备案号、软著；
- 权限用途说明；
- 账号注销路径说明。

---

## 11. 环境变量模板

建议放在本地 `.env.local`（不要提交）或 CI Secret：

```bash
# 品牌 / 包名（先定死）
export APP_ID="com.yourcompany.trackerone"
export IOS_BUNDLE_ID="com.yourcompany.trackerone"

# 高德
export AMAP_ANDROID_KEY=""
export AMAP_IOS_KEY=""
export AMAP_SECURITY_CODE=""   # 如控制台启用安全码

# 极光
export JPUSH_APP_KEY=""
export JPUSH_MASTER_SECRET=""  # 仅服务端，绝不下发客户端
export JPUSH_CHANNEL="developer-default"

# 推送网关（服务端）
export PUSH_GATEWAY_URL="https://push.yourcompany.com"
export PUSH_WEBHOOK_SECRET=""

# 服务端
export TRACCAR_API_URL="https://track.yourcompany.com"
export TRACCAR_REPORT_URL="https://track.yourcompany.com:5055"

# iOS
export APPLE_TEAM_ID=""
export ASC_KEY_ID=""
export ASC_ISSUER_ID=""

# Android 签名
export ANDROID_STORE_PASSWORD=""
export ANDROID_KEY_PASSWORD=""
export ANDROID_KEY_ALIAS="upload"
```

### 11.1 国内生产构建命令

```bash
flutter build appbundle --release \
  --dart-define=FLAVOR=prod \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY="$AMAP_ANDROID_KEY" \
  --dart-define=AMAP_IOS_KEY="$AMAP_IOS_KEY" \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY="$JPUSH_APP_KEY" \
  --dart-define=JPUSH_CHANNEL="$JPUSH_CHANNEL" \
  --dart-define=CRASH_REPORTER=none
```

### 11.2 iOS 生产构建命令

```bash
flutter build ipa --release \
  --dart-define=FLAVOR=prod \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY="$AMAP_ANDROID_KEY" \
  --dart-define=AMAP_IOS_KEY="$AMAP_IOS_KEY" \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY="$JPUSH_APP_KEY" \
  --dart-define=CRASH_REPORTER=none
```

### 11.3 无 Key 降级构建（当前测试包）

```bash
flutter build apk --release \
  --dart-define=MAP_PROVIDER=none \
  --dart-define=PUSH_PROVIDER=none \
  --dart-define=CRASH_REPORTER=none
```

---

## 12. 回执表（申请到后填写）

| 名称 | 值 | 获取位置 | 写入位置 | 完成 |
|---|---|---|---|---|
| 正式包名 | `com.trackerone.app` | 已定稿 | `android/app/build.gradle.kts` | ✅ |
| iOS Bundle ID | `com.trackerone.app` | 已定稿 | Xcode / App ID | ✅ |
| 高德 Android Key | `3c5cfa8ef73973fb579289710cc2370f` | 高德控制台 | `build_config.dart` 默认值 | ✅ |
| 高德 iOS Key |  | 高德控制台 | `--dart-define` | ☐ |
| 地图审图号 |  | 高德控制台 | 关于页 | ☐ |
| 极光 AppKey | `2e6135fffb1db1d409ab1d62` | 极光控制台 | `build_config.dart` + Gradle 占位符 | ✅ |
| 极光 Master Secret |  | 极光控制台 | 服务端 Secret | ☐ |
| 小米 AppSecret |  | 小米控制台 | 极光后台 | ☐ |
| 华为 AppId/Secret |  | AGC | 极光后台 | ☐ |
| 荣耀 AppId/Secret |  | 荣耀控制台 | 极光后台 | ☐ |
| OPPO AppKey/Secret |  | OPPO 控制台 | 极光后台 | ☐ |
| vivo AppId/Key/Secret |  | vivo 控制台 | 极光后台 | ☐ |
| Android keystore | `android/app/upload-keystore.jks`（alias `upload`） | 已生成 | `android/app/` | ✅ |
| keystore 密码 | 已随机生成 | `android/key.properties` | 密码库 + 离线备份 | 🟡 待备份 |
| keystore SHA1 | `0B:21:56:4F:7E:F3:91:9E:60:35:68:1D:84:88:D9:FD:D6:AB:0E:E9` | `keytool -list -v` | 高德 Android Key | ✅ |
| Apple Team ID |  | Apple Developer | Xcode / ExportOptions | ☐ |
| APNs Key ID |  | Apple Developer | 极光后台 | ☐ |
| APNs .p8 |  | Apple Developer | 极光后台 | ☐ |
| 域名 |  | 云厂商 | 服务端/隐私政策 | ☐ |
| ICP 备案号 |  | 云厂商 | 关于页/官网 | ☐ |
| APP 备案号 |  | 云厂商/管局 | 关于页 | ☐ |
| 软著证书号 |  | 版权中心 | 商店后台 | ☐ |
| 推送网关 Secret |  | 自生成 | 网关/Traccar | ☐ |

---

## 13. 建议申请顺序（关键路径）

```text
第 0 天
  ├─ 定包名/Bundle ID/域名/主体
  ├─ 注册高德、极光账号
  └─ 提交软著（周期最长）

第 1 天
  ├─ 申请高德 Android/iOS Key（需 release SHA1，先生成 keystore）
  ├─ 生成 Android keystore 并备份
  ├─ 创建极光应用，拿 AppKey
  └─ 启动域名 ICP 备案

第 1 周
  ├─ 企业认证：小米/华为/荣耀/OPPO/vivo
  ├─ 加入 Apple Developer Program
  ├─ 创建 App ID / APNs Key
  ├─ 部署 Traccar + 推送网关
  └─ 编写隐私政策与 SDK 清单

第 2 周
  ├─ 厂商通道逐个审批
  ├─ APP 备案（需域名/服务器/隐私政策）
  └─ 真机联调：地图、推送、后台上报

第 3–6 周
  ├─ 软著下证
  ├─ 备案下号
  ├─ 商店素材与测试账号
  └─ 提审
```

---

## 14. 安全规则

**可以进客户端（仍建议 CI 注入）：**

- 高德 Android/iOS Key
- 极光 AppKey
- 渠道号

**绝对不能进客户端 / git / 聊天记录：**

- 极光 Master Secret
- 厂商 AppSecret / MasterSecret
- 推送网关 HMAC Secret
- Android keystore 密码
- Apple `.p8` 私钥
- App Store Connect API Key
- 服务端数据库密码、Traccar admin 密码

**必须备份：**

- Android keystore（丢失无法升级）
- Apple APNs `.p8`（只能下载一次）
- 推送网关 Secret
- 所有账号的恢复码/二次验证

---

## 15. 当前项目仍缺的代码改动（与申请配套）

| 改动 | 位置 | 说明 |
|---|---|---|
| 替换包名/Bundle ID | `android/app/build.gradle.kts`、Xcode | 申请 Key 前必须定稿 |
| 移除 debug 签名回退 | `android/app/build.gradle.kts:68-74` | 缺签名应直接失败 |
| 关于页展示备案号/审图号 | 设置/关于页 | 合规要求 |
| 账号注销入口 | 设置页 + 服务端 | 商店必测 |
| 推送 alias 解绑 | `PushGateway` / `SessionController` | 换账号防串消息 |
| 彻底清除本地数据 | 设置页 + drift | 隐私合规 |
| 条件编译/拆分 Firebase | Gradle flavor | 国内包不应含 Firebase/GMS |
| 修正 `PUSH_GATEWAY_URL` 说明 | `build_config.dart` | 当前未使用，避免误解 |
| iOS 隐私清单 | `ios/Runner/PrivacyInfo.xcprivacy` | App Store 要求 |
| Android `allowBackup=false` | `AndroidManifest.xml` | 防止轨迹进云备份 |

---

## 16. 最快可跑通路径（今天就能做）

如果只想先让地图和推送在真机上跑起来：

1. ~~生成 release keystore~~ **已完成**（见 7.1，SHA1 已记录）；
2. 高德控制台创建 Android Key（包名 `com.trackerone.app` + 上面的 SHA1）；
3. 极光控制台创建应用（同包名 `com.trackerone.app`），拿 AppKey；
4. 构建：
   ```bash
   flutter build apk --release \
     --dart-define=MAP_PROVIDER=amap \
     --dart-define=AMAP_ANDROID_KEY="..." \
     --dart-define=PUSH_PROVIDER=jpush \
     --dart-define=JPUSH_APP_KEY="..."
   ```
5. 安装后进「设置 → 诊断」确认推送 alias；进地图确认底图。

> 注意：包名已定为 `com.trackerone.app`，keystore 已生成；高德与极光 Key 仍需按该包名申请。

---

## 17. 相关文档

- `docs/09-china-launch.md`：地图/推送/备案决策
- `docs/10-setup-runbook.md`：本地环境与 SDK 接入
- `docs/12-push-integration.md`：推送链路与网关联调
- `docs/13-release-checklist.md`：提审前检查
- `docs/14-roadmap-gap-analysis.md`：差距与 P0/P1/P2
- `server/README.md`：Traccar Webhook 补丁
