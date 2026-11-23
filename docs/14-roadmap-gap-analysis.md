# 14 · 开发计划对齐与差距分析

> 对照对象：`docs/01-prd.md`、`docs/06-roadmap.md`、`docs/07-quality-release.md`。
> 结论时间：2026-11。状态定义：
> ✅ 代码完成且本地验证；🟡 代码完成但缺真机/凭据/测量；⛔ 未实现。

## 1. 结论摘要

| 维度 | 结论 |
|---|---|
| 工程与核心闭环 | ✅ 登录 → 跟踪 → 实时地图 → 历史/事件 → 推送/指令 → 诊断 |
| 本轮 4 项收尾 | 🟡 代码与文档完成；真机、推送凭据、性能实测仍需外部条件 |
| 35 语言 | 🟡 35 个 ARB 已生成；除 zh 外为机器翻译，需母语校对 |
| 发布材料 | ✅ 签名配置、自检脚本、测试矩阵、推送联调、发布清单已补齐 |
| 可上架状态 | ⛔ 仍缺真实包名/Key、备案与审图号、账号注销、真机验收 |

**一句话**：已达到“功能完整、可构建、可自检的发布候选代码”，但还不是
“可提交商店的发布候选版本”。

## 2. 本轮 4 项工作完成情况

### 2.1 真机权限 / 后台定位 / 厂商白名单引导

| 项 | 状态 | 证据 |
|---|---|---|
| 三步权限向导（通知 → 前台 → 后台 + 活动识别） | ✅ | `features/onboarding/presentation/permissions_screen.dart` |
| 永久拒绝跳系统设置 | ✅ | 同上 |
| 电池优化状态与申请入口 | ✅ | `diagnostics_controller.dart` / `diagnostics_screen.dart` |
| 厂商识别（小米/华为/OPPO/vivo/三星） | ✅ | `diagnostics/application/device_vendor.dart` |
| 厂商保活指引页 | ✅ | `diagnostics/presentation/battery_guide_screen.dart` |
| 诊断页 / 权限向导入口 | ✅ | 路由 `/diagnostics/battery` |
| 24h / 72h 真机后台上报 | ⛔ | 缺真机执行；矩阵见 `docs/11` |

### 2.2 极光推送与网关真机联调

| 项 | 状态 | 证据 |
|---|---|---|
| JPush/FCM/None 通道抽象 | ✅ | `core/push/*` |
| alias 注册 `u{userId}@{serverId}` | ✅ | `push_service.dart` / `push_registration_controller.dart` |
| 推送诊断（通道/alias/注册/错误/最近消息/重试） | ✅ | 诊断页“推送通知”卡片 |
| 点击深链、冷启动补跳、远程指令 | ✅ | `app/router.dart` |
| AppKey、厂商通道资质 | ⛔ | 需企业申请（1–2 周） |
| 推送网关 + Traccar webhook 部署 | ⛔ | 需后端联调；契约见 `docs/12` |
| 锁屏/冷启动真机验证 | ⛔ | 缺设备与凭据 |

### 2.3 指令发送 UI + 待确认指令重试

| 项 | 状态 | 证据 |
|---|---|---|
| 指令类型与能力过滤（`supportedCommands`） | ✅ | `domain/entities/device_command.dart` |
| 单次定位、周期上报、断油断电、布撤防、重启、恢复出厂、消息 | ✅ | `devices/presentation/device_commands.dart` |
| 参数输入与校验（间隔 10–86400 秒、消息非空） | ✅ | 同上 |
| 危险指令二次确认 | ✅ | 同上 |
| 先落库再发送（drift `PendingCommands`，schema v2） | ✅ | `core/storage/app_database.dart` / `command_queue.dart` |
| 网络/超时/5xx 自动重试，401/403/参数错误不重试 | ✅ | `commands/application/command_controller.dart` |
| 离线入队、重连补发、30 秒轮询（最多 6 次） | ✅ | 同上 |
| 指令记录、重试、取消、清除已完成 | ✅ | `CommandQueueCard` |
| 真机指令执行验证 | ⛔ | 需真实设备/服务端 |

### 2.4 35 语言 + 性能 + 发布材料

| 项 | 状态 | 证据 |
|---|---|---|
| 35 个 ARB（en + 34） | ✅ | `lib/l10n/app_*.arb`，`tool/translate_arb.py` 生成，含 `@@locale` |
| 语言选择器（35 项、搜索、RTL 语言） | ✅ | `core/localization/app_languages.dart` + 设置页 |
| 完整 locale 标签持久化（`pt_BR` / `zh_TW`） | ✅ | `locale_controller.dart` |
| 机器翻译审校 | ⛔ | 除 zh 外均需母语校对；`kab` 暂为英文占位 |
| WebSocket 50ms 批合并 | ✅ | `realtime_controller.dart` |
| 地图网格聚合 + 缩放回调 | ✅ | `core/map/marker_cluster.dart`、`map_screen.dart` |
| 500/1000 设备模拟数据 | ✅ | `core/dev/simulated_data.dart`、`SIMULATE_DEVICES` |
| 性能实测（帧率/内存/冷启动） | ⛔ | 缺中端真机与 DevTools 记录 |
| Android release 签名配置 | ✅ | `android/key.properties.example` + Gradle |
| iOS ExportOptions 模板 | ✅ | `ios/ExportOptions.plist.example` |
| 发布自检脚本 | ✅ | `tool/release_check.sh` |
| 测试矩阵 / 推送联调 / 发布清单 | ✅ | `docs/11`、`docs/12`、`docs/13` |

## 3. 与里程碑逐项对齐

| 里程碑 | 计划退出标准 | 当前 | 差距 |
|---|---|---|---|
| M0 技术验证 | SDK 24h、登录/WS、高德真机、极光后台/冷启动 | 🟡 | 代码路径齐全；缺真机与凭据 |
| M1 骨架 | 服务器档案 + 登录 + 守卫 + CI 绿 | ✅ | 无 CI 流水线文件，本地 `release_check.sh` 可替代 |
| M2 核心 | 上报 + 地图 + 详情 + 离线缓存 | ✅ | 真机后台上报未验收 |
| M3 闭环 | 历史 + 事件 + 推送直达 + 指令 | 🟡 | 历史仅列表 + 地图，缺图表/导出；推送缺联调 |
| M4 可运维 | 诊断 + 多语言 + 性能 + 安全自查 | 🟡 | 诊断/多语言代码完成；性能未实测，安全自查仅文档 |
| M5 发布 | 测试矩阵 + 商店材料 + 灰度 | ⛔ | 真机矩阵未跑；备案/软著/商店素材未准备 |

## 4. 缺失与不完善清单

### P0（上架阻断）

1. 🟡 **真实包名/Bundle ID 与 Key**：包名已统一为 `com.trackerone.app`；高德 Android Key、极光 AppKey 已内置；**iOS 高德 Key 仍待申请**。
2. ⛔ **真机后台上报 24h/72h**：无法用模拟器替代，必须实测耗电与断点。
3. 🟡 **推送端到端**：AppKey 与客户端 alias 逻辑已完成；APNs `.p8`、厂商通道、推送网关、Traccar webhook 仍未真实联通。
4. ⛔ **合规材料**：APP 备案号、ICP、地图审图号、第三方 SDK 清单、隐私政策正式版均未准备；
   首启全局隐私政策同意页已完成（`PrivacyConsentGate`，同意前不初始化地图/推送/崩溃上报 SDK，
   设置页可撤回授权），但 `Brand.privacyUrl` / `Brand.termsUrl` 仍是占位地址，需替换为正式 URL。
5. 🟡 **账号注销与数据删除**：已实现“清理 drift 缓存/指令队列/推送 alias/账号 JSON”与 `DELETE /api/users/{id}` 注销入口；普通用户若被服务端拒绝会提示联系管理员。服务端自助注销策略仍需确认。
6. 🟡 **正式签名**：Android 上传密钥已生成并接入（release 缺签名会直接失败）；iOS 仍需 Apple 开发者账号、Team ID、证书/描述文件与 APNs Key。`PrivacyInfo.xcprivacy` 已添加并纳入 Runner 资源。
7. ⛔ **应用图标/启动页/商店截图**：Android 图标与 Flutter 模板 MD5 完全一致，仍为默认资源；无 adaptive icon、无商店素材。
8. 🟡 **Android 权限最小化**：`AD_ID`、`ACCESS_ADSERVICES_AD_ID`、`ACCESS_ADSERVICES_ATTRIBUTION`、`BIND_GET_INSTALL_REFERRER_SERVICE` 已通过 manifest `tools:node="remove"` 移除；`READ_PHONE_STATE`、`QUERY_ALL_PACKAGES`、`WRITE/READ_EXTERNAL_STORAGE` 来自 JPush SDK，需真机验证推送后处理。

### P1（体验与完整性）

1. **35 语言审校**：机器翻译可能语义偏差；`kab` 为英文占位；RTL 需逐页走查。
2. **历史能力**：缺行程/停留分段、速度/海拔图表、GPX/KML/CSV 导出、10k 点抽稀。
3. **报表**：PRD 的汇总报表未实现（路线图列为 v1.1）。
4. **围栏查看/编辑**：当前只能接收事件，不能管理围栏。
5. **单位/时区/主题**：设置页仅语言与系统主题；未见公制/英制切换与手动主题。
6. **免打扰/通知偏好**：未实现按事件类型或时段静音。
7. **SOS/快捷开关/桌面小组件**：路线图 P1，未实现。
8. **OIDC/SSO、多服务器切换 UI**：服务器档案可存多个，但切换与 OIDC 未完成。
9. ✅ **错误文案国际化**（2026-11-19）：数据层 `AppFailure` 增加 `messageKey`，
   界面统一走 `core/localization/failure_localizer.dart`；二维码扫描、登录、服务器
   配置、指令队列、诊断、实时刷新等提示均已本地化。仍待补：32 种语言的 74 个新增
   key（当前回落英文，见 `docs/13` 说明）；iOS 权限弹窗文案仍为英文系统默认。
10. **无障碍**：图标按钮部分有 tooltip，但缺少系统性的语义标签与 200% 字体回归。
11. **横屏/平板**：未做专门布局。
12. **性能实测**：聚合与合流代码已就位，但未记录 500/1000 设备帧率与内存。
13. 🟡 **服务端下行消息**（2026-11-23）：App 侧消息中心与网关接口/存储均已完成
    （推送壳 + REST 收件箱 + ACK，见 `docs/17` 与 `server/README.md` 2.4）；
    仍待 Deploy 后真机联调，以及 Traccar/后台的下发入口与审计页面。

### P1 代码缺陷修复（2026-11-13）

| 问题 | 处理 | 状态 |
|---|---|---|
| HTTP 400 被当作可重试 `server` | 新增 `FailureKind.invalidRequest`，不自动重试 | ✅ |
| 离线入队也消耗 `attempts` | 新增 `CommandQueue.markQueued()`，保持 pending 且不计数 | ✅ |
| 进程中断后 `sending` 永久卡住 | 启动时 `recoverInterrupted()` 恢复为 pending | ✅ |
| `RealtimeController.refresh()` 丢失 `connected` | 以 WebSocket 实际状态回填 | ✅ |
| 通用 REST 401 无全局登出 | `TraccarApi` 增加 `onUnauthorized` 拦截器并接入会话 | ✅ |
| `home_screen.dart` 死代码 | 已删除 | ✅ |
| 事件固定 24h、历史无分页/上限 | 事件支持 24h/7d/30d 与 300 条上限；历史按天分段请求并在 2 万点后抽稀（`HistoryTrace.sampled`） | ✅ |
| 约 58 处中文硬编码 | 数据层改为 `messageKey`，界面统一本地化 | ✅ |
| 后台定位缺少单独授权 | `BackgroundLocationConsentNotifier` + 单独同意弹窗，撤回总授权时一并清除 | ✅ |
| 新增 74 个 ARB key 未翻译 32 种语言 | 回落英文，待人工翻译 | 🟡 |
| 首启缺少全局隐私政策同意页 | 新增 `PrivacyConsentGate`，同意前不初始化地图/推送/崩溃上报 | ✅ |

### P2（工程与运维）

1. 缺少 CI 配置（GitHub Actions/GitLab CI）与自动构建产物归档。
2. 缺少集成测试（`integration_test/`）与 golden 测试。
3. 崩溃上报国内仍为 Noop（Bugly 未接）。
4. 远程配置开关、证书固定、离线瓦片、二维码/MDM 批量配置未实现。
5. ✅ `lib/features/home/home_screen.dart` 占位页已删除（2026-11-13）。
6. `docs/06-roadmap.md` 的进度描述需随本轮更新。
7. `privacyUrl` 等品牌值仍为占位，需在发布前替换。

## 5. 不建议对外宣称“已完成”的内容

- “支持 35 种语言”：应表述为“35 种语言已接入，非中文为机器翻译初稿”。
- “推送已联调”：应表述为“客户端与契约已完成，待真实 AppKey/网关真机联调”。
- “性能达标”：应表述为“已实现聚合与批处理，待真机实测”。
- “可上架”：应表述为“发布候选代码完成，商店材料与真机验收未完成”。

## 6. 建议的下一阶段（2 周）

| 优先级 | 工作 | 产出 |
|---|---|---|
| P0 | 真机矩阵 A1/A2/A6/I1 跑通权限 + 24h 后台上报 | 回填 `docs/11` 表格与日志 |
| P0 | 申请极光/厂商通道，部署网关，打通一条事件 | 锁屏/冷启动录屏 + 网关日志 |
| P0 | 替换包名/Bundle ID/Key，配置正式签名 | release AAB/IPA |
| P0 | 准备隐私政策、SDK 清单、备案/审图号、账号注销 | 商店合规材料包 |
| P1 | 母语校对 34 个 ARB（至少 en/ar/ja/ru/pt_BR） | 校对记录与修正 |
| P1 | 历史图表与导出、单位/时区设置 | 功能补齐 |
| P1 | 性能实测与调优（500/1000） | 帧率/内存报告 |
| P2 | CI + integration_test + 崩溃上报 | 自动化与可观测性 |

## 7. 验收口径建议

发布评审时按下表打勾，而不是只看“代码已写”：

- [ ] 真机 24h 后台上报有数据、有耗电记录；
- [ ] 锁屏推送、冷启动深链各 1 次成功录屏；
- [ ] 35 语言 key/占位符一致，RTL 与 200% 字体走查通过；
- [ ] 500/1000 设备帧率与内存有实测值；
- [ ] `tool/release_check.sh` 全绿且使用 release 签名；
- [ ] 备案号/审图号/隐私政策/SDK 清单可在应用内看到；
- [ ] 账号注销与数据删除可实际执行。

## 8. 本轮本地验证结果（2026-11-13）

| 检查 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `dart analyze lib test` | ✅ 0 issue |
| 单元/组件测试 | `flutter test` | ✅ 78 通过（新增隐私授权 5 个用例） |
| 35 语言 ARB | `tool/release_check.sh --fast` | ✅ 35 个文件、320 个 key 与占位符一致（含 `@@locale`） |
| Android 构建 | `flutter build apk --release` | ✅ `build/app/outputs/flutter-apk/app-release.apk`（`com.trackerone.app`） |
| Android AAB | `flutter build appbundle --release` | ✅ `build/app/outputs/bundle/release/app-release.aab` |
| iOS 构建 | `flutter build ios --release --no-codesign` | ✅ 真机 arm64 产物；未签名 IPA 已生成 |
| 发布自检 | `tool/release_check.sh --fast` | ✅ 通过（iOS 签名团队仍待配置） |
| 签名配置 | Gradle `hasReleaseSigning` | ✅ 已配置正式上传密钥；缺少 `key.properties` 时 release 构建直接失败 |
| Android 权限 | `aapt2 dump permissions` | ✅ `AD_ID` / `ACCESS_ADSERVICES_*` 已移除；JPush 的 `READ_PHONE_STATE` 等仍保留 |
| iOS 隐私清单 | `Runner.app/PrivacyInfo.xcprivacy` | ✅ 已编入 Runner 资源 |

> 以上结果证明“代码可编译、可测试、可自检”，不代表真机验收通过。
> 真机、推送凭据、性能数据与正式签名仍按第 4 节 P0 清单执行。

### 2026-11-19 增量验证

| 检查 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze` | ✅ 0 issue |
| 单元/组件测试 | `flutter test` | ✅ 117 通过（新增收件箱解析/控制器 23 个、二维码解析 6 个、后台定位授权 3 个） |
| ARB | `tool/release_check.sh --fast` | ✅ 35 个文件结构一致；⚠️ 32 种语言 74 个新增 key（2368 条）未翻译，回落英文 |
| 错误文案 | 代码走查 | ✅ 网络/领域层改用 `messageKey`，界面统一 `failureMessage()` |
| Android 构建 | `flutter build apk --release --split-per-abi` | ✅ 通用包 + 3 个 ABI 包，签名 `CN=TrackerOne`（SHA256 `cc80b19c…`），versionCode 4（通用）/ 1004 / 2004 / 4004 |
| Android AAB | `flutter build appbundle --release` | ✅ `TrackerOne-0.4.0-release.aab`，无 `AD_ID` |
| iOS 构建 | `flutter build ios --release --no-codesign` | ✅ `Runner.app` 含 `PrivacyInfo.xcprivacy`，Bundle ID `com.trackerone.app` |
| 产物校验 | `shasum -a 256 dist/*` | ✅ 6 个产物已生成（未带 `PUSH_GATEWAY_URL`，仅本地验证） |
| 下行消息（App 侧） | `flutter test test/inbox_*` | ✅ 消息中心、去重、ACK 容忍、已读、未登录/无网关分支；网关接口仍待实现 |

已知构建告警：`AMapFoundation` 当前版本不含 arm64 模拟器切片，Apple Silicon +
iOS 26+ 模拟器会提示不支持 arm64。当前 Intel Mac 模拟器构建通过；换 Apple
Silicon 后地图相关调试需使用真机（或等待高德 SDK 更新）。

### 2026-11-23 增量验证（收件箱网关）

| 检查 | 命令 | 结果 |
|---|---|---|
| 网关测试 | `cd server/push-gateway && go test ./...` | ✅ 新增存储/HTTP 用例：下发、游标、ACK 幂等、越权与清空 |
| App 测试 | `flutter test` | ✅ 117 通过（游标改为会话内状态后回归通过） |
| 发布自检 | `tool/release_check.sh` | ✅ ARB / analyze / test / Go vet + test 全绿 |
| 收件箱契约 | `server/README.md` 2.4 | ✅ `GET/POST /v1/messages`、`POST .../ack`、`DELETE /v1/messages` |
