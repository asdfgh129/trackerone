# 推送网关（TrackerOne · 中国大陆推送链路）

Traccar 事件 → 本网关 → 极光 JPush → 厂商通道 → TrackerOne App。

服务端只有一个职责：**把事件安全、幂等、可合并地送到用户设备**。
不代理业务 API、不存业务数据、不做账号体系。

## 1. 能力一览

| 能力 | 实现 |
|---|---|
| Traccar → 网关鉴权 | HMAC-SHA256（`X-Traccar-Signature: sha256=<hex>`），常量时间比较 |
| App → 网关鉴权 | `Authorization: Bearer <Traccar Token>`，网关回 Traccar `/api/session` 校验，别名必须属于该用户 |
| 幂等 | `event.id` 作为幂等键，默认保留 24 小时 |
| 限流 | 单用户每分钟上限（默认 60），超出部分合并成一条延后推送 |
| 免打扰 | `QUIET_HOURS=22:00-07:00`，时段内只入库不推送，次日补发 |
| 文案模板 | 中英文模板，按 `event.type` 渲染（围栏进入/离开、告警、点火、超速…） |
| 重试与死信 | 投递失败指数退避重试 3 次，仍失败写入死信列表 |
| 审计 | JSON 结构化日志：eventId、alias、类型、极光 msg_id、耗时 |
| 健康检查 | `/healthz`（存活）、`/readyz`（依赖就绪） |

## 2. 接口

### `POST /v1/events` —— 接收 Traccar webhook

```http
POST /v1/events
Content-Type: application/json
X-Traccar-Signature: sha256=<hmac_hex>
X-Locale: zh            # 可选，默认取 DEFAULT_LOCALE

{ "version": 1, "userId": 42, "deviceId": 7, "deviceName": "京A·12345",
  "event": { "id": 555, "type": "geofenceEnter", "attributes": {...} },
  "position": {...}, "message": {...} }
```

响应（HTTP 202）：

```json
{ "status": "sent", "eventId": 555, "alias": "u42@1", "msgId": "123456" }
```

`status` 取值：`sent` / `coalesced`（超限合并）/ `deferred`（免打扰）/ `duplicate`（幂等命中）/
`no_alias`（未注册别名，丢弃）/ `skipped` / `failed`。

签名不对返回 `401`，网关不会重试也不会记录事件。

### `POST /v1/aliases` —— 注册别名

```http
POST /v1/aliases
Authorization: Bearer <Traccar Token>
Content-Type: application/json

{ "alias": "u42@1", "platform": "android", "vendor": "xiaomi",
  "appVersion": "0.4.0", "deviceModel": "Xiaomi 14" }
```

网关会校验 Token 对应的用户 id 与别名里的 `u{userId}` 一致、`/api/server` 的 id 与
`@{serverId}` 一致，防止越权绑定他人别名。

### `DELETE /v1/aliases/{alias}` —— 解绑

退出登录 / 注销账号时调用，Bearer 头仍需带 Traccar Token。

### 管理接口（需 `Authorization: Bearer $ADMIN_TOKEN`）

- `GET /v1/aliases` —— 别名列表
- `GET /v1/dead?limit=50` —— 死信列表
- `POST /v1/flush` —— 手动触发延后队列投递

## 3. 本地运行

```bash
# 1) 起 Redis（没有 Redis 时用内存存储）
docker run -d --name push-redis -p 6379:6379 redis:7-alpine

# 2) 起网关（不接真实极光）
TRACCAR_WEBHOOK_SECRET=dev-secret \
STORE_BACKEND=memory DRY_RUN=true LISTEN_ADDR=127.0.0.1:8080 \
ADMIN_TOKEN=admin-token \
go run ./cmd/gateway

# 3) 注册别名并模拟一条事件
GATEWAY_URL=http://127.0.0.1:8080 SECRET=dev-secret ./scripts/send_test_event.sh
```

内存模式重启会丢数据，生产必须用 Redis。

## 4. 部署

```bash
cp .env.example .env    # 填入 TRACCAR_WEBHOOK_SECRET / JPUSH_MASTER_SECRET / ADMIN_TOKEN
docker compose up -d
```

网关只需要一个域名（如 `push.example.com`）与 HTTPS 证书；Traccar 侧配置见
仓库根目录 `server/README.md`。

## 5. 环境变量

见 `.env.example`。关键项：

| 变量 | 说明 |
|---|---|
| `TRACCAR_WEBHOOK_SECRET` | 与 Traccar `notificator.webhook.secret` 一致 |
| `TRACCAR_BASE_URL` | Traccar 地址，用于校验客户端 Token；不配则跳过校验 |
| `TRACCAR_SERVER_ID` | Traccar 服务端 id，决定别名后缀，默认 1 |
| `JPUSH_APP_KEY` / `JPUSH_MASTER_SECRET` | 极光凭据；**Master Secret 只放这里** |
| `STORE_BACKEND` | `redis`（生产）/ `memory`（本地联调） |
| `RATE_LIMIT_PER_MINUTE` | 单用户每分钟上限 |
| `QUIET_HOURS` / `QUIET_HOURS_TZ` | 免打扰时段与时区 |
| `DRY_RUN` | `true` 时不调用极光，只跑通流程 |
| `ADMIN_TOKEN` | 管理接口令牌，留空则禁用管理接口 |

## 6. 测试

```bash
go test ./...
```

覆盖：签名校验与别名解析、文案渲染、事件幂等、限流合并与延后补发、
别名越权拦截、HTTP 接口鉴权与健康检查。

## 7. 安全红线

- `JPUSH_MASTER_SECRET` 只出现在网关环境变量与 CI Secret，禁止进 App / git / 日志；
- Traccar → 网关必须走 HTTPS + HMAC；
- 通知文案不要包含完整车牌、手机号等敏感信息，必要时在网关侧脱敏；
- 中国大陆用户数据不得出网到境外服务。
