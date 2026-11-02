# 07 · 质量、构建与发布

## 1. 质量目标

| 指标 | 目标 |
|---|---|
| 崩溃自由用户率 | ≥ 99.5% |
| ANR 率 | < 0.3% |
| 上报成功率（在线） | ≥ 98% |
| 位置端到端延迟 P95 | < 10s |
| 地图帧率 | 60fps（常规） |
| 冷启动 | < 2.5s |
| 单元测试覆盖（domain/application） | ≥ 70% |
| 关键流程 E2E | 100% 覆盖 |

## 2. 测试分层

```
        ┌──────────────┐
        │  现场测试     │  真机 24h/72h、国产 ROM
        ├──────────────┤
        │  E2E / 集成   │  登录、上报、地图、推送、指令
        ├──────────────┤
        │  Widget       │  页面状态、交互、无障碍
        ├──────────────┤
        │  单元测试      │  领域模型、仓库、解析、状态机
        └──────────────┘
```

### 2.1 单元测试

重点：

- `TrackingConfig` 映射与预设。
- Position/Event/Device 解析（含异常字段）。
- WebSocket 消息合并、去重、乱序。
- 历史抽稀、停留识别、距离/速度单位换算。
- 路由守卫。
- 错误映射（401/403/5xx/超时）。
- 队列重放与幂等。

工具：`flutter_test`、`mocktail`、`fake_async`。

### 2.2 Widget 测试

- 地图页：空态、离线、加载、错误、权限缺失。
- 跟踪面板：五种状态切换。
- 历史：时间轴拖动、播放、导出入口。
- 事件：筛选、已读、深链。
- 诊断：结论与修复按钮。

### 2.3 集成 / E2E

使用 `integration_test` + 测试服务器（Docker Traccar + 预置账号/设备）。

| 用例 | 步骤 |
|---|---|
| 首次引导 | 启动 → 选模式 → 配服务器 → 登录 → 授权 → 首页 |
| 本机上报 | 开始 → 模拟位置 → 服务端收到 → 地图出现 |
| 历史回放 | 选日期 → 播放 → 暂停 → 拖动 → 导出 |
| 推送直达 | 极光后台下发（或 curl 网关）→ 后台/冷启动点击 → 事件页 |
| 指令 | 发送单次定位 → 状态变化 |
| 断网恢复 | 断网 → 移动 → 恢复 → 补点 |
| 退出登录 | 清理 Token/缓存 → 回登录 |

### 2.4 现场测试

| 项 | 要求 |
|---|---|
| 设备 | ≥ 6 台：Pixel、三星、小米、华为、OPPO/vivo、iPhone |
| 系统 | Android 24/31/34/36；iOS 15/17/18 |
| 场景 | 步行、驾车、静止、地下车库、地铁 |
| 时长 | 24h 全量；核心设备 72h |
| 记录 | 点数、间隔、耗电、崩溃、队列、ROM 限制 |

## 3. 测试矩阵

| 维度 | 取值 |
|---|---|
| 平台 | Android / iOS |
| 网络 | Wi-Fi / 4G / 5G / 弱网 / 离线 / 切换 |
| 生命周期 | 前台 / 后台 / 锁屏 / 强杀 / 重启 |
| 权限 | 全部允许 / 部分拒绝 / 永久拒绝 / 运行中撤销 |
| 服务器 | 6.0 / 6.16 / 反代 / 自签名 / 不可达 |
| 数据量 | 0 / 10 / 100 / 1000 设备；7 天 / 30 天历史 |
| 账号 | 管理员 / 普通用户 / 只读 |
| 语言 | 中文 / 英文 / RTL（阿拉伯语） |
| 主题 | 浅色 / 深色 / 跟随系统 |
| 字体 | 默认 / 200% |

## 4. 性能与稳定性

### 4.1 基准

| 场景 | 工具 | 阈值 |
|---|---|---|
| 冷启动 | `flutter run --profile` + DevTools | < 2.5s |
| 地图 500 设备 | DevTools timeline | ≥ 30fps |
| 地图 1000 设备 | 同上 | ≥ 30fps，内存 < 300MB |
| 历史 10k 点 | 同上 | 首屏 < 3s |
| 长时间运行 | 2h 前台地图 | 内存增长 < 20% |
| 后台上报 24h | 电量统计 | ≤ 6% |

### 4.2 优化清单

- 地图 marker 复用，避免每帧重建。
- WebSocket 消息批量合并（16–50ms 节流）。
- 历史点抽稀与分段加载。
- 图片/图标缓存。
- 列表 `itemBuilder` + 固定 extent。
- 避免在 build 中做解析/排序。
- 包体：R8/ProGuard、资源压缩、按架构拆分（如需要）。

## 5. 安全

### 5.1 检查清单（OWASP MASVS-L1）

- [ ] 无硬编码密钥/Token/服务器凭据。
- [ ] Token 仅存 Secure Storage。
- [ ] 日志无敏感信息（Token、密码、精确坐标）。
- [ ] 强制 HTTPS；自签名需显式确认。
- [ ] 证书校验未被全局关闭。
- [ ] 生物识别用于读取 Token。
- [ ] 退出登录清理 Token、缓存、Cookie。
- [ ] 深链参数校验（防注入/开放重定向）。
- [ ] 未同意隐私政策前，不初始化高德/极光/统计 SDK（抓包验证）。
- [ ] WebView（如启用）禁用文件访问与任意 JS 桥。
- [ ] 依赖漏洞扫描（`flutter pub outdated` + Dependabot）。

### 5.2 隐私

- 隐私政策覆盖：位置、设备信息、推送标识、崩溃日志、分析。
- 首次上报前明确告知接收方（服务器地址）。
- 提供数据删除与撤回同意。
- 分析事件不含位置与账号。

## 6. CI/CD

### 6.1 GitHub Actions（示意）

```yaml
name: CI
on:
  pull_request:
  push:
    branches: [main]

jobs:
  quality:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          cache: true
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze
      - run: flutter test --coverage
      - uses: codecov/codecov-action@v4

  build-android:
    needs: quality
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 17 }
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build appbundle --flavor prod-cn \
          --dart-define=API_BASE_URL=${{ secrets.API_BASE_URL }} \
          --dart-define=MAP_PROVIDER=amap \
          --dart-define=AMAP_ANDROID_KEY=${{ secrets.AMAP_ANDROID_KEY }} \
          --dart-define=PUSH_PROVIDER=jpush \
          --dart-define=JPUSH_APP_KEY=${{ secrets.JPUSH_APP_KEY }}
      - uses: actions/upload-artifact@v4
        with: { name: android-aab, path: build/app/outputs/bundle/prodCnRelease/ }

  build-ios:
    needs: quality
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build ipa --flavor prod --export-options-plist=ios/ExportOptions.plist
```

### 6.2 分支与发布

| 分支 | 用途 |
|---|---|
| `main` | 可发布；受保护 |
| `feat/*` | 功能 |
| `fix/*` | 修复 |
| `release/*` | 发布冻结 |

- PR 必须通过 analyze + test + 1 人 review。
- 版本号：`MAJOR.MINOR.PATCH+BUILD`；每次商店构建递增 BUILD。
- Tag：`v1.0.0` 触发发布流水线。

### 6.3 环境

| Flavor | 包名后缀 | 地图 | 推送 | 服务器 |
|---|---|---|---|---|
| dev | `.dev` | 高德/无 | jpush/fcm/none | 本地/测试 |
| staging | `.staging` | 高德 | jpush | 预发 |
| prod-cn | 无 | 高德 | jpush | 生产 |
| prod-intl | 无 | flutter_map | fcm | 生产 |

签名密钥存 CI Secrets，禁止入仓。

## 7. 发布流程

### 7.1 Android

1. `flutter build appbundle --flavor prod`
2. 内部测试轨道（Internal testing）
3. 封闭测试（Closed testing）≥ 3 天
4. 生产发布（分阶段 5% → 20% → 50% → 100%）

### 7.2 iOS

1. `flutter build ipa`
2. TestFlight 内测
3. 提交审核（附后台定位说明与演示视频）
4. 分阶段发布（Phased Release）

### 7.3 发布检查清单

- [ ] 版本号/构建号正确
- [ ] 图标、启动图、截图、描述更新
- [ ] 隐私政策 URL 可访问
- [ ] 数据安全表单与实现一致
- [ ] 后台定位申报材料（Google Play / 国内商店）
- [ ] APP 备案号已获取并在「关于」页展示
- [ ] 隐私政策、SDK 清单、个人信息收集清单已上线
- [ ] 地图审图号已展示
- [ ] 通知权限文案
- [ ] 深链/Universal Link 验证
- [ ] 推送证书/密钥有效（极光 + 厂商通道）
- [ ] 崩溃符号上传
- [ ] 测试账号可用
- [ ] 回滚方案确认

## 8. 商店合规

> 首发中国大陆，优先执行 **8.3 中国大陆**；8.1 / 8.2 适用于海外包。

### 8.1 Google Play（仅海外 / prod-intl）

**后台定位**（必须申报）：

- 说明核心功能：用户主动开启的手机位置跟踪。
- 演示视频：从开启 → 锁屏 → 服务端收到位置。
- 权限声明：`ACCESS_BACKGROUND_LOCATION` 的使用场景。
- 隐私政策中明确后台采集。

**其他**

- 数据安全表单：位置（收集、可选、加密传输）、设备 ID、崩溃日志。
- 前台服务类型：`location`。
- 目标 API 级别符合当年要求。

### 8.2 App Store（iOS，国内/海外）

- `UIBackgroundModes: location` 的用途说明。
- App Privacy：精确位置、设备 ID、崩溃数据。
- 审核备注：如何测试后台跟踪（测试账号 + 步骤）。
- 若包含 WebView，需确保非"纯网页壳"（本项目原生为主，风险低）。

### 8.3 中国大陆（首发）

> 完整清单见 [`docs/09-china-launch.md`](09-china-launch.md)。

| 项 | 要求 |
|---|---|
| APP 备案 | 先备案后上架；备案号在「关于」页展示 |
| 域名 ICP | 服务端域名在境内必须备案 |
| 地图 | 高德（甲级资质），GCJ-02，展示审图号，不缓存/转售瓦片 |
| 推送 | 极光 + 厂商通道；隐私政策列明 SDK |
| 个人信息 | 单独同意（敏感个人信息）、收集清单、SDK 清单、删除权 |
| 权限时机 | 不得启动即申请后台定位 |
| 商店 | 华为/小米/OPPO/vivo/应用宝/荣耀 逐一适配 |
| 软著 | 按商店要求，提前 30–60 天申请 |
| 主体 | 企业主体才能开通全部厂商通道 |

**隐私自检（上线前必做）：**

1. 用抓包工具确认：未点「同意」前无高德/极光/统计请求；
2. 关闭所有权限后，App 仍可浏览缓存与设置；
3. 关闭上报后，常驻通知消失、无位置请求；
4. 「删除数据」后重启，无残留位置；
5. 隐私政策中的 SDK 清单与 `pubspec.yaml` 实际依赖一致。

## 9. 监控与回滚

### 9.1 上线监控

| 指标 | 来源 | 告警阈值 |
|---|---|---|
| 崩溃率 | Bugly / Crashlytics | > 1% 立即 |
| ANR | Play Console | > 0.5% |
| 登录失败率 | 分析 | > 10% |
| 上报成功率 | 分析/服务端 | < 95% |
| WS 连接失败率 | 分析 | > 15% |
| 审核状态 | 商店 | 变化即通知 |

### 9.2 回滚

- Android：暂停分阶段发布；必要时发布修复版。
- iOS：暂停 Phased Release；紧急版本走审核加急。
- 服务端兼容问题：远程开关降级相关功能（P1）。
- 数据问题：提供本地缓存清理入口，不发版也可恢复。

## 10. 文档与交接

必须随代码维护：

- `README.md`：快速开始、目录、构建。
- `docs/`：本套文档。
- `CHANGELOG.md`：版本变更。
- `docs/adr/`：架构决策记录（可从 08 拆分）。
- 发布手册：签名、账号、商店后台、证书到期时间。
- 应急手册：崩溃、推送失败、审核被拒、服务器不可达。
