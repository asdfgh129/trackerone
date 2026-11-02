# Changelog

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
