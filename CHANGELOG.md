# Changelog

## 未发布

### 发布准备

- 正式包名/Bundle ID 改为 `com.trackerone.app`（Android `namespace`/`applicationId`、iOS Bundle ID、深链 URL Name 同步）
- 生成 Android 上传密钥 `android/app/upload-keystore.jks`，新增 `android/key.properties`（已 gitignore）
- release 构建缺少 `key.properties` 时直接失败，不再回退 debug 签名
- 新增 `LocalDataCleaner`：统一清理 drift 设备/位置/事件缓存与指令队列
- “清除本地数据”、退出登录、401、删除服务器、注销账号均会清理对应本地数据
- 推送 `PushGateway` 新增 `deleteAlias()`：极光解绑 alias，FCM 取消 topic 订阅
- 新增“注销账号”入口，调用 `DELETE /api/users/{id}`；403 时提示联系管理员
- 内置高德 Android Key 与极光 AppKey（`BuildConfig` 默认值 + Gradle 占位符），
  `PUSH_PROVIDER` 默认改为 `jpush`，release 构建自动启用地图与推送
- 新增 7 个设置类 ARB key，35 语言同步
- 修复 400 参数错误被当作可重试、离线入队消耗重试次数、`sending` 状态无法恢复、
  刷新丢失 WebSocket 连接状态、通用 REST 401 未全局登出
- 移除未使用的 `firebase_analytics` 依赖，并通过 manifest 移除 `AD_ID` 等广告权限
- 新增 iOS `PrivacyInfo.xcprivacy` 并加入 Runner 资源（声明定位/账号/崩溃数据，无跟踪）
- 删除无引用的 `lib/features/home/home_screen.dart` 占位页
- 新增缓存/指令 `clearAll` 单元测试；`flutter test` 71 项通过

## 0.4.0

### 指令

- 新增设备指令面板：按 `supportedCommands` 过滤，支持单次定位、周期上报、
  断油断电、恢复油电、布防/撤防、重启、恢复出厂、消息
- 参数校验（周期 10–86400 秒、消息非空）与危险指令二次确认
- 指令先写入 drift `PendingCommands`（schema v2 + 迁移）再发送
- 网络/超时/5xx 自动重试（30 秒、最多 6 次）；401/403/参数错误不重试
- 离线入队、WebSocket 重连补发；记录支持重试、取消、清除已完成
- 新增 `test/command_queue_test.dart`、`test/device_command_test.dart`

### 权限与保活

- 新增厂商识别（小米/华为/OPPO/vivo/三星）与厂商保活指引页
- 诊断页、权限向导增加保活指南入口；支持申请电池优化豁免

### 推送

- 推送注册状态可观测：通道、alias、注册结果、最近错误、最近消息、手动重试
- 诊断页新增推送卡片；未配置时明确说明应用内 WebSocket 仍可用
- 推送注册从 `FutureProvider` 改为 `AsyncNotifier`，便于刷新与排障

### 多语言

- 新增 35 语言 ARB（en + 34），`tool/translate_arb.py` 可重新生成初稿
- 语言选择器支持 35 项、搜索、完整 locale 标签（`pt_BR` / `zh_TW`）
- `zh` 为人工文案；其余为机器翻译初稿，需母语校对（`kab` 暂为英文占位）
- 地图合规/不可用/缺少 Key、聚合提示等文案全部迁入 ARB

### 性能

- WebSocket 增量按 50ms 合并后再更新状态，降低高并发重绘
- 地图按缩放级别网格聚合；本机标记永不聚合；聚合点可展开设备列表
- 新增 `SIMULATE_DEVICES` 调试注入（500/1000 台）与聚合/模拟数据测试

### 发布材料

- Android release 签名模板与 Gradle 自动读取 `key.properties`
- iOS `ExportOptions.plist.example`
- `tool/release_check.sh`：ARB 完整性/占位符、包名、签名、analyze、test
- 新增 `docs/11` 真机测试矩阵、`docs/12` 推送联调、`docs/13` 发布清单、
  `docs/14` 计划差距分析

### 测试

- 新增指令队列、指令类型、语言映射、标记聚合、模拟数据测试
- `dart analyze` 0 issue；单元/组件测试全部通过

## 0.3.0

### 诊断与权限

- 新增诊断页：总体结论（正常 / 风险 / 阻塞）、权限逐项状态、电池优化、
  前台服务、跟踪状态、最后活动、网络类型、WebSocket、服务器版本与会话状态，
  支持复制/清空日志、跳转跟踪与权限向导
- 新增三步权限向导：通知 → 使用期间定位 → 后台定位 + Android 活动识别；
  支持“稍后再说”、永久拒绝跳系统设置、逐步状态反馈
- 开始后台上报前检查通知 / 前台定位 / 后台定位，缺失时引导进入权限向导
- 诊断结论逻辑抽成纯数据模型，新增 12 个单元测试

### 推送与深链

- 登录后自动注册推送 alias（`u{userId}@{serverId}`），serverId 来自
  `/api/server`；注册失败不影响登录
- 推送消息区分“前台到达”与“用户点击”，只有点击才自动跳转事件详情
- 未登录时点击推送会缓存 eventId，登录完成后补跳转
- 冷启动通知在推送 SDK 初始化完成后读取，避免竞态
- 远程指令（如 `positionSingle`）触发本机立即上报
- `ServerInfo` 增加服务端 id 解析

### 离线缓存

- 新增 drift 数据库（`app_database.dart`）：设备、最新位置、事件按服务器隔离，
  以 Traccar JSON payload 存储，服务端字段变化无需迁移
- 新增 `RealtimeCache`：快照落盘、WebSocket 增量 upsert、事件保留 30 天
- 实时地图/REST 失败时自动回退到本地缓存，保留设备标记并在顶部显示离线原因
- 模型补充 `toJson`；新增 `test/realtime_cache_test.dart`（内存数据库验证）

### 设置

- 新增语言切换：跟随系统 / 简体中文 / English，持久化到本地并即时生效

### 构建

- 修复 AGP 9 Kotlin DSL 下 `manifestPlaceholders` 的 `String?` 类型错误
- Kotlin 升级到 2.4.20，与 `traccar_client_sdk` 保持一致
- 统一把地图等插件的 `compileSdk` 抬到 37，解决 AAR metadata 校验失败
- Android debug APK 构建通过
- iOS 保留 SwiftPM（`traccar_client_sdk` 只有 Swift Package），高德继续走
  CocoaPods；新增 `tool/patch_amap_nanopb.sh`，用 `nmedit` 把 MAMapKit 内嵌的
  nanopb 符号改为局部，解决与 Firebase 的 `3 duplicate symbols`
- `ios/Podfile` 在 `post_install` 自动执行上述补丁；并固定
  `$FirebaseSDKVersion = '12.19.0'` 作为改走 CocoaPods 时的版本兜底
- iOS 模拟器构建通过（`flutter build ios --simulator --no-codesign`）

### 测试

- 新增 `test/diagnostics_test.dart`、`test/server_info_test.dart`、
  `test/realtime_cache_test.dart`
- 推送消息点击标记测试；共 44 个测试全部通过

## 0.2.0

### 平台工程

- 生成 `android/` 与 `ios/`（包名 `com.example.trackerone`，上架前需替换）
- Android：`compileSdk 37` / `minSdk 24` / `targetSdk 36`、Java 17、脱糖、
  定位/后台定位/通知/相机权限、`allowNativeHeapPointerTagging=false`、
  关闭 Flutter 自动深链（避免极光厂商通道白屏）
- iOS：定位/运动/相机权限说明、`UIBackgroundModes`、`BGTaskScheduler`、
  `trackerone://` URL scheme
- 重新生成平台工程仍使用 `tool/bootstrap.sh`（已存在时需 `FORCE=1`）

### 架构与状态

- 新增 `AppPreferences`（服务器档案、活跃服务器、账号缓存、本机标识、地图授权）
- 新增 `TokenStore`（flutter_secure_storage，按服务器隔离；含测试用内存实现）
- 新增 `TraccarApi`：服务器探活、密码登录 → Cookie → Token、Token 登录、
  撤销 Token、设备/位置/历史/事件/指令，统一 `AppFailure` 错误映射
- 新增 `TraccarSocketClient`：单连接、快照/增量解析、指数退避重连、401 回调
- 新增 `ServerProfilesController` / `SessionController` / `RealtimeController` /
  `TrackingController`
- 路由改为 `routerProvider` + `StatefulShellRoute`，实现服务器/登录守卫

### 界面

- 服务器档案：列表、添加/编辑、自动推导上报地址、测试连接、二维码导入、删除
- 登录：密码 / Token 两种方式、内联错误、切换服务器
- 主框架：地图 / 设备 / 告警 / 跟踪 / 设置五个 Tab
- 地图：WGS-84 → GCJ-02 渲染、设备标记、在线状态、选中设备卡片、地图隐私门
- 设备：搜索、状态/速度/最后更新、详情页、地图预览、单次定位指令
- 告警：最近 24 小时历史事件 + WebSocket 实时事件合并去重
- 跟踪：本机标识、绑定设备、开始/停止上报、单次定位、SOS、电量、跟踪日志
- 设置：账号/服务器、地图授权、诊断入口、清除本地数据、版本与合规信息
- 新增中英文 ARB 文案，接入 `flutter_localizations`

### 测试与验证

- `flutter analyze` 0 issue；`flutter test` 全部通过
- 新增 `test/server_profile_test.dart`（地址推导、反代路径、序列化、去重）
- Android debug 构建验证（见构建日志）

## 0.1.0

### 初始骨架

- 产品、架构、API、定位、排期、质量文档
- 领域模型、服务器档案、跟踪引擎抽象与 SDK 适配器

### 中国大陆首发方案

- 新增 `docs/09-china-launch.md`：地图选型、推送架构、备案、合规、商店、排期影响
- 新增 `docs/10-setup-runbook.md`：Flutter 环境验证、平台工程、原生配置、M0 验收
- 更新 `00`~`08`：高德、极光、备案、合规、中国专项需求、排期与风险
- 新增 ADR-013（推送网关）、ADR-014（合规基线）、ADR-015（包名）
- 重写 ADR-004（高德）、ADR-008（极光 + 厂商通道）；ADR-012 标注部分被替代

### 代码

- `lib/core/map/`：坐标点、WGS-84/GCJ-02/BD-09 转换、地图抽象、
  隐私同意门、高德渲染适配
- `lib/core/push/`：`PushGateway` 抽象、极光实现、FCM 实现、`PushService` 门面
- `lib/core/observability/crash_reporter.dart`：接口化，Firebase 未配置时降级为 noop
- `lib/main.dart`：不因 Firebase 缺失而阻断启动
- `lib/core/config/build_config.dart`：地图/推送/崩溃构建期开关

### 服务端

- `server/traccar-plugin/.../NotificatorWebhook.java`：Traccar 事件 webhook（HMAC 签名）
- `server/README.md`：补丁安装、配置、网关契约、极光下行、联调命令

### 测试与工具

- `test/coordinate_transform_test.dart`
- `test/push_message_test.dart`
- `tool/bootstrap.sh`：安全生成 `android/`、`ios/`
- `tool/verify.sh`：一键 `pub get` / `gen-l10n` / `analyze` / `test`

### 插件 API 核对（基于包源码，非编译验证）

- 高德：`AMapInitializer.updatePrivacyAgree` / `init`、`AMapWidget`、
  `Marker(onTap: (String id) {})`、`Polyline(width: double)`
- 极光：`setup` 为同步方法、冷启动接口为 `getLaunchAppNotification()`
- 缺少高德 Key 时显示提示卡片，不初始化 SDK
- FCM 未初始化 Firebase 时自动补初始化，失败则降级
- 修正 `push_message_test` 对原始 payload 的错误断言

### 依赖

- 新增 `amap_map`、`x_amap_base`、`jpush_flutter`
- Firebase 标注为海外/开发专用

### 未验证

- 尚未执行 `flutter pub get` / `analyze` / `test`（本机未安装 Flutter）
- `amap_map` 与 `jpush_flutter` 的精确 API 需首次拉依赖后核对
