# 05 · 后台定位与可靠性

后台定位是本项目最容易"看起来能用、实际不可靠"的部分。本文定义选型、配置、权限、平台差异、诊断与验收标准。

## 1. 需求

| 编号 | 需求 |
|---|---|
| T1 | App 在后台、锁屏时持续采集并上报 |
| T2 | 断网时本地排队，恢复后按序补传，不重复 |
| T3 | 进程被系统回收、设备重启后可恢复 |
| T4 | 静止时暂停 GPS，控制功耗 |
| T5 | 用户可随时看到"是否在上报、最后成功时间、队列量" |
| T6 | 权限缺失/系统限制可被诊断并给出修复路径 |
| T7 | iOS 被强杀、Android 被厂商清理时行为可预期 |
| T8 | 上报内容不包含用户未同意的数据 |

## 2. 方案对比

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| **A. `traccar_client_sdk`** | Apache-2.0；KMP 原生实现；SQLite 队列；停驶检测；开机恢复；与 Traccar 协议一致；Client 已验证 | 可定制性受限于 SDK API；调试黑盒 | **默认** |
| B. 自研（geolocator + flutter_foreground_task + drift） | 完全可控；可深度定制 | 可靠性工作量大；iOS 后台限制复杂；预计 +4–6 周 | 备选 |
| C. 商业库（如 Transistorsoft） | 成熟；文档完善 | 收费、按 App 授权、体积大 | 不优先 |
| D. 复用旧 Client 代码 | 迁移快 | 旧代码结构简单、无诊断/预设/多服务器 | 仅参考 |

**决策：A + 接口隔离。** 业务层依赖 `TrackingEngine`，未来可替换为 B 或 C。

> 许可提示：旧 Client 的 Android Manifest / iOS Info.plist 中存在 Transistorsoft 的 license 元数据，但当前 `pubspec.yaml` 只依赖 Apache-2.0 的 `traccar_client_sdk`。新项目**不要盲目复制**这段元数据；发布前向 SDK 维护方确认是否需要额外授权。

## 3. 引擎接口

```dart
class TrackingConfig {
  final String serverUrl;
  final String deviceId;
  final Map<String, String> headers;
  final AccuracyLevel accuracy;
  final int intervalSeconds;
  final int distanceMeters;
  final int angleDegrees;
  final int heartbeatIntervalSeconds;
  final bool buffer;
  final bool stopDetection;
  final bool wakeLock;
  final bool preferPlatformProviders;
  final NotificationConfig notification;
}

abstract interface class TrackingEngine {
  Future<void> init(TrackingConfig config);
  Future<void> start();
  Future<void> stop();
  Future<bool> requestPosition({String? alarm});
  Future<bool> isTracking();
  Future<void> applyConfig(TrackingConfig config);
  Stream<TrackingEvent> get events;   // started/stopped/uploaded/failed/queue
  Future<List<TrackingLogEntry>> getLogs();
  Future<void> clearLogs();
}
```

**SDK 适配器职责**

- 把 `TrackingConfig` 映射为 SDK 的 `Config` / `LocationConfig`。
- 把 `PlatformException` 翻译为 `PermissionFailure` / `TrackingFailure`。
- 把 SDK 日志转为统一 `TrackingLogEntry`。
- 启动前做权限预检与 UI 状态同步。
- 不上报任何 SDK 未提供的数据。

## 4. 配置与预设

### 4.1 字段

| 字段 | SDK 字段 | 默认 | 影响 |
|---|---|---|---|
| accuracy | `LocationConfig.accuracy` | medium | 精度/功耗 |
| intervalSeconds | `intervalSeconds` | 300 | 心跳间隔 |
| distanceMeters | `distanceMeters` | 75 | 位移触发 |
| angleDegrees | `angleDegrees` | 0 | 转向触发 |
| heartbeatIntervalSeconds | `heartbeatIntervalSeconds` | 0 | iOS 后台唤醒 |
| buffer | `buffer` | true | 离线队列 |
| stopDetection | `stopDetection` | true | 静止暂停 |
| wakeLock | `wakeLock` | false | Android 唤醒锁 |
| preferPlatformProviders | `preferPlatformProviders` | false | 禁用 Fused |

### 4.2 预设

| 预设 | 精度 | 间隔 | 距离 | 角度 | 停止检测 | 适用 |
|---|---|---|---|---|---|---|
| 步行 | high | 60s | 20m | 15° | 开 | 通勤/运动 |
| 驾车 | high | 30s | 50m | 10° | 开 | 车辆 |
| 资产 | medium | 600s | 200m | 0 | 开 | 长期追踪 |
| 高频 | highest | 10s | 0 | 0 | 关 | 演示/应急 |
| 省电 | low | 1800s | 500m | 0 | 开 | 低电量 |

用户选择预设后仍可逐项微调，微调后标记为"自定义"。

### 4.3 生效时机

- 运行中修改：调用 `applyConfig`，无需重启。
- 切换服务器/设备 ID：先 `stop()`，再 `init()` + `start()`。
- 修改后 3 秒内 UI 显示新配置已应用。

## 5. 权限

### 5.1 矩阵

| 权限 | Android | iOS | 何时申请 |
|---|---|---|---|
| 网络 | 自动 | 自动 | — |
| 通知 | `POST_NOTIFICATIONS` (13+) | 通知授权 | 引导第 1 步 |
| 前台定位 | `ACCESS_FINE_LOCATION` | When In Use | 引导第 2 步 |
| 后台定位 | `ACCESS_BACKGROUND_LOCATION` | Always | 用户开启上报时 |
| 运动识别 | `ACTIVITY_RECOGNITION` | Motion & Fitness | 引导第 3 步 |
| 前台服务 | `FOREGROUND_SERVICE_LOCATION` | — | 开始跟踪时 |
| 相机 | `CAMERA` | Camera | 扫码时 |
| 生物识别 | `USE_BIOMETRIC` | Face ID | 开启锁时 |

### 5.2 申请顺序（关键）

```
通知 → 前台定位 → 用户主动点"开始上报" → 后台定位 → 运动识别
```

不要首次启动就申请"始终允许定位"，否则：

- Android 12+ 会被引导到设置页，转化率低；
- iOS 容易被用户拒绝；
- 商店审核会质疑权限时机。

### 5.3 永久拒绝

- 检测 `PermissionStatus.permanentlyDenied`。
- 展示图文步骤 + "打开设置"（`openAppSettings()`）。
- 回到应用后自动重新检查并刷新状态。
- 不用弹窗反复骚扰。

## 6. 平台差异

### 6.1 Android

| 机制 | 行为 |
|---|---|
| 前台服务（location 类型） | 锁屏/后台继续运行；必须有常驻通知 |
| Boot Receiver | 重启后恢复跟踪（SDK 内置） |
| 电池优化白名单 | 未加入时可能被 Doze 限制 |
| 厂商 ROM | 可能杀进程，需要单独引导 |
| 强制停止 | 系统禁止重启，直到用户再次打开 |
| 应用更新 | SDK 声明可恢复 |

**通知渠道**

- 渠道名："位置跟踪"
- 重要性：低（无声、不可滑除）
- 文案可配置："正在上报位置到 <服务器>"
- 提供"停止"动作（PendingIntent → 广播/服务）

**Android 14+**：前台服务类型必须声明 `location`；启动时检查 `FOREGROUND_SERVICE_LOCATION`。

### 6.2 iOS

| 机制 | 行为 |
|---|---|
| Always 定位 | 锁屏/后台继续 |
| Significant Location Change | 可在被系统终止后重新拉起 |
| Region Monitoring | 离开静止区域时唤醒 |
| BGTask (`fetch`) | 心跳唤醒，系统自行调度 |
| 强杀（上滑） | 停止，直到用户重新打开 |
| 重启 | 需要用户打开一次 |
| 低电量模式 | 更新频率下降 |

**Info.plist 必填**

```xml
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>用于在后台持续上报位置，您可以随时停止。</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>用于在地图上显示您的位置。</string>
<key>NSMotionUsageDescription</key>
<string>用于判断是否静止，以节省电量。</string>
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

> `heartbeat` 标识符由 SDK 约定；若启用 `heartbeatIntervalSeconds`，必须原样注册。发布前用真机验证后台唤醒。

**AppDelegate**：SDK 文档要求在启动路径重建 tracker（`sharedTracker()`），以便系统后台唤醒时恢复配置。适配器需在 `main()` 尽早 `init`。

### 6.3 国产 ROM 引导

| 厂商 | 路径（可能随版本变化） |
|---|---|
| 小米 / Redmi | 设置 → 应用 → 权限 → 自启动；省电策略 → 无限制；锁定后台 |
| 华为 / 荣耀 | 应用启动管理 → 手动管理（自启动/关联启动/后台活动）；电池优化 → 不允许 |
| OPPO / realme | 电池 → 应用速冻/耗电保护 → 允许后台运行；自启动 |
| vivo / iQOO | 电池 → 后台高耗电 → 允许；自启动 |
| 三星 | 电池 → 后台使用限制 → 从"休眠应用"移除 |
| 一加 / 魅族 | 电池优化 → 不优化；自启动 |

**产品策略**

- 检测到厂商后展示对应图文，不展示通用长文。
- 只在"跟踪已开启但 10 分钟无心跳"时提示，避免首次打扰。
- 提供"我已设置，重新检测"。

## 7. 省电策略

| 策略 | 实现 |
|---|---|
| 静止暂停 | SDK `stopDetection` |
| 距离过滤 | `distanceMeters` |
| 精度降级 | 非导航场景用 medium/low |
| 心跳合并 | 大间隔 + 心跳 |
| 后台断 WS | 进入后台 30s 后断开，前台恢复 |
| 地图瓦片缓存 | 避免重复下载 |
| 批量上传 | SDK 队列自然合并 |
| 关闭唤醒锁 | 默认关闭，仅调试开启 |

**功耗目标**：中等配置（medium / 300s / 75m）24 小时 ≤ 6%。测试方法见第 10 节。

## 8. 可靠性矩阵

| 场景 | Android 预期 | iOS 预期 | 处理 |
|---|---|---|---|
| 切后台 | 继续 | 继续 | 无需处理 |
| 锁屏 | 继续 | 继续 | 无需处理 |
| 切换网络 | 队列重试 | 队列重试 | 提示"等待网络" |
| 飞行模式 30 分钟 | 位置排队 | 位置排队 | 恢复后补传 |
| 进程被回收 | 前台服务重启 | 系统唤醒 | SDK 恢复 |
| 用户上滑强杀 | 停止 | 停止 | 诊断页说明 |
| 设备重启 | 自动恢复 | 需打开一次 | 诊断页说明 |
| 低电量模式 | 可能延迟 | 明显延迟 | 提示 |
| 厂商清理 | 可能停止 | — | 白名单引导 |
| 权限被撤销 | 停止并提示 | 停止并提示 | 实时监听 |

## 9. 诊断设计

### 9.1 指标

| 指标 | 来源 | 用途 |
|---|---|---|
| 跟踪开关 | SDK `isTracking` | 状态一致性 |
| 最后定位时间 | SDK 日志/本地记录 | 判断是否卡住 |
| 最后成功上报 | 本地记录 | 判断网络/服务端 |
| 队列数量 | SDK 日志或自维护 | 判断积压 |
| 权限状态 | permission_handler | 修复入口 |
| 电池优化 | 平台 API | 白名单引导 |
| 前台服务 | Android API | 是否存活 |
| WebSocket 状态 | SocketClient | 实时能力 |
| 服务器可达性 | 定时探测 | 区分本地/服务端问题 |
| 时钟偏差 | 服务端时间 vs 本地 | 解释时间异常 |
| 设备/ROM | device_info_plus | 厂商引导 |

### 9.2 结论引擎

```
无权限            → "缺少后台定位权限" + 去设置
有权限但无前台服务 → "系统未启动跟踪服务" + 重启跟踪
有服务但 10 分钟无定位 → "GPS 信号弱或系统限制" + 检查省电
有定位但无上报    → "网络/服务器不可达" + 测试连接
有上报但地图不更新 → "实时连接断开" + 重连
```

### 9.3 日志

- 保留 7 天 / 10MB，环形覆盖。
- 字段：时间、级别、模块、消息、可选错误码。
- **脱敏**：不记录完整 Token、密码、服务器凭据；坐标可四舍五入到 3 位。
- 导出：zip 文本，走系统分享；用户主动触发。

## 10. 验收与测试

### 10.1 实验室

| 用例 | 方法 | 通过标准 |
|---|---|---|
| 前台跟踪 | 模拟位置移动 | 每间隔收到点 |
| 后台跟踪 | 切后台 30 分钟 | 心跳连续 |
| 锁屏 | 锁屏 2 小时 | 无断档 |
| 断网恢复 | 飞行模式 30 分钟 | 恢复后补传，顺序正确 |
| 进程回收 | `adb shell am kill` | 服务恢复 |
| 强制停止 | 设置中强制停止 | 打开后恢复 |
| 重启 | 重启设备 | 自动恢复（Android） |
| 权限撤销 | 运行中撤销 | 状态变为受限 |
| 低电量 | 开启省电模式 | 有降频但不丢点 |

### 10.2 现场

- 至少 3 台真机 × 3 家 ROM。
- 24h / 72h 连续运行。
- 驾车、步行、静止三种场景。
- 记录：点数、间隔分布、耗电、崩溃、队列。

### 10.3 功耗

```
条件：满电、飞行模式关闭、Wi-Fi + 4G、屏幕熄灭
配置：medium / 300s / 75m / stopDetection on
时长：24h
指标：电池消耗 ≤ 6%，点数 ≥ 200
```

## 11. 隐私与合规

- 首次开启上报前展示：采集内容、频率、目的、接收方（服务器地址）。
- 提供"暂停上报"与"删除本地数据"。
- 后台定位权限的商店申报：说明核心功能、演示视频、隐私政策链接。
- iOS App Privacy：位置（精确）、设备 ID、崩溃数据。
- 不将位置用于广告或画像。

## 12. 中国大陆补充要求

中国大陆把「行踪轨迹」列为**敏感个人信息**，后台定位是审核重点。

| 要求 | 落地 |
|---|---|
| 单独同意 | 用户点「开始上报」时单独弹窗，列出频率、精度、上传地址、保存期限 |
| 拒绝后可用 | 拒绝后台定位仍可查看设备地图（前台定位） |
| 撤回同意 | 设置页可随时关闭上报并删除本地缓存 |
| 权限时机 | 不在首次启动申请后台定位；先通知 → 前台定位 → 用户主动开启 |
| 自启动 | 说明用途；不得用于保活无关功能 |
| 通知文案 | 常驻通知必须说明「正在向 <域名> 上报位置」 |
| 数据出境 | 不上报到境外服务器；中国大陆包不初始化 Firebase |
| 地图 | 高德底图，展示审图号，不缓存/转发瓦片 |
| 商店检测 | 用华为/小米/OPPO/vivo 隐私自检工具跑一遍 |

**合规的权限顺序：**

```
通知 → 前台定位 → 用户点「开始上报」→ 单独同意 → 后台定位 → 运动识别
```

**常见驳回原因：**

1. 启动即申请 `ACCESS_BACKGROUND_LOCATION`；
2. 隐私政策未列出高德/极光 SDK 及收集字段；
3. 拒绝权限后直接退出，无法使用其他功能；
4. 常驻通知文案与实际上报地址不一致；
5. 无法关闭上报或删除数据。

## 13. 风险

| 风险 | 影响 | 缓解 |
|---|---|---|
| 厂商杀后台 | 跟踪中断 | 白名单引导 + 诊断 + 用户教育 |
| iOS 强杀 | 不恢复 | 明确说明；建议用户不要上滑 |
| 审核质疑后台定位 | 上架延迟 | 清晰的用途说明 + 演示视频 + 最小权限 |
| SDK 行为变化 | 升级风险 | 接口隔离 + 版本锁定 + 回归清单 |
| 功耗投诉 | 差评/卸载 | 预设 + 自适应 + 透明状态 |
| 许可问题 | 法务风险 | 发布前确认 SDK/第三方库授权 |
