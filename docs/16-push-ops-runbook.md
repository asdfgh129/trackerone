# 16 · 推送落地操作手册（厂商通道 / 推送网关 / Traccar 对接）

> 本文是 `docs/12` 的**执行版**：按顺序做完即可跑通「Traccar 事件 → 极光 → 手机锁屏通知」。
> 接口契约见 `docs/12-push-integration.md` 与 `server/README.md`，本文只讲「怎么做」。

## 0. 谁做什么

| # | 事项 | 负责人 | 产出 | 阻塞项 |
|---|---|---|---|---|
| 1 | 极光应用创建与 AppKey | 你（企业实名） | `JPUSH_APP_KEY`、`JPUSH_MASTER_SECRET` | 极光企业认证 |
| 2 | 厂商通道申请（小米/华为/荣耀/OPPO/vivo） | 你（企业资质） | 各厂商 AppKey / 推送证书 | 企业主体 + 1–2 周审核 |
| 3 | APNs 证书/Auth Key（iOS） | 你（Apple 账号） | `.p8` + Key ID + Team ID | Apple Developer 账号 |
| 4 | 推送网关服务 | 我可以写（Go/Node 二选一）+ 你部署 | `push.example.com` | 一台服务器 + 域名 + HTTPS |
| 5 | Traccar 打补丁与配置 | 你（服务器权限），我出步骤/校验 | `webhook` 通知器生效 | Traccar 源码或可回滚的环境 |
| 6 | 客户端验证 | 一起做 | 诊断页 alias + 锁屏通知 | 真机 |

> 🔴 **红线**：`JPUSH_MASTER_SECRET` 只进网关环境变量与 CI Secret，
> 永远不要出现在 App、git、聊天记录、截图中。

---

## 1. 极光后台（30 分钟）

1. <https://www.jpush.cn/common/apps> → 创建应用 `TrackerOne`。
2. Android：填包名 `com.trackerone.app`；iOS：填 Bundle ID `com.trackerone.app`。
3. 应用设置 → 记录：
   - `AppKey`（客户端用，**已内置**：`2e6135fffb1db1d409ab1d62`）
   - `Master Secret`（服务端用，**给我时用密码管理器私发，不要贴进仓库**）
4. 应用设置 → Android → 逐个添加厂商通道（见第 2 节）。
5. 应用设置 → iOS → 上传 APNs Auth Key（`.p8`），填 Key ID、Team ID，
   区分「开发 / 生产」两套环境。

客户端无需改动：`BuildConfig.jpushAppKey` 与 Gradle `JPUSH_APPKEY` 占位符已内置同一个 AppKey。

---

## 2. 厂商通道（1–2 周，主要耗时在资质）

在极光后台「应用设置 → 厂商通道」逐个添加。每家都要在**对应厂商开放平台**
先创建应用、拿到该厂商自己的 AppKey / 推送证书，再填进极光。

| 厂商 | 开放平台 | 需要填到极光的 | 资质要求 | 备注 |
|---|---|---|---|---|
| 小米 | <https://dev.mi.com> | 小米 AppId + AppKey + 包名签名 | 企业主体 | 需在小米后台开通「消息推送」并上传包名+签名 |
| 华为 | <https://developer.huawei.com> | 华为 App ID + 包名签名 | 企业主体 | HMS Core 需在应用内集成（SDK 侧工作量大） |
| 荣耀 | <https://developer.honor.com> | 荣耀 App ID + 包名签名 | 企业主体 | 与华为流程类似但独立申请 |
| OPPO | <https://open.oppomobile.com> | OPPO AppKey + 包名 + 证书指纹 | 企业主体 | 需在 OPPO 后台开通推送 |
| vivo | <https://dev.vivo.com.cn> | vivo AppKey + 包名 + 证书指纹 | 企业主体 | 同上 |

通用要点：

- **包名与签名必须与正式包一致**：`com.trackerone.app` + 本仓库 `upload-keystore.jks`
  的证书指纹（SHA1 `0B:21:56:4F:7E:F3:91:9E:60:35:68:1D:84:88:D9:FD:D6:AB:0E:E9`）。
  用 debug 签名在厂商后台是收不到的。
- 厂商通道未开通时，极光会回落到自有通道，App 仍能收到，只是锁屏/省电时到达率下降。
- 华为通道要集成 HMS，需要额外的原生依赖与包体增量；建议先做小米 + OPPO + vivo，
  华为/荣耀放到第二批。

**性价比排序**：小米 > OPPO > vivo > 荣耀 > 华为（华为集成成本最高）。

---

## 3. 推送网关（我出代码，你出机器）

### 3.1 需要你准备

- 一台能跑 Docker 的云服务器（1C2G 足够）；
- 一个域名，如 `push.example.com`，解析到该服务器；
- HTTPS 证书（Let's Encrypt 即可），Traccar 只允许 HTTPS 调用。

### 3.2 我可以直接产出（说一声就开工）

- 网关最小实现（推荐 Go，单二进制 + Redis）：
  - `POST /v1/events`：验 HMAC（`X-Traccar-Signature`）、`event.id` 幂等、限流、渲染文案；
  - `POST /v1/aliases` / `DELETE /v1/aliases/{alias}`：别名注册与解绑；
  - 调极光 `POST https://api.jpush.cn/v3/push`；
  - `Dockerfile` + `docker-compose.yml`（含 Redis）+ `.env.example`；
  - 一键自测脚本（模拟 Traccar 事件 → 检查极光返回）。
- 需要你回填的只有两个环境变量：`JPUSH_APP_KEY`、`JPUSH_MASTER_SECRET`。

### 3.3 最小能力清单（验收用）

| 能力 | 验收方式 |
|---|---|
| HMAC 校验 | 故意改 body → 网关返回 401 |
| 幂等 | 同一 `event.id` 连发两次 → 极光只收到 1 条 |
| 别名隔离 | alias `u2@1` 不会收到 `u1@1` 的事件 |
| 限流 | 单用户 60 条/分钟后合并或丢弃 |
| 文案模板 | `event.type=geofenceEnter` → 中文标题「围栏进入」 |
| 审计日志 | 每条投递记录 eventId、alias、极光 msg_id、耗时 |

---

## 4. Traccar 服务端（已有补丁，按步骤打）

补丁源码已在仓库：`server/traccar-plugin/src/main/java/org/traccar/notificators/NotificatorWebhook.java`。

1. 放到 Traccar 源码目录：

```bash
cp server/traccar-plugin/src/main/java/org/traccar/notificators/NotificatorWebhook.java \
   /path/to/traccar/src/main/java/org/traccar/notificators/
```

2. 在 `NotificatorManager.NOTIFICATORS_ALL` 注册 `"webhook"`（注意 `Map.of` 最多 10 组，
   当前正好 10 组；以后再加要改成 `Map.ofEntries`）。
3. `conf/traccar.xml` 增加：

```xml
<entry key='notificator.types'>web,mail,webhook</entry>
<entry key='notificator.webhook.url'>https://push.example.com/v1/events</entry>
<entry key='notificator.webhook.secret'>与网关一致的随机密钥</entry>
<entry key='notificator.webhook.timeoutSeconds'>5</entry>
```

4. 重启 Traccar；Web 端 → 通知规则 → `notificator` 选 **webhook**，
   事件类型按需勾选（围栏进入/离开、告警、指令结果）。
5. 自检：

```bash
tail -f /opt/traccar/logs/traccar.log | grep -i webhook
```

> 不想维护 Traccar 分支时的备选：网关轮询 `GET /api/reports/events`，
> 代价是延迟（≥1 分钟）与额外 API 配额，见 `server/README.md` 第 5 节。

---

## 5. 客户端（代码已就绪，只需真机验证）

- 登录后自动注册 alias `u{userId}@{serverId}`；
- **必须先在首启隐私弹窗点「同意并继续」**，否则不会初始化极光 SDK（合规要求）；
- 「设置 → 诊断」页应显示：通道 `jpush`、alias、已注册、无错误；
- 退出登录 / 注销账号会自动解绑 alias。

---

## 6. 端到端验收清单

逐条勾选，全绿才算完成（对应 `docs/12` 第 6 节）：

- [ ] 网关用 `curl` 模拟 Traccar 事件 → 极光返回 `msg_id`
- [ ] App 前台收到事件消息
- [ ] App 后台收到系统通知
- [ ] 锁屏 5 分钟内收到（厂商通道生效的机型）
- [ ] 冷启动点击通知 → 直达 `/event/:id`
- [ ] 未登录点击通知 → 登录后补跳转
- [ ] 断网发送 → 恢复后重试且不重复
- [ ] 退出登录后不再收到该账号通知
- [ ] iOS（配好 APNs 后）收到并能点击

---

## 7. 排障顺序

| 现象 | 先查 | 再查 |
|---|---|---|
| 诊断页「未注册」 | 隐私弹窗是否已同意 | `PUSH_PROVIDER`、AppKey、网络 |
| 网关调极光失败 | Master Secret / 配额 / IP 白名单 | 请求体 `audience.alias` 是否与 App 注册一致 |
| 前台收不到 | 网关是否真的发出 | 客户端是否在消费 `messages` 流 |
| 锁屏收不到 | 厂商通道状态与配额 | 包名/签名是否与厂商后台一致、电池优化 |
| 点击不跳转 | `extras.eventId` 是否透传 | 厂商通道是否剥离 `extras` |
| 重复通知 | 网关幂等键 | 是否有多条通知规则同时命中 |

---

## 8. 建议排期

| 阶段 | 时长 | 说明 |
|---|---|---|
| 极光后台 + Master Secret | 0.5 天 | 你 |
| 网关开发与自测 | 1–2 天 | 我（你提供服务器与域名） |
| Traccar 补丁与联调 | 0.5 天 | 你（服务器权限） |
| 厂商通道申请（小米/OPPO/vivo） | 1–2 周 | 你（资质审核并行） |
| 真机端到端验证 | 0.5 天 | 一起 |
| iOS APNs 链路 | 依赖 Apple 账号 | 你 |

---

## 9. 当前状态

| 项 | 状态 |
|---|---|
| 客户端 alias 注册 / 点击深链 / 远程指令 / 诊断页 | ✅ 代码完成 |
| 首启隐私同意后才初始化推送 SDK | ✅ 本轮完成 |
| 极光 AppKey | ✅ 已内置（`2e61…1d62`） |
| 极光 Master Secret | ⛔ 待你提供（仅给网关） |
| 厂商通道 | ⛔ 待申请 |
| 推送网关 | ⛔ 待实现与部署（我可以写） |
| Traccar webhook 通知器 | ✅ 补丁已写好，待打到你服务器 |
| 真机锁屏/冷启动验证 | ⛔ 待真机 |
