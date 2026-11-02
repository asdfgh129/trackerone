# 03 · 技术架构

## 1. 架构目标

| 目标 | 设计手段 |
|---|---|
| 可替换定位引擎 | `TrackingEngine` 接口 + SDK 适配器 |
| 可替换地图 | `MapAdapter` / 瓦片配置，业务层只认经纬度 |
| 可测试 | 依赖注入（Riverpod）、Repository 接口、纯 Dart 领域层 |
| 离线优先 | drift 缓存 + 先读后同步 + 写入队列 |
| 实时性 | WebSocket 单连接 + 事件总线 + 快照恢复 |
| 白标 | `Brand` 配置 + flavor + 远程开关 |
| 低耦合 | feature-first，feature 之间只通过 domain/repository 交互 |

---

## 2. 总体架构

```
┌──────────────────────────────────────────────────────────────┐
│ Presentation                                                 │
│  Screens / Widgets / Controllers (Riverpod Notifier)         │
├──────────────────────────────────────────────────────────────┤
│ Application                                                  │
│  Use cases / Services: Session, Tracking, Sync, Push, Command│
├──────────────────────────────────────────────────────────────┤
│ Domain                                                       │
│  Entities: Device, Position, Event, ServerProfile, User      │
│  Repository interfaces / Value objects / Failures            │
├──────────────────────────────────────────────────────────────┤
│ Data                                                         │
│  TraccarApi (REST) · TraccarSocket (WS) · LocalDb (drift)    │
│  SecureStore · Prefs · TrackingEngine · Map(AMap) · Push(JPush/FCM) │
├──────────────────────────────────────────────────────────────┤
│ Platform                                                     │
│  Android / iOS: 定位、通知、生物识别、文件、网络              │
└──────────────────────────────────────────────────────────────┘
```

### 依赖方向

```
features → application → domain ← data
                ↑                   │
                └──── providers ────┘
```

- `domain` 不依赖 Flutter、Dio、drift。
- `data` 实现 `domain` 的 Repository 接口。
- `features` 只依赖 `application` / `domain`，不直接调用 Dio。
- 跨 feature 复用放到 `core` 或独立的 `domain` 模块。

---

## 3. 模块划分

```
lib/
├── main.dart
├── app/
│   ├── app.dart                 # MaterialApp.router
│   ├── router.dart              # go_router + 守卫
│   ├── theme.dart
│   └── shell.dart               # 底部导航骨架
├── core/
│   ├── config/
│   │   ├── brand.dart           # 品牌、包名、默认地址
│   │   └── build_config.dart    # --dart-define
│   ├── network/
│   │   ├── api_client.dart      # Dio 实例
│   │   ├── auth_interceptor.dart
│   │   ├── retry_interceptor.dart
│   │   └── socket_client.dart   # WebSocket 生命周期
│   ├── storage/
│   │   ├── database.dart        # drift
│   │   ├── secure_store.dart
│   │   └── preferences.dart     # 命名空间隔离
│   ├── tracking/
│   │   ├── tracking_engine.dart # 接口
│   │   └── sdk_tracking_engine.dart
│   ├── push/
│   │   ├── push_gateway.dart    # 抽象 + Noop
│   │   ├── jpush_push_gateway.dart
│   │   ├── fcm_push_gateway.dart
│   │   ├── push_service.dart    # alias / 注册 / 消息门面
│   │   └── push_router.dart     # data → 深链（待实现）
│   ├── location/
│   │   └── permission_service.dart
│   ├── map/
│   │   ├── geo_point.dart            # 坐标点 + 坐标系枚举
│   │   ├── coordinate_transform.dart # WGS84/GCJ02/BD09
│   │   ├── map_models.dart           # 标记/尾迹/相机
│   │   ├── map_provider.dart         # 供应商配置
│   │   ├── map_privacy_consent.dart  # SDK 隐私授权
│   │   ├── tracker_map_view.dart     # 唯一地图入口
│   │   └── amap/
│   │       ├── amap_bootstrap.dart
│   │       └── amap_tracker_map.dart
│   ├── observability/
│   │   ├── logger.dart
│   │   └── crash_reporter.dart
│   └── utils/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── failures.dart
└── features/
    ├── onboarding/
    ├── auth/
    ├── server/
    ├── map/
    ├── devices/
    ├── history/
    ├── events/
    ├── tracking/
    ├── commands/
    ├── diagnostics/
    └── settings/
```

### Feature 内部结构

```
features/map/
├── data/
│   └── map_repository_impl.dart
├── application/
│   └── map_controller.dart      # Notifier
├── domain/
│   └── map_state.dart
└── presentation/
    ├── map_screen.dart
    └── widgets/
```

---

## 4. 状态管理

### 选型：Riverpod

理由：

- 编译期安全、易测试、无需 BuildContext。
- 适合异步数据（`AsyncValue`）与依赖覆盖（测试替换）。
- 与 go_router 的 redirect 配合良好。

### 约定

| 类型 | 用途 | 示例 |
|---|---|---|
| `Provider` | 依赖注入 / 只读依赖 | `apiClientProvider` |
| `NotifierProvider` | 可变 UI 状态 | `trackingControllerProvider` |
| `AsyncNotifierProvider` | 异步加载 + 刷新 | `devicesControllerProvider` |
| `StreamProvider` | 实时流 | `livePositionsProvider` |
| `FutureProvider.family` | 参数化查询 | `historyProvider(range)` |

### 状态建模

```dart
sealed class TrackingState {
  const TrackingState();
}
class TrackingStopped extends TrackingState {}
class TrackingStarting extends TrackingState {}
class TrackingRunning extends TrackingState {
  final DateTime lastUpload;
  final int queueSize;
}
class TrackingLimited extends TrackingState {
  final LimitationReason reason;
}
class TrackingFailed extends TrackingState {
  final String message;
}
```

- UI 用 `switch` 穷尽处理状态。
- 禁止在 Widget 内直接发网络请求。
- 所有副作用集中在 Controller / Service。

---

## 5. 路由

`go_router` 路由表：

| 路径 | 页面 | 守卫 |
|---|---|---|
| `/` | 启动决策 | — |
| `/welcome` | 欢迎/模式选择 | — |
| `/server` | 服务器配置 | — |
| `/login` | 登录 | — |
| `/onboarding/permissions` | 权限向导 | — |
| `/home/map` | 地图 | 需要服务器 + 登录 |
| `/home/devices` | 设备列表 | 同上 |
| `/home/events` | 事件 | 同上 |
| `/home/tracking` | 跟踪 | 需要服务器 |
| `/home/settings` | 我的 | — |
| `/device/:id` | 设备详情 | 登录 |
| `/device/:id/history` | 历史回放 | 登录 |
| `/event/:id` | 事件详情 | 登录 |
| `/diagnostics` | 诊断 | — |

**守卫规则**

1. 无服务器档案 → `/server`。
2. 需要登录但无 Token → `/login`，并记录 `redirect`。
3. 推送冷启动跳转延迟到会话恢复完成，避免竞态。
4. 深链 scheme 同时支持 `trackerone://` 与配置用的 `https://` Universal Link。

---

## 6. 网络层

### 6.1 REST

```dart
Dio buildDio(ServerProfile profile, TokenStore tokens) {
  return Dio(BaseOptions(
    baseUrl: profile.apiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 20),
    headers: {'Accept': 'application/json'},
  ))
    ..interceptors.addAll([
      AuthInterceptor(tokens),
      RetryInterceptor(maxRetries: 2),
      LogInterceptor(redact: true),
    ]);
}
```

**拦截器职责**

| 拦截器 | 职责 |
|---|---|
| Auth | 注入 `Authorization: Bearer`；401 时触发登出 |
| Retry | 幂等请求（GET）指数退避；避免重复 POST |
| Error | 将 DioException 映射为 `AppFailure` |
| Log | 脱敏记录 method/path/status/耗时，不记录 body 中的 token |

**Cookie 处理**：登录的第一步需要 JSESSIONID，使用 `dio_cookie_manager` + `cookie_jar`（或手动读取 `set-cookie`）完成 `session → token` 的换取。换取成功后不再依赖 Cookie。

### 6.2 WebSocket

```
connect(token) → wss://host/api/socket?token=...
  ├─ onOpen: 收到最新 positions 快照
  ├─ onData: {positions|devices|events|logs:[...]}
  ├─ onError/onDone: 指数退避重连（1s→30s，±20% 抖动）
  └─ 前台恢复 / 网络恢复: 立即重连并拉快照
```

**要求**

- 全局单连接，按用户/服务器隔离。
- 连接状态暴露为 `Stream<SocketStatus>`。
- 应用进入后台 30 秒后主动断开（省电），前台恢复重连。
- 消息解析失败不崩溃，记录并丢弃。
- 事件去重：`event.id`；位置去重：`(deviceId, fixTime)`。

### 6.3 在线/离线

- `connectivity_plus` 仅作提示，不作为唯一真相。
- 以请求成功/失败为准；离线时写队列，恢复后重放。
- 读操作：先返回缓存（`AsyncValue.data` + `isRefreshing`），再后台刷新。

---

## 7. 本地存储

### 7.1 drift 数据库

表设计（v1）：

```sql
CREATE TABLE server_profiles (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  api_base_url TEXT NOT NULL,
  report_url TEXT NOT NULL,
  is_active INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE devices (
  id INTEGER PRIMARY KEY,          -- 服务端 id
  server_id INTEGER NOT NULL,
  unique_id TEXT,
  name TEXT,
  category TEXT,
  status TEXT,
  last_update INTEGER,
  attributes TEXT,                 -- JSON
  raw TEXT                         -- JSON 原始对象
);

CREATE TABLE positions (
  id INTEGER PRIMARY KEY,
  server_id INTEGER NOT NULL,
  device_id INTEGER NOT NULL,
  fix_time INTEGER NOT NULL,
  latitude REAL NOT NULL,
  longitude REAL NOT NULL,
  altitude REAL,
  speed REAL,
  course REAL,
  accuracy REAL,
  battery REAL,
  attributes TEXT,
  UNIQUE(server_id, device_id, fix_time)
);

CREATE TABLE events (
  id INTEGER PRIMARY KEY,
  server_id INTEGER NOT NULL,
  device_id INTEGER,
  type TEXT,
  event_time INTEGER,
  read INTEGER NOT NULL DEFAULT 0,
  raw TEXT
);

CREATE TABLE pending_actions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,              -- command / read / mute
  payload TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  retries INTEGER NOT NULL DEFAULT 0
);
```

**保留策略**：位置 7 天、事件 30 天、日志 7 天；按服务器隔离；退出登录可选择清除。

### 7.2 Secure Storage

| Key | 内容 |
|---|---|
| `auth.token.<serverId>` | 会话 Token |
| `auth.password.<serverId>` | 可选保存的密码（默认不保存） |
| `biometric.enabled` | 生物识别开关（非敏感） |

- Android 使用 EncryptedSharedPreferences / Keystore。
- iOS 使用 Keychain（`first_unlock_this_device`）。
- 生物识别只保护"读取动作"，不重复加密。

### 7.3 SharedPreferences

统一命名空间，避免旧项目 `url` 冲突：

```
app.theme
app.locale
app.units
tracking.deviceId
tracking.accuracy
tracking.interval
tracking.distance
tracking.angle
tracking.heartbeat
tracking.buffer
tracking.stopDetection
tracking.wakeLock
tracking.preferPlatformProviders
map.provider
map.style
map.trail
notifications.enabled
diagnostics.uploadLogs
```

---

## 8. 跟踪引擎抽象

```dart
abstract interface class TrackingEngine {
  Future<void> init(TrackingConfig config);
  Future<void> start();
  Future<void> stop();
  Future<bool> requestPosition({String? alarm});
  Future<bool> isTracking();
  Future<void> applyConfig(TrackingConfig config);
  Stream<TrackingEvent> get events;
  Future<List<TrackingLogEntry>> getLogs();
  Future<void> clearLogs();
}
```

- 默认实现：`SdkTrackingEngine`（包装 `traccar_client_sdk`）。
- 备选实现：`ForegroundTaskTrackingEngine`（geolocator + flutter_foreground_task），用于无法使用 SDK 的场景。
- 通过 `trackingEngineProvider` 注入；测试使用 Fake。

详见 [05-tracking-engine.md](05-tracking-engine.md)。

---

## 9. 地图抽象

业务层只依赖 `lib/core/map/` 中的模型与唯一入口 `TrackerMapView`：

```dart
class GeoPoint { final double latitude; final double longitude; }
class MapDeviceMarker { final int deviceId; final GeoPoint point; final double course; ... }
```

渲染层通过 `MapConfig` 选择：

| 方案 | 适用 | 备注 |
|---|---|---|
| **高德 `amap_map`** | **中国大陆首发** | Apache-2.0，GCJ-02，需隐私授权 |
| 腾讯 `flutter_tencent_map` | 备选 | 同 GCJ-02，业务层无需改动 |
| flutter_map + 栅格瓦片 | 海外 / 自托管 / 无 Key | 纯 Dart，保留为 fallback |
| MapLibre GL | 矢量、大量数据 | 后期评估 |

**坐标系**：服务端与缓存统一 WGS-84；只在 `amap_tracker_map.dart` 内转 GCJ-02。

```
Traccar (WGS-84)
   → LocalDb (WGS-84)
   → MapDeviceMarker (WGS-84)
   → AmapTrackerMap → CoordinateTransform.wgs84ToGcj02 → AMapWidget
```

- 点击地图回调反向转回 WGS-84 再交给业务层；
- 导出 GPX/KML/CSV 永远使用 WGS-84；
- 百度 BD-09 转换已实现但**不启用**，避免误用。

---

## 10. 推送与深链

### 10.1 通道抽象

```dart
abstract interface class PushGateway {
  String get id;
  Future<void> initialize({required String alias});
  Future<void> updateAlias(String alias);
  Stream<PushMessage> get messages;
  Future<PushMessage?> takeInitialMessage();
  Future<void> dispose();
}
```

| 实现 | 场景 | SDK |
|---|---|---|
| `JpushPushGateway` | 中国大陆生产 | `jpush_flutter` |
| `FcmPushGateway` | 海外 / 开发 | `firebase_messaging` |
| `NoopPushGateway` | 未配置，仅应用内事件 | — |

由 `BuildConfig.pushProvider` 选择，`pushGatewayProvider` 注入。

### 10.2 中国大陆链路

```
Traccar 事件
  → NotificatorWebhook（server/ 补丁，HMAC 签名）
  → 推送网关（去重/限流/模板/回执）
  → 极光 REST（audience.alias）
  → 小米/华为/OPPO/vivo/荣耀 厂商通道
  → App
```

别名规范：`u{userId}@{serverId}`，登录后注册，退出时删除。

> 中国大陆包**不初始化** Firebase；但当前依赖仍会打包 Firebase 原生库，\n> 提审前需按 [`docs/09` 3.9 节](09-china-launch.md) 做构建隔离。

### 10.3 海外链路（FCM）

```
FirebaseMessaging
 ├─ onMessage            → 应用内横幅 + 事件流
 ├─ onMessageOpenedApp   → 路由到 /event/:id
 ├─ getInitialMessage    → 缓存，登录后跳转
 └─ onBackgroundMessage  → 最小依赖，更新本地事件缓存
```

Token 注册两条链路（仅海外）：

| 用途 | 目标 | 方式 |
|---|---|---|
| 设备远程指令 | `device.attributes.notificationTokens` | 上报带 `notificationToken` 或 `PUT /api/devices/{id}` |
| 用户事件推送 | `user.attributes.notificationTokens` | `PUT /api/users/{id}` |

### 10.4 深链

| Scheme | 用途 |
|---|---|
| `trackerone://event/<id>` | 推送/分享 |
| `trackerone://server?url=...` | 配置导入 |
| `https://<domain>/...` | Universal Link（P1） |

`app_links` 单流监听，按 host 分流；未登录时缓存意图。

> JPush 厂商通道点击会带 `n_extra` 参数，Flutter 3.29+ 需关闭自动深链
> （`shouldHandleDeeplinking() = false`），否则冷启动白屏。

---

## 11. 错误模型

```dart
sealed class AppFailure {
  final String message;
  final String? code;
}
class NetworkFailure extends AppFailure {}
class TimeoutFailure extends AppFailure {}
class UnauthorizedFailure extends AppFailure {}
class ForbiddenFailure extends AppFailure {}
class NotFoundFailure extends AppFailure {}
class ServerFailure extends AppFailure {}      // 5xx
class ValidationFailure extends AppFailure {}  // 4xx 业务
class TrackingFailure extends AppFailure {}
class PermissionFailure extends AppFailure {}
```

- UI 只展示 `userMessage`，详细错误进日志。
- 401 统一跳登录；403 展示权限说明；5xx 提供重试。
- 错误上报到崩溃平台时附带 `code`、页面、服务器版本（不含 token/位置）。

---

## 12. 可观测性

| 类型 | 方案 |
|---|---|
| 崩溃 | 中国大陆：腾讯 Bugly；海外：Firebase Crashlytics；默认 `NoopCrashReporter` |
| 分析 | 中国大陆：友盟（匿名、可关闭）；海外：Firebase Analytics |
| 日志 | `logger` 包 + 文件 sink；分级；脱敏 |
| 性能 | DevTools + 自建埋点（不依赖境外服务） |
| 远程开关 | 自建配置接口（P1），中国大陆不用 Remote Config |

日志规范：

```
[12:03:41] INFO  socket    connected (attempt=1)
[12:03:42] WARN  tracking  background restricted: OEM battery saver
[12:03:45] ERROR api       GET /api/devices 500 (requestId=...)
```

---

## 13. 后台执行

- 定位：由跟踪引擎的前台服务/后台任务负责，Flutter 侧不常驻。
- 推送：FCM 后台 isolate 只做最小工作（写缓存、更新角标），不初始化 UI。
- JPush 由原生厂商通道拉起，Dart 侧只处理 `extras` 与跳转。
- 同步：前台时同步；后台不主动轮询。
- 生命周期：`AppLifecycleState` 驱动 WebSocket 断开/重连与缓存刷新。

---

## 14. 构建与 Flavor

| Flavor | 用途 | API | 地图 | 推送 | 包名后缀 |
|---|---|---|---|---|---|
| dev | 本地开发 | 可配置 | 高德/无 | jpush/fcm/none | `.dev` |
| staging | 内测 | staging | 高德 | jpush | `.staging` |
| prod-cn | 中国大陆商店 | prod | 高德 | jpush | 无 |
| prod-intl | 海外商店 | prod | flutter_map | fcm | 无 |

```bash
flutter run --flavor dev --dart-define=API_BASE_URL=http://10.0.2.2:8082

flutter build appbundle --flavor prod-cn \
  --dart-define=API_BASE_URL=https://track.example.com \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY=$AMAP_ANDROID_KEY \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=JPUSH_APP_KEY=$JPUSH_APP_KEY
```

- 敏感配置不进仓库；使用 `--dart-define` 或 CI Secrets。
- 中国大陆包不初始化 Firebase（`CRASH_REPORTER=none`、`PUSH_PROVIDER=jpush`）。\n  注意：依赖仍会打包原生库，提审前需做构建隔离（`docs/09` 3.9）。
- 包名后缀需与高德 Key、极光 AppKey、Firebase 应用分别注册。

---

## 15. 关键时序

### 15.1 登录

```
User → LoginScreen → AuthController
  → POST /api/session (cookie)
  → POST /api/session/token
  → SecureStore.write(token)
  → GET /api/session?token (校验/用户信息)
  → LocalDb.upsert(user)
  → router.go('/home/map')
```

### 15.2 实时位置

```
SocketClient.connect(token)
  ← {positions:[最新快照]}
  → LocalDb.upsert(positions)
  → livePositionsProvider (Stream)
  → MapController.merge()
  → MapScreen rebuild (仅变化的 marker)
```

### 15.3 启动跟踪

```
TrackingController.start()
  → PermissionService.ensureTrackingPermissions()
  → TrackingEngine.applyConfig(config)
  → TrackingEngine.start()
  → 前台服务通知
  → state = TrackingRunning
  → 定时刷新 queueSize / lastUpload
```

### 15.4 推送冷启动

```
冷启动（JPush 厂商通道 / FCM）
  → main()：按 flavor 初始化推送 SDK（中国大陆不初始化 Firebase）
  → 读取启动参数，缓存 eventId
  → 恢复会话
  → 登录完成
  → router.go('/event/<id>')
```

> 中国大陆冷启动由 JPush 厂商通道拉起，参数在 `extras`；
> 海外由 FCM `getInitialMessage()` 提供。

---

## 16. 可测试性设计

- `domain` 纯 Dart，可直接单测。
- Repository 接口 + Fake 实现，Widget 测试不依赖网络。
- `TrackingEngine`、`SocketClient`、`Clock`、`MapAdapter` 全部可注入。
- 时间使用 `Clock` 抽象，避免测试中的 `DateTime.now()`。
- 路由守卫可单测（传状态，断言重定向）。

---

## 17. 与现有两个项目的关系

| 现有能力 | 处理方式 |
|---|---|
| Client 的跟踪配置/预设/二维码 | 迁移并扩展（预设、诊断、命名空间） |
| Client 的 `traccar_client_sdk` 封装 | 保留为默认引擎适配器 |
| Client 的 Firebase/推送/深链 | 重构为统一推送抽象，支持事件 + 指令，中国大陆切极光 |
| Manager 的 WebView + JS Bridge | 移除；地图/详情/历史原生实现 |
| Manager 的 Token 存储/生物识别/OAuth | 保留思路，接入统一会话层 |
| Manager 的下载/分享逻辑 | 改为原生导出（GPX/KML/CSV） |
| Web 端 `window.appInterface` 协议 | 仅作为 v2 WebView 报表兜底时保留 |
