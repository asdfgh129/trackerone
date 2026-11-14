# 12 · 极光推送与网关联调

> 目标：把 Traccar 事件稳定、可去重地送到锁屏设备，并支持点击深链与远程指令。
> 本文覆盖客户端、Traccar 服务端、推送网关与极光后台的接口约定。

## 1. 链路

```
Traccar 事件（围栏/告警/指令）
  → NotificatorWebhook（Traccar 服务端插件）
  → 自建推送网关（鉴权 / 去重 / 模板 / 限流 / 审计）
  → 极光 JPush REST v3（按 alias）
  → 小米 / 华为 / OPPO / vivo / 荣耀厂商通道
  → TrackerOne（JPush SDK）→ 前台消息 / 通知点击 / 冷启动
```

选择极光的原因：一次 REST 调用即可路由到多家厂商通道；厂商通道需要企业资质，
申请周期约 1–2 周，应尽早启动。

## 2. 别名（alias）约定

客户端登录并拿到 Traccar 服务端 id 后注册：

```
alias = u{userId}@{serverId}
```

- `userId`：Traccar 账号 id；
- `serverId`：`/api/server` 返回的 `id`（通常为 1）；
- 同一用户连接多个 Traccar 服务器时不会串消息；
- 退出登录或切换账号时必须解绑旧 alias（当前实现依赖 JPush 的
  `deleteAlias`，需真机验证）。

诊断页会展示当前通道、alias、注册状态、最近错误与最近一条消息，便于联调。

## 3. 客户端配置

构建参数：

```bash
flutter build apk --release \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY=$JPUSH_APP_KEY \
  --dart-define=PUSH_GATEWAY_URL=https://push.example.com \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY=$AMAP_ANDROID_KEY \
  --dart-define=AMAP_IOS_KEY=$AMAP_IOS_KEY
```

Android 原生占位（`android/app/build.gradle.kts`）：

```kotlin
manifestPlaceholders["JPUSH_PKGNAME"] = applicationId!!
manifestPlaceholders["JPUSH_APPKEY"] = (project.findProperty("jpush.appKey") as String?) ?: ""
manifestPlaceholders["JPUSH_CHANNEL"] = (project.findProperty("jpush.channel") as String?) ?: "developer-default"
```

正式构建建议用 `~/.gradle/gradle.properties` 或 CI Secret 注入，不要提交 AppKey。

iOS：

1. Xcode → Runner → Signing & Capabilities → 添加 Push Notifications；
2. 添加 Background Modes → Remote notifications；
3. 在极光后台配置 APNs 证书或 Auth Key；
4. `PUSH_PROVIDER=jpush` 时不需要 `GoogleService-Info.plist`。

## 4. 推送 payload 契约

网关 → JPush → 客户端最终需要包含：

```json
{
  "eventId": 12345,
  "command": "positionSingle",
  "title": "围栏离开",
  "body": "车辆京A12345 已离开公司围栏",
  "data": {}
}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `eventId` | 事件类必填 | 点击后跳转 `/event/:id` |
| `command` | 指令类必填 | 如 `positionSingle`，客户端触发本机立即上报 |
| `title` / `body` | 是 | 通知展示文案；建议由网关按语言模板生成 |
| `data` | 否 | 透传字段，不放大对象 |

客户端只信任服务端下发的 `eventId` 与 `command`，不根据通知文案做路由。

## 5. 网关接口（建议最小实现）

### 5.1 接收 Traccar webhook

```
POST /webhooks/traccar
Authorization: Bearer <shared-secret>
Content-Type: application/json

{ "event": { ...Traccar event... }, "device": { ... }, "position": { ... } }
```

要求：

- 校验 shared secret / mTLS，拒绝公网匿名调用；
- 按 `event.id` 幂等，重复投递不重复推送；
- 根据 `event.type` 与用户通知设置决定是否发送；
- 记录投递日志（eventId、alias、通道、厂商响应、耗时）；
- 失败重试使用指数退避，超过上限进入死信队列。

### 5.2 调用极光

```
POST https://api.jpush.cn/v3/push
Authorization: Basic base64(appKey:masterSecret)
Content-Type: application/json
```

示例：

```json
{
  "platform": "all",
  "audience": { "alias": ["u42@1"] },
  "notification": {
    "android": {
      "alert": "车辆已离开围栏",
      "title": "围栏离开",
      "extras": { "eventId": 12345 }
    },
    "ios": {
      "alert": { "title": "围栏离开", "body": "车辆已离开围栏" },
      "sound": "default",
      "extras": { "eventId": 12345 }
    }
  },
  "options": {
    "apns_production": true,
    "time_to_live": 3600,
    "third_party_channel": { "xiaomi": { "distribution": "secondary_push" } }
  }
}
```

> 厂商通道的具体字段随极光版本变化，以极光控制台文档为准；关键是
> `extras` / `data` 必须能透传到客户端。

## 6. 联调步骤

1. **服务端**：部署 Traccar + NotificatorWebhook，配置网关地址与 shared secret；
2. **网关**：用 curl 模拟 Traccar 事件，确认能调用 JPush 成功；
3. **极光后台**：确认应用、包名、AppKey、APNs 证书/Key、厂商通道状态；
4. **客户端**：安装 release 包，登录，诊断页确认 alias 已注册；
5. **前台**：网关发一条事件，确认应用内消息；
6. **后台**：切到桌面再发，确认系统通知；
7. **锁屏**：锁屏后发送，确认厂商通道可达；
8. **冷启动**：强杀应用后点击通知，确认直达事件详情；
9. **未登录**：退出登录后点击通知，确认登录后补跳转；
10. **退避**：关闭网络发送，恢复后确认重试与去重。

### 本地快速验证（不依赖 Traccar）

```bash
curl -X POST https://push.example.com/webhooks/traccar \
  -H 'Authorization: Bearer dev-secret' \
  -H 'Content-Type: application/json' \
  -d '{"event":{"id":900001,"type":"geofenceExit"},"device":{"id":1,"name":"测试车"},"position":{"deviceId":1}}'
```

## 7. 排障

| 现象 | 优先排查 |
|---|---|
| 诊断页显示“未注册” | `PUSH_PROVIDER`、AppKey、网络、`/api/server` 是否可达 |
| 前台收不到 | WebSocket 是否通；网关是否真的调用 JPush；alias 是否匹配 |
| 后台/锁屏收不到 | 厂商通道资质、AppKey、包名/签名、电池优化、自启动 |
| 点击不跳转 | `extras.eventId` 是否透传；是否被厂商通道剥离 |
| 冷启动无数据 | `takeInitialMessage` 是否在 SDK 初始化后调用；是否被点击消费两次 |
| iOS 收不到 | APNs 证书/Key 环境（开发/生产）、Push Notifications capability |
| 同一事件重复通知 | 网关幂等键是否使用 `event.id`；客户端是否会再次本地通知 |

## 8. 安全与合规

- AppKey 可公开，Master Secret 只能保存在服务端/CI Secret；
- 网关必须鉴权、限流、记录审计日志；
- 通知文案避免完整车牌/手机号等敏感信息，可按用户设置脱敏；
- 推送 SDK 必须在用户同意隐私政策后初始化（已由首启隐私同意页统一管控，
  同意前不会初始化任何第三方 SDK）；
- 第三方 SDK 清单中必须列出极光、厂商通道与地图 SDK；
- 不向境外服务器发送中国大陆用户数据；海外包使用 FCM 单独配置。

## 9. 当前状态

| 项 | 状态 |
|---|---|
| 客户端 alias 注册、点击深链、远程指令 | ✅ 代码完成 |
| 推送诊断（通道/alias/状态/错误/最近消息） | ✅ 代码完成 |
| 隐私同意后才初始化推送 SDK | ✅ 本轮完成 |
| 极光 AppKey / 厂商通道资质 | ⛔ 待申请（步骤见 [docs/16](16-push-ops-runbook.md)） |
| 推送网关部署与 Traccar webhook | 🟡 网关代码已完成（`server/push-gateway/`），待部署；Traccar 待打补丁 |
| 真机锁屏/冷启动验证 | ⛔ 待真机 |
| 退出登录解绑 alias | 🟡 代码路径存在，需真机确认 |

> 没有真实 AppKey、厂商资质与网关地址时，只能完成代码与文档层面的准备；
> 发布前必须按第 6 节完整跑通并回填结果。
