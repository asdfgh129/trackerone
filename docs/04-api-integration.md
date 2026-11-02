# 04 · 服务端对接规范

目标：与 **Traccar Server 6.x** 直接对接，v1 不修改服务端。

## 1. 地址与端口

Traccar 默认同时暴露三类入口：

| 入口 | 默认端口 | 用途 | 示例 |
|---|---|---|---|
| Web / REST / WebSocket | `8082`（HTTP）或 `443`（反代） | 登录、设备、历史、实时 | `https://track.example.com` |
| OsmAnd 位置上报 | `5055` | 手机上报位置 | `https://track.example.com:5055` |
| 其他设备协议 | `5000–5500` | 硬件设备接入 | 与 App 无关 |

**服务器档案**需要同时保存 `apiBaseUrl` 与 `reportUrl`。自动推导规则见 PRD AUTH-02。

> 反代部署时，`/api/socket` 必须支持 WebSocket Upgrade；`reportUrl` 可能需要单独暴露 5055 或映射到 `/` 的独立端口。

## 2. 认证

### 2.1 密码登录 → 会话 Token

```bash
# 1) 表单登录，服务端返回 JSESSIONID
curl -c cookies.txt -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "email=user@example.com&password=secret" \
  https://track.example.com/api/session

# 2) 用会话换取长期 Token（纯文本）
curl -b cookies.txt -X POST \
  https://track.example.com/api/session/token
# → "eyJhbGciOi..."

# 3) 用 Token 校验并获取用户
curl -H "Authorization: Bearer eyJhbGciOi..." \
  https://track.example.com/api/session
```

**客户端实现要点**

- 第 1→2 步需要 Cookie Jar（`dio_cookie_manager`）。
- Token 保存到 Secure Storage，按 `serverId` 隔离。
- 之后的 REST 全部用 `Authorization: Bearer <token>`。
- WebSocket 用查询参数：`wss://host/api/socket?token=<token>`。
- 退出登录调用 `POST /api/session/token/revoke`（form: `token`）。

### 2.2 Token 直接登录

适用于企业分发、扫码配置、自动化测试：

```
GET /api/session?token=<token>
```

成功返回 `User`，失败 401/404。

### 2.3 OIDC（P1）

```
GET /api/session/openid/auth        → 303 跳转到 IdP
GET /api/session/openid/callback    → 回调
```

移动端需要 Custom Tabs / ASWebAuthenticationSession，并把回调通过 Deep Link 交还应用。v1 先支持密码 + Token。

## 3. REST 接口清单

路径均相对于 `apiBaseUrl`。

### 3.1 会话与服务器

| 方法 | 路径 | 用途 |
|---|---|---|
| POST | `/api/session` | 表单登录 |
| POST | `/api/session/token` | 换取 Token |
| GET | `/api/session` | 校验/获取当前用户 |
| POST | `/api/session/token/revoke` | 撤销 Token |
| GET | `/api/server` | 服务器信息（无需认证） |
| GET | `/api/server/geocode` | 逆地理编码（可选） |

`GET /api/server` 可用于：

- 探活与版本展示；
- 判断是否为 Traccar（返回结构不符则提示）；
- 读取服务器名称、坐标格式、功能开关。

### 3.2 设备

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/devices` | 设备列表（支持 `all`、`userId`、`id`、`uniqueId`、`keyword`、`limit`、`offset`） |
| GET | `/api/devices/{id}` | 设备详情 |
| POST | `/api/devices` | 创建设备（需要权限） |
| PUT | `/api/devices/{id}` | 更新设备（含 attributes） |
| DELETE | `/api/devices/{id}` | 删除设备 |
| GET | `/api/devices/{id}/image` | 设备图片 |
| PUT | `/api/devices/{id}/accumulators` | 里程等累计值 |

**绑定本机流程**

```
GET /api/devices?uniqueId=<deviceId>
  ├─ 命中 → 保存 device.id
  └─ 未命中 → POST /api/devices {name, uniqueId, category:"phone"}
                ├─ 成功 → 保存
                └─ 403 → 提示联系管理员
```

### 3.3 位置与历史

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/positions` | 最新位置（无参）或时间范围位置 |
| GET | `/api/positions?deviceId=&from=&to=` | 历史轨迹（原始点） |
| GET | `/api/positions?deviceId=&id=` | 指定位置 |
| GET | `/api/positions/gpx` | 导出 GPX |
| GET | `/api/positions/kml` | 导出 KML |
| GET | `/api/positions/csv` | 导出 CSV |
| GET | `/api/reports/route` | 路线报告 |
| GET | `/api/reports/trips` | 行程报告 |
| GET | `/api/reports/summary` | 汇总报告 |
| GET | `/api/reports/events` | 历史事件 |
| GET | `/api/reports/geofences` | 围栏报告 |

**历史查询建议**

- 时间用 ISO 8601 UTC：`from=2026-11-01T00:00:00Z`。
- 按天或 6 小时分段请求，避免单次过大。
- 客户端按 `fixTime` 去重并排序。
- 超过 5000 点时抽稀渲染，但导出使用原始数据。

### 3.4 事件

**没有** `GET /api/events` 列表接口（仅有 `/api/events/{id}`）。事件来源：

1. 实时：WebSocket `{events:[...]}`
2. 历史：`GET /api/reports/events?deviceId=&from=&to=&type=%`
3. 单条：`GET /api/events/{id}`

事件本地缓存 30 天，用于列表与离线查看。

### 3.5 指令

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/commands` | 已保存指令 |
| GET | `/api/commands/types` | 支持的指令类型 |
| GET | `/api/commands/send?deviceId=` | 当前设备可用指令 |
| POST | `/api/commands/send` | 发送指令（可带 `groupId`） |

```json
{
  "deviceId": 42,
  "type": "positionSingle",
  "attributes": {}
}
```

响应：

- `200`：已发送，返回 `Command`
- `202`：已排队，返回 `QueuedCommand`
- `400`：无权限/类型不支持

### 3.6 用户（推送 Token）

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/api/users/{id}` | 获取当前用户 |
| PUT | `/api/users/{id}` | 更新用户（含 `attributes.notificationTokens`） |

> 标准用户通常可以更新自己的部分字段。若服务端限制，改由管理员维护，或使用设备级 Token 仅接收指令。

## 4. 数据模型

### 4.1 Device

```json
{
  "id": 42,
  "name": "京A·12345",
  "uniqueId": "12345678",
  "status": "online",
  "lastUpdate": "2026-11-01T08:12:30.000+00:00",
  "positionId": 987654,
  "groupId": 3,
  "phone": null,
  "model": null,
  "contact": null,
  "category": "car",
  "disabled": false,
  "attributes": {
    "notificationTokens": "...",
    "speedLimit": 80
  }
}
```

`status`：`online` / `offline` / `unknown`。

### 4.2 Position

```json
{
  "id": 987654,
  "deviceId": 42,
  "protocol": "osmand",
  "serverTime": "2026-11-01T08:12:31.000+00:00",
  "deviceTime": "2026-11-01T08:12:30.000+00:00",
  "fixTime": "2026-11-01T08:12:30.000+00:00",
  "valid": true,
  "latitude": 39.9042,
  "longitude": 116.4074,
  "altitude": 43.0,
  "speed": 17.2,
  "course": 87.0,
  "accuracy": 8.0,
  "attributes": {
    "batteryLevel": 78,
    "distance": 1234.5,
    "totalDistance": 45678.9
  }
}
```

- **坐标**：WGS-84。
- **速度**：节（knots）。
- **方位**：度（0–360）。
- `attributes` 为动态字段，渲染时做容错。

### 4.3 Event

```json
{
  "id": 555,
  "deviceId": 42,
  "geofenceId": 7,
  "type": "geofenceEnter",
  "eventTime": "2026-11-01T08:15:00.000+00:00",
  "positionId": 987700,
  "attributes": {}
}
```

常见类型：`deviceOnline`、`deviceOffline`、`geofenceEnter`、`geofenceExit`、`alarm`、`speed`、`ignitionOn`、`ignitionOff`、`maintenance`。

### 4.4 User

```json
{
  "id": 1,
  "name": "Admin",
  "email": "user@example.com",
  "administrator": false,
  "attributes": {
    "notificationTokens": "tokenA,tokenB",
    "language": "zh"
  }
}
```

## 5. WebSocket 实时协议

### 5.1 连接

```
wss://<host>/api/socket?token=<token>
```

- 必须在前台保持；后台主动断开。
- 服务端空闲超时由 `web.timeout` 配置（默认 300000ms，即 5 分钟），客户端需发送心跳或依赖底层 Ping/Pong。
- 断线重连：1s → 2s → 4s → … → 30s，±20% 抖动。

### 5.2 消息

服务端推送 JSON 对象，键为集合名：

```json
{
  "positions": [ { ... } ]
}
```

```json
{
  "devices": [ { ... } ]
}
```

```json
{
  "events": [ { ... } ]
}
```

```json
{
  "logs": [ { ... } ]
}
```

- 连接建立后立即收到 `{positions:[最新位置]}` 快照。
- 之后按用户权限推送增量。
- 客户端可发送 `{"logs": true}` 订阅日志（可选）。
- 同一消息可能包含多个键；解析时逐键处理。
- 未知键忽略。

### 5.3 客户端处理

```dart
void onMessage(dynamic raw) {
  final map = jsonDecode(raw as String) as Map<String, dynamic>;
  for (final entry in map.entries) {
    switch (entry.key) {
      case 'positions': _mergePositions(entry.value);
      case 'devices':   _mergeDevices(entry.value);
      case 'events':    _mergeEvents(entry.value);
      case 'logs':      _appendLogs(entry.value);
    }
  }
}
```

- 合并时按 id 去重，位置按 `(deviceId, fixTime)` 去重。
- 只更新变化的 marker，避免整图重绘。
- 解析异常：记录 + 丢弃该消息，不断连。

## 6. 位置上报协议（OsmAnd）

`traccar_client_sdk` 使用 Traccar 兼容的 OsmAnd HTTP 参数。

**请求**：`GET/POST <reportUrl>?...`（SDK 内部实现）

| 参数 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 设备 uniqueId |
| `lat` / `lon` | 是 | WGS-84 |
| `timestamp` | 否 | 秒或毫秒；缺省用服务端时间 |
| `speed` | 否 | **节** |
| `bearing` / `heading` | 否 | 度 |
| `altitude` | 否 | 米 |
| `accuracy` | 否 | 米 |
| `batt` | 否 | 电量百分比 |
| `charge` | 否 | 是否充电 |
| `alarm` | 否 | 告警标记（如 `sos`） |
| `valid` | 否 | 是否有效定位 |
| `notificationToken` | 否 | 仅海外 FCM 方案使用；中国大陆走极光网关，不传 |
| `cell` / `wifi` | 否 | 辅助定位 |

**服务端行为**

- `id` 必须已存在，否则 400；App 需先绑定设备。
- `notificationToken` 会写入**设备** attributes，用于远程指令（仅海外 FCM）。
- 位置入队后由服务端广播到 WebSocket。

**坐标约定**

| 场景 | 坐标系 |
|---|---|
| OsmAnd 上报 | WGS-84 |
| Traccar 存储与 REST 返回 | WGS-84 |
| 高德 / 腾讯渲染 | GCJ-02（客户端转换） |
| 高德逆地理 / POI | GCJ-02（调用前转换） |
| GPX / KML / CSV 导出 | WGS-84 |

> 任何情况下都不要把 GCJ-02 结果写回服务端，否则轨迹会整体偏移约 500 米。

## 7. 推送集成

### 7.1 中国大陆链路（生产）

```
Traccar 事件
  → NotificatorWebhook（自维护补丁，HTTP + HMAC）
  → 推送网关（去重/限流/模板/回执）
  → 极光 JPush REST（audience.alias）
  → 小米/华为/OPPO/vivo/荣耀 厂商通道
  → App
```

**服务端改造**（详见 [`server/README.md`](../server/README.md)）：

```xml
<entry key='notificator.types'>web,mail,webhook</entry>
<entry key='notificator.webhook.url'>https://push.example.com/v1/events</entry>
<entry key='notificator.webhook.secret'>随机密钥</entry>
```

**网关契约**

```json
{
  "version": 1,
  "userId": 1,
  "deviceId": 42,
  "deviceName": "京A·12345",
  "event": { "id": 555, "type": "geofenceEnter", "eventTime": "..." },
  "position": { "latitude": 39.9042, "longitude": 116.4074 },
  "message": { "title": "围栏进入", "body": "京A·12345 进入「公司」" },
  "issuedAt": 1793513700000
}
```

- 请求头 `X-Traccar-Signature: sha256=<hmac>`；
- 网关按 `event.id` 幂等；
- 网关按 `alias = u{userId}@{serverId}` 调极光；
- 非 2xx 只记录日志，Traccar 不自动重试。

**极光下行**

```json
{
  "platform": ["android", "ios"],
  "audience": { "alias": ["u1@1"] },
  "notification": {
    "android": {
      "title": "围栏进入",
      "alert": "京A·12345 进入「公司」",
      "extras": { "eventId": "555", "deviceId": "42" }
    },
    "ios": {
      "alert": "京A·12345 进入「公司」",
      "sound": "default",
      "extras": { "eventId": "555", "deviceId": "42" }
    }
  }
}
```

### 7.2 海外链路（FCM）

Traccar 使用 `firebase` notificator 时需要：

```xml
<entry key='notificator.firebase.serviceAccount'>...</entry>
<entry key='notificator.firebase.mode'>data|direct</entry>
```

```json
{
  "notification": { "title": "围栏进入", "body": "京A·12345 进入「公司」" },
  "data": { "eventId": "555", "event": "{...}", "position": "{...}" }
}
```

### 7.3 App 侧解析

无论通道，最终都归一化为：

```dart
class PushMessage {
  final int? eventId;      // 事件通知
  final String? command;   // 远程指令
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
}
```

| 通道 | 字段位置 |
|---|---|
| JPush | `notification.android.extras` / `notification.ios.extras` |
| FCM | `data` |
| 应用内 | WebSocket `{events:[...]}` |

### 7.4 生命周期

| 状态 | JPush（中国大陆） | FCM（海外） |
|---|---|---|
| 前台 | `onReceiveNotification` → 应用内横幅 | `onMessage` |
| 后台 | 厂商通道系统通知 | 系统通知 |
| 冷启动 | `getLaunchAppNotification()` 读 `extras` | `getInitialMessage()` |
| 点击 | `onOpenNotification` → `/event/{id}` | `onMessageOpenedApp` |

> 未登录时点击推送：先缓存 `eventId`，登录完成后再跳转，避免路由竞态。

## 8. 错误与边界

| HTTP | 含义 | 客户端处理 |
|---|---|---|
| 400 | 参数/协议错误 | 展示服务端 message（若有） |
| 401 | Token 失效 | 清理会话 → 登录页 |
| 403 | 无权限 | 展示权限说明，不重试 |
| 404 | 资源不存在 | 从缓存移除 |
| 429 | 限流 | 指数退避，提示稍后 |
| 5xx | 服务端错误 | 重试 2 次，之后展示错误卡片 |

**注意**

- 不要对 POST（指令、创建设备）自动重试，避免重复执行。
- 分页接口使用 `limit`/`offset`；位置按时间分段。
- 服务端时间与本地时间可能偏差；以 `fixTime` 为准，显示时转本地时区。

## 9. 版本兼容

| 服务端 | 支持 |
|---|---|
| 6.0+ | 基础 REST/WS |
| 6.8+ | 推荐；事件/指令字段更完整 |
| 6.16 | 开发基准 |
| < 6.0 | 不承诺 |

**能力探测**

1. `GET /api/server` 获取版本/名称。
2. 若接口返回 404，降级隐藏对应功能（如 OIDC、部分报表）。
3. 记录 `serverVersion` 到诊断页与错误上报。

## 10. 安全

- 强制 HTTPS（自签名需显式开关）。
- Token 不落日志、不进 URL（WebSocket 例外，使用 `wss`）。
- 证书固定（P1）：仅企业版，提供关闭开关。
- 服务器地址校验：禁止 `http://` 明文除非用户确认风险。
- 位置数据只在用户主动开启上报后发送。
- 退出登录/删除服务器档案时清除 Token、缓存与地图瓦片。

## 11. 联调清单

- [ ] 密码登录 → Token → REST 成功
- [ ] Token 过期 → 401 → 自动回登录
- [ ] WebSocket 连接、快照、增量、断线重连
- [ ] 本机上报 → 服务端出现位置 → WebSocket 收到
- [ ] 历史位置查询与导出
- [ ] 事件历史与实时事件
- [ ] 极光推送后台/冷启动可达，点击直达事件
- [ ] 推送网关 HMAC 校验、幂等、限流
- [ ] （海外）FCM 前台/后台/冷启动
- [ ] 设备指令发送与本机指令接收
- [ ] 用户/设备 Token 注册与清理
- [ ] 反代 + WebSocket + 自签名场景
- [ ] 服务端 6.0 与 6.16 兼容性抽测
