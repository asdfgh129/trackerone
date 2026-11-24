# server · 中国大陆推送链路

Traccar 6.16 自带 `web` / `firebase` / `traccar` 等通知器，但**没有通用 webhook**，
而 `firebase` 在中国大陆 Android 不可用。因此需要两件东西：

```
Traccar 事件
   │  NotificatorWebhook（本目录，需打补丁）
   ▼
自建推送网关（BFF）
   │  鉴权 / 别名映射 / 去重 / 限流 / 模板 / 回执
   ▼
极光 JPush REST  ──►  小米 / 华为 / OPPO / vivo / 荣耀 厂商通道
   │
   ▼
TrackerOne App
```

## 1. 给 Traccar 打补丁

### 1.1 放置文件

```bash
cp server/traccar-plugin/src/main/java/org/traccar/notificators/NotificatorWebhook.java \
   ../traccar/src/main/java/org/traccar/notificators/
```

### 1.2 注册通知器

编辑 `src/main/java/org/traccar/notification/NotificatorManager.java`：

```java
import org.traccar.notificators.NotificatorWebhook;

private static final Map<String, Class<? extends Notificator>> NOTIFICATORS_ALL = Map.of(
        "command", NotificatorCommand.class,
        "web", NotificatorWeb.class,
        "mail", NotificatorMail.class,
        "sms", NotificatorSms.class,
        "firebase", NotificatorFirebase.class,
        "traccar", NotificatorTraccar.class,
        "telegram", NotificatorTelegram.class,
        "whatsapp", NotificatorWhatsapp.class,
        "pushover", NotificatorPushover.class,
        "webhook", NotificatorWebhook.class);   // ← 新增
```

> `Map.of` 最多支持 10 组键值对。Traccar 6.16 当前是 9 组，加入 `webhook` 后正好 10 组；
> 若之后再新增第 11 个通知器，需要改为 `Map.ofEntries(...)`。

### 1.3 配置

`conf/traccar.xml`（或环境变量）：

```xml
<entry key='notificator.types'>web,mail,webhook</entry>
<entry key='notificator.webhook.url'>https://push.example.com/v1/events</entry>
<entry key='notificator.webhook.inboxUrl'>https://push.example.com/v1/messages</entry>
<entry key='notificator.webhook.inboxTypes'>commandResult</entry>
<entry key='notificator.webhook.serverId'>1</entry>
<entry key='notificator.webhook.secret'>替换为随机密钥</entry>
<entry key='notificator.webhook.timeoutSeconds'>5</entry>
```

- `inboxUrl` 可省略：默认把 `url` 的 `/v1/events` 替换为 `/v1/messages`；
- `inboxTypes` 逗号分隔，命中后写入收件箱而不是普通事件推送；
- 签名仍用 `secret`，Traccar 不需要配置 `ADMIN_TOKEN`。

### 1.4 在 Web 端启用

通知规则（Notifications）里把 `notificator` 选为 **webhook**。
默认值仍是 `web`，只推给在线 WebSocket。
指令结果需要为 `commandResult` 类型启用通知，否则收件箱收不到结果。

### 1.5 构建

```bash
cd ../traccar
./gradlew assemble        # 或 mvn package
```

## 2. 推送网关契约

### 2.1 接收事件

`POST /v1/events`

```http
Content-Type: application/json; charset=utf-8
X-Traccar-Signature: sha256=<hmac_sha256(raw_body, secret)>
```

```json
{
  "version": 1,
  "userId": 1,
  "userEmail": "user@example.com",
  "deviceId": 42,
  "deviceName": "京A·12345",
  "uniqueId": "12345678",
  "event": {
    "id": 555,
    "deviceId": 42,
    "type": "geofenceEnter",
    "eventTime": "2026-11-01T08:15:00.000+00:00",
    "positionId": 987700,
    "geofenceId": 7,
    "attributes": {}
  },
  "position": {
    "id": 987700,
    "deviceId": 42,
    "latitude": 39.9042,
    "longitude": 116.4074,
    "fixTime": "2026-11-01T08:14:58.000+00:00",
    "attributes": { "batteryLevel": 78 }
  },
  "message": { "title": "围栏进入", "body": "京A·12345 进入「公司」", "digest": "..." },
  "issuedAt": 1793513700000
}
```

校验要点：

1. 校验 HMAC（常量时间比较），失败返回 401；
2. `event.id` 做幂等（Redis `SETNX push:event:<id>`，TTL 24h）；
3. 只有 `userId` 在该网关注册过别名才推送；
4. 返回 2xx 后 Traccar 认为成功；非 2xx 只记录日志，不自动重试。

### 2.2 别名注册

App 登录后调用：

```http
POST /v1/aliases
Authorization: Bearer <app-session-token>
Content-Type: application/json

{
  "alias": "u1@1",
  "platform": "android",
  "vendor": "xiaomi",
  "appVersion": "1.0.0",
  "deviceModel": "Xiaomi 14"
}
```

- `alias` 规范：`u{traccarUserId}@{traccarServerId}`；
- 网关保存 `alias -> {jpushRegistrationId, platform, vendor, lastSeen}`；
- 退出登录调用 `DELETE /v1/aliases/{alias}`；
- App 不需要把极光 Registration ID 传给 Traccar，避免污染设备属性。

### 2.3 下发给极光

```http
POST https://api.jpush.cn/v3/push
Authorization: Basic base64(appKey:masterSecret)
```

```json
{
  "platform": ["android", "ios"],
  "audience": { "alias": ["u1@1"] },
  "notification": {
    "android": {
      "alert": "京A·12345 进入「公司」",
      "title": "围栏进入",
      "extras": { "eventId": "555", "deviceId": "42" }
    },
    "ios": {
      "alert": "京A·12345 进入「公司」",
      "sound": "default",
      "extras": { "eventId": "555", "deviceId": "42" }
    }
  },
  "options": {
    "time_to_live": 3600,
    "apns_production": true
  }
}
```

> 厂商通道离线消息必须把业务字段放在 `extras`，App 侧统一从 `extras` 解析
> `eventId` / `command`。

### 2.4 服务端下发消息（收件箱）

App 侧实现见 `docs/17-adr-downlink.md`。网关负责持久化、增量游标与投递回执，
推送只发「壳通知」（`extras.inboxId`），正文由 App 拉取。

**下发（管理员）**

```http
POST /v1/messages
Authorization: Bearer <ADMIN_TOKEN>
Content-Type: application/json

{
  "userId": 1,
  "kind": "command",
  "title": "指令：断油",
  "body": "调度要求对京A·12345 断油",
  "data": { "deviceId": 42, "command": "engineStop" },
  "expiresIn": 3600
}
```

- `kind`：`command` / `notice` / `chat`；缺省 `notice`；
- `expiresIn` 为秒，缺省 command 1h、chat 72h、notice 7d；
- 返回 `201`：`{"message": {...}, "push": "sent|no_alias|failed"}`；
- 推送失败不影响入库，App 下次同步仍能拉到；
- Traccar 也可直接调用：不带 `Authorization`，改用与 `/v1/events`
  相同的 `X-Traccar-Signature: sha256=<hmac>`，消息 `source` 记为 `traccar`。

**拉取（App）**

```http
GET /v1/messages?since=<游标>&limit=50
Authorization: Bearer <app-session-token>
```

```json
{
  "messages": [
    {
      "id": "msg_1_12",
      "kind": "command",
      "title": "指令：断油",
      "body": "调度要求对京A·12345 断油",
      "data": { "deviceId": 42, "command": "engineStop" },
      "createdAt": "2026-11-20T10:00:00Z",
      "expiresAt": "2026-11-20T11:00:00Z"
    }
  ],
  "nextCursor": "12"
}
```

- 网关用 Traccar Token 换用户与 serverId，按用户隔离，禁止越权；
- 游标为内部递增序号，客户端只需原样回传 `nextCursor`；
- 首次不带 `since` 返回最新一页（升序），后续只返回游标之后的消息；
- `limit` 上限 100，缺省 50。

**投递回执**

```http
POST /v1/messages/{id}/ack
Authorization: Bearer <app-session-token>
```

- 幂等；返回 `204`；消息不属于当前用户或不存在返回 `404`；
- ACK 表示「已收到」，不等于已读；已读仅存在 App 本地。

**撤回 / 重发（管理员）**

```http
POST /v1/messages/{id}/revoke?userId=1&serverId=1
POST /v1/messages/{id}/resend?userId=1&serverId=1
Authorization: Bearer <ADMIN_TOKEN>
```

- 撤回为软删除：App 不再拉取，审计仍保留 `revokedAt`；
- 重发只重推壳通知，不新增消息；已撤回或已过期返回 `400`。

**审计（管理员）**

```http
GET /v1/messages/audit?userId=1&serverId=1&cursor=&limit=50
Authorization: Bearer <ADMIN_TOKEN>
```

```json
{
  "messages": [
    {
      "id": "msg_1_12",
      "userId": 1,
      "serverId": 1,
      "kind": "notice",
      "title": "",
      "body": "success",
      "source": "traccar",
      "pushStatus": "sent",
      "pushAttempts": 1,
      "pushedAt": "2026-11-24T10:00:01Z",
      "ackedAt": "2026-11-24T10:00:05Z",
      "revokedAt": null,
      "data": { "eventType": "commandResult", "deviceId": 42 }
    }
  ],
  "nextCursor": "12"
}
```

- 按序号倒序；`nextCursor` 为空串表示没有更多；
- 含已撤回、已过期消息，便于排查投递与回执。

**指令结果**

Traccar 的 `commandResult` 默认由 `NotificatorWebhook` 直接写入
`POST /v1/messages`（`inboxTypes` 可配置）；旧插件仍发 `/v1/events` 时，
网关会自动转为收件箱消息。`data` 含 `eventType/eventId/deviceId/result/success`，
App 以本地化「指令结果」卡片展示。

**清空（管理员，注销 / 清除数据）**

```http
DELETE /v1/messages?userId=1&serverId=1
Authorization: Bearer <ADMIN_TOKEN>
```

## 3. 网关最小实现建议

> ✅ **已实现**：`server/push-gateway/`（Go，单二进制 + Redis，Docker 可直接部署）。
> 见 [`server/push-gateway/README.md`](push-gateway/README.md)：
> HMAC 校验、幂等、限流合并、免打扰、文案模板、重试与死信、审计日志、
> 别名越权拦截、健康检查，`go test ./...` 全绿。
> 本节保留为设计依据。

| 能力 | 说明 |
|---|---|
| 鉴权 | Traccar → 网关用 HMAC；App → 网关用 Traccar Token 换取短期 JWT |
| 幂等 | Redis 键 `push:event:<eventId>` |
| 限流 | 单用户 60 条/分钟，超出合并 |
| 模板 | 按 `event.type` 渲染中英文案，避免服务端硬编码 |
| 静默 | 用户免打扰时段只入库不推送 |
| 回执 | 极光 callback → 记录到达/点击，用于看板 |
| 多服务器 | alias 带 `serverId`，支持多 Traccar 实例 |

推荐技术栈：Go / Java（Spring Boot）/ Node.js 均可；数据库 PostgreSQL + Redis。
日均 10 万事件以内，单实例 1C2G 足够。

## 4. 本地联调

```bash
# 模拟 Traccar 调用
BODY='{"version":1,"userId":1,"deviceId":42,"event":{"id":555,"type":"geofenceEnter"},"message":{"title":"测试","body":"hello"}}'
SECRET='dev-secret'
SIG=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')

curl -i -X POST http://localhost:8080/v1/events \
  -H 'Content-Type: application/json' \
  -H "X-Traccar-Signature: sha256=$SIG" \
  -d "$BODY"
```

## 5. 注意

- 这个补丁让服务端从「官方 Traccar」变成**自维护分支**，升级 Traccar 时需要重新应用；
- 若不想维护分支，备选方案是网关轮询 `/api/reports/events`，但有延迟与配额成本；
- 不要把极光 Master Secret 放进 App 或客户端仓库，只放服务端环境变量。
