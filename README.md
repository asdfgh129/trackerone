# TrackerOne

把 **Traccar Client**（本机后台上报）与 **Traccar Manager**（设备查看与管理）合二为一的 Flutter 移动应用，兼容 Traccar 6.x 服务端。

> 工作代号 **TrackerOne**，正式包名/Bundle ID 已定为 `com.trackerone.app`；品牌、默认服务器与隐私政策地址仍可通过 `lib/core/config/brand.dart` 统一替换。

## 项目状态

| 阶段 | 状态 |
|---|---|
| 产品与技术规划 | ✅ 完成（见 `docs/`） |
| 中国大陆方案（地图/推送/备案） | ✅ 已定（见 `docs/09`） |
| 工程骨架 | ✅ 已建立 |
| 核心抽象（坐标系 / 地图 / 推送） | ✅ 代码已编译验证 |
| Traccar 推送补丁 | ✅ 代码已写（`server/`） |
| Flutter 平台工程 | ✅ 已生成 `android/` + `ios/`，原生权限/后台模式已配置 |
| M1 骨架 | ✅ 服务器档案、密码/Token 登录、会话持久化、路由守卫、底部导航 |
| M2 跟踪与实时地图 | ✅ 本机上报、设备/位置 WebSocket、设备列表/详情、跟踪面板已接入 |
| M3 历史 / 事件 / 推送 | 🟡 历史与事件已完成；推送 alias、深链、远程指令、推送诊断已接线，待真机与网关联调 |
| M4 可运维 | 🟡 诊断页、权限/保活引导、35 语言、指令队列、地图聚合与性能优化已就绪；待真机性能实测与翻译校对 |
| 离线缓存 | ✅ drift 缓存设备/最新位置/事件/待发送指令，实时接口失败时自动回退 |
| 指令 | ✅ 指令面板、参数校验、危险确认、离线入队、自动重试、记录管理 |
| 发布材料 | 🟡 签名模板、ExportOptions、`tool/release_check.sh`、测试矩阵/推送/发布清单已补齐；正式签名与备案待办 |
| 构建验证 | ✅ Android debug APK、iOS 模拟器（`flutter build ios --simulator`）均通过 |

> 首发市场为**中国大陆**。当前地图按高德实施，推送按极光 + 厂商通道实施；
> 详细依据见 [docs/09-china-launch.md](docs/09-china-launch.md)。

## 为什么不是简单合并

| 维度 | Traccar Client | Traccar Manager | TrackerOne |
|---|---|---|---|
| 定位 | 本机位置上报 | 查看/管理设备 | 两者合一 |
| 界面 | 原生 5 页 | WebView 套壳 | 原生地图优先 |
| 服务器配置 | 只有上报地址 | 只有 Web 地址 | 服务器档案（API + 上报） |
| 实时性 | 无 | 依赖 Web 前端 | REST + WebSocket 原生订阅 |
| 历史轨迹 | 无 | 依赖 Web 前端 | 原生回放 + 图表 + 导出 |
| 推送 | 远程指令 | Web 事件转发 | 事件 + 指令统一路由 |
| 离线 | SDK 队列 | 无 | 本地缓存 + 队列 + 重试 |
| 权限 | 后台定位 | 前台定位 | 分阶段申请 + 健康检查 |
| 国际化 | 35 语言 | 无 | 统一 ARB，继承 35 语言 |

## 核心能力（MVP）

- **本机实时上报**：后台定位、断网缓存、开机恢复、省电策略、快捷开关、SOS。
- **多设备实时地图**：设备列表、状态、聚合、跟随、轨迹尾迹、WebSocket 实时更新。
- **历史与报表**：行程、停留、路线回放、速度/海拔曲线、GPX/KML/CSV 导出。
- **事件与推送**：围栏/告警推送、点击直达、应用内事件流、免打扰。
- **远程指令**：单次定位、开始/停止上报、恢复出厂设置（需服务端支持）。
- **多服务器**：自建/托管服务器档案、二维码导入、OIDC、Token 登录、生物识别锁。
- **可运维**：诊断页（权限、队列、最后上报、日志导出）、崩溃上报、远程配置。

## 技术栈

| 层 | 选型 |
|---|---|
| 框架 | Flutter 3.x / Dart 3.x（Android 24+，iOS 15+） |
| 状态管理 | Riverpod |
| 路由 | go_router |
| 网络 | dio + `web_socket_channel` |
| 本地存储 | drift（SQLite）/ flutter_secure_storage / shared_preferences |
| 定位引擎 | `traccar_client_sdk`（Apache-2.0，可替换） |
| 地图 | 高德 `amap_map`（中国大陆，GCJ-02）；`flutter_map` 保留海外/兜底 |
| 推送 | 极光 JPush + 厂商通道 + 自建网关；FCM 仅海外/开发 |
| 坐标 | 数据层 WGS-84，仅渲染层转 GCJ-02 |
| 可观测 | 默认 `NoopCrashReporter`；海外 Crashlytics，国内待接 Bugly |
| 后端 | 现有 Traccar Server（REST + WebSocket）+ `NotificatorWebhook` 补丁 |
| 合规 | APP 备案、域名 ICP、隐私同意流、SDK 清单、审图号 |

## 目录结构

```
trackerone/
├── docs/                     # 开发文档（先读 00、01、03、09）
├── lib/
│   ├── app/                  # App 壳、路由、主题
│   ├── core/
│   │   ├── config/           # BuildConfig / 品牌
│   │   ├── map/              # 坐标系、地图抽象、高德适配
│   │   ├── push/             # PushGateway、极光、FCM
│   │   ├── tracking/         # TrackingEngine 与 SDK 适配
│   │   └── observability/    # 崩溃上报
│   └── features/             # 按业务域划分
├── server/                   # Traccar 推送补丁 + 网关契约
├── test/                     # 单元 / Widget 测试（端到端测试待建）
├── docs/                     # PRD / 架构 / 发布与 ADR（含下行消息 docs/17）
├── tool/bootstrap.sh         # 生成 android/ios 平台工程
├── tool/verify.sh            # pub get / analyze / test
├── tool/release_check.sh     # 发布自检：ARB / 配置 / analyze / test
├── tool/translate_arb.py     # 从 en 生成 34 个语言初稿（需母语校对）
├── pubspec.yaml
└── analysis_options.yaml
```

## 快速开始

平台工程已生成，直接拉依赖并运行：

```bash
cd trackerone

# 1. 依赖与代码生成
flutter pub get
flutter gen-l10n

# 2. 编译与测试（等价于 tool/verify.sh）
flutter analyze
flutter test

# 3. 运行（未配置 Key 时可用 MAP_PROVIDER=none / PUSH_PROVIDER=none）
flutter run \
  --dart-define=MAP_PROVIDER=none \
  --dart-define=PUSH_PROVIDER=none
```

配置高德地图与极光推送时：

```bash
flutter run \
  --dart-define=API_BASE_URL=https://track.example.com \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY=$AMAP_ANDROID_KEY \
  --dart-define=AMAP_IOS_KEY=$AMAP_IOS_KEY \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY=$JPUSH_APP_KEY
```

性能压测（仅调试，不写入缓存）：

```bash
flutter run \
  --dart-define=SIMULATE_DEVICES=1000 \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY=$AMAP_ANDROID_KEY
```

发布前自检：

```bash
# ARB 35 语言完整性 + 占位符 + 签名配置 + analyze + test
tool/release_check.sh

# 只检查配置与 ARB
tool/release_check.sh --fast
```

更多文档：

- 真机测试矩阵：[docs/11-device-test-matrix.md](docs/11-device-test-matrix.md)
- 极光/网关联调：[docs/12-push-integration.md](docs/12-push-integration.md)
- 发布清单：[docs/13-release-checklist.md](docs/13-release-checklist.md)
- 开发计划差距分析：[docs/14-roadmap-gap-analysis.md](docs/14-roadmap-gap-analysis.md)
- Key/签名/资质申请：[docs/15-credentials-and-signing-checklist.md](docs/15-credentials-and-signing-checklist.md)
- 推送落地操作手册：[docs/16-push-ops-runbook.md](docs/16-push-ops-runbook.md)

原生权限、`allowNativeHeapPointerTagging=false`、iOS Background Modes、
极光厂商通道等已按 [`docs/10-setup-runbook.md`](docs/10-setup-runbook.md) 写入平台工程；
重新生成平台工程时使用 `FORCE=1 tool/bootstrap.sh`（会覆盖原生配置，慎用）。

> 未配置 Key 时用 `MAP_PROVIDER=none` / `PUSH_PROVIDER=none`，应用仍可启动，
> 只是地图显示占位、推送退化为应用内事件。

## 文档索引

| 文档 | 内容 |
|---|---|
| [00-project-charter.md](docs/00-project-charter.md) | 背景、愿景、目标、范围、成功指标 |
| [01-prd.md](docs/01-prd.md) | 功能需求、优先级、验收标准 |
| [02-ux-spec.md](docs/02-ux-spec.md) | 信息架构、页面、状态、设计规范 |
| [03-architecture.md](docs/03-architecture.md) | 分层架构、模块、数据流、时序 |
| [04-api-integration.md](docs/04-api-integration.md) | Traccar REST / WebSocket / 推送 / 上报协议 |
| [05-tracking-engine.md](docs/05-tracking-engine.md) | 后台定位方案、权限、省电、可靠性、中国合规 |
| [06-roadmap.md](docs/06-roadmap.md) | 里程碑、任务拆解、排期、DoD |
| [07-quality-release.md](docs/07-quality-release.md) | 测试、CI/CD、发布、合规 |
| [08-decisions-risks.md](docs/08-decisions-risks.md) | ADR、风险登记、待决问题 |
| [09-china-launch.md](docs/09-china-launch.md) | 中国大陆地图/推送/备案/商店落地方案 |
| [10-setup-runbook.md](docs/10-setup-runbook.md) | 环境搭建、平台工程、M0 验收手册 |
| [server/README.md](server/README.md) | Traccar webhook 补丁、推送网关契约、联调 |

## 许可证与商标

本项目的架构与接口设计参考 Apache-2.0 的 Traccar 生态项目，但不包含其品牌资源。发布前请确认：

- `Traccar` 名称与图标的使用权限；
- 高德地图的授权、配额与测绘合规（展示审图号）；
- 后台定位相关的应用商店政策、隐私政策与 APP 备案。
