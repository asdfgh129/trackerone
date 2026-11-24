# 13 · 发布检查清单

> 适用：Android（国内应用商店 + Google Play）与 iOS App Store。
> 建议在提审前 3 天冻结功能，只修 P0。

## 1. 品牌与标识

- [x] `applicationId` / iOS Bundle ID 已统一为 `com.trackerone.app`
- [ ] 更新 `lib/core/config/brand.dart` 中的应用名、支持邮箱、隐私政策 URL
- [ ] 应用图标（Android adaptive icon / iOS AppIcon）与启动页
- [ ] 应用名称在多语言下不截断
- [ ] 高德 Key 与最终包名/Bundle ID 绑定：Android ✅（`3c5c…370f`），iOS 待申请
- [ ] 极光 AppKey / 厂商通道绑定：AppKey ✅（`2e61…1d62`），厂商通道待配置（步骤见 [docs/16](16-push-ops-runbook.md)）

## 2. Android 签名

1. 上传密钥已生成（2026-11-06，只做一次，务必离线备份）：
   - `android/app/upload-keystore.jks`（alias `upload`，RSA 2048，10000 天）
   - `android/key.properties`（随机强密码，已 gitignore）
   - SHA1 见 `docs/15`，用于高德 Android Key
2. 确认 `android/key.properties`、`*.jks` 未被提交；
3. 若更换构建机，从密码库恢复上述两个文件；
4. 构建：

```bash
flutter build appbundle --release \
  --dart-define=FLAVOR=prod \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_ANDROID_KEY=$AMAP_ANDROID_KEY \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=PUSH_GATEWAY_URL=https://push.example.com
```

> ⚠️ `PUSH_GATEWAY_URL` 是推送链路的必经参数：网关靠它接收别名注册，
> **不填则网关会丢弃全部事件**（`no_alias`），App 只能靠 WebSocket 收事件。
> 部署步骤见 [docs/16](16-push-ops-runbook.md)。

5. 校验签名：

```bash
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

> 未配置 `key.properties` 或 `storeFile` 时 release 构建会直接失败（不再回退
> debug 签名）；`tool/release_check.sh` 也会拦截。

## 3. iOS 签名

1. 复制 `ios/ExportOptions.plist.example` 为 `ios/ExportOptions.plist`，
   填入 `teamID` 与分发方式；
2. Xcode 配置自动签名或描述文件；
3. 构建：

```bash
flutter build ipa --release \
  --dart-define=FLAVOR=prod \
  --dart-define=MAP_PROVIDER=amap \
  --dart-define=AMAP_IOS_KEY=$AMAP_IOS_KEY \
  --dart-define=PUSH_PROVIDER=jpush \
  --dart-define=PUSH_GATEWAY_URL=https://push.example.com
```

4. 导出/上传：

```bash
xcrun altool --upload-app --type ios \
  -f build/ios/ipa/*.ipa \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

5. 确认 Info.plist：
   - `NSLocationWhenInUseUsageDescription`
   - `NSLocationAlwaysAndWhenInUseUsageDescription`
   - `NSMotionUsageDescription`（如启用活动识别）
   - `UIBackgroundModes` 包含 `location`，使用推送时包含 `remote-notification`
   - `NSUserTrackingUsageDescription` 只在确实使用 IDFA 时添加（本项目不接入广告）

## 4. 版本与构建号

- [x] `pubspec.yaml` 的 `version` 已递增（语义化，当前 0.4.0+4）；
- [x] Android `versionCode` 由 Flutter 自动生成，确认大于上一版；
- [x] iOS `CFBundleShortVersionString` / `CFBundleVersion` 正确；
- [ ] 构建号写入关于页与诊断日志，便于定位线上问题；
- [ ] 保留 mapping / dSYM 文件用于崩溃符号化。

## 5. 合规与商店材料

- [ ] 隐私政策 URL 可访问，内容覆盖定位、地图、推送、崩溃上报；
- [ ] 个人信息收集清单、第三方 SDK 清单（高德、极光、厂商通道、Firebase）；
- [x] 用户同意隐私政策前不初始化地图/推送/统计 SDK（首启全局弹窗 + 地图独立授权）
- [x] 后台定位单独授权与撤回（`core/privacy/background_location_consent.dart`，
      设置页可关闭；撤回总隐私授权时一并清除并停止后台上报）
- [ ] 新增 81 个 ARB key 的人工翻译：33 种语言当前回落英文（共 2599 条，
      `flutter gen-l10n` 会列出未翻译条目），上架前至少补齐 en 之外的商店主推语言
- [x] 提供账号注销与数据删除入口（已接 `DELETE /api/users/{id}`，服务端策略待确认）
- [ ] APP 备案号、ICP 备案、地图审图号展示在设置/关于页；
- [ ] Android 权限用途说明与隐私弹窗；
- [x] iOS 隐私清单 `PrivacyInfo.xcprivacy` 已添加并加入 Runner 资源；App Store 隐私问卷待填写
- [ ] 应用截图、描述、关键词、年龄分级、联系方式；
- [ ] 国内商店软著/资质（按各商店要求）。

## 6. 功能与质量门禁

```bash
# 统一自检：ARB 完整性、占位符、配置、analyze、test
tool/release_check.sh

# 构建验证
flutter build apk --debug
flutter build ios --simulator --no-codesign
```

- [x] `dart analyze` 0 issue；
- [x] `flutter test` 全绿（117 项）；
- [x] 35 个 ARB 文件 key 与占位符一致；
- [ ] 真机测试矩阵（docs/11）P0 用例通过；
- [ ] 后台上报 24h / 72h 数据达标；
- [ ] 500/1000 设备地图 ≥ 30fps（或记录明确风险）；
- [ ] 冷启动 < 2.5s；
- [ ] 崩溃率、ANR 在灰度期无异常；
- [ ] 弱网、离线、权限撤销、Token 失效均有可恢复路径；
- [x] 消息中心（`/inbox`）：空态 / 错误态 / 网关未配置 / 离线队列均有处理；
- [x] 消息网关接口与存储已实现（`GET/POST /v1/messages`、ACK、注销清理，
      见 `server/README.md` 2.4 与 [docs/17](17-adr-downlink.md)）；Go 测试通过；
- [x] 指令结果链路（Traccar `commandResult` → 收件箱）与撤回/重发/审计接口已实现；
- [ ] 部署网关并完成收件箱真机联调（App 侧可用 `--dart-define=INBOX_DEMO=true` 先走通交互）。

## 7. 性能基线记录

| 指标 | 阈值 | 实测 | 设备 |
|---|---|---|---|
| 冷启动 | < 2.5s |  |  |
| 地图 500 设备 | ≥ 30fps |  |  |
| 地图 1000 设备 | ≥ 30fps / < 300MB |  |  |
| 历史 10k 点首屏 | < 3s |  |  |
| 后台上报 24h 耗电 | ≤ 6% |  |  |
| 2h 前台地图内存增长 | < 20% |  |  |

> 使用 `--dart-define=SIMULATE_DEVICES=500` 或 `1000` 复现地图压力测试；
> 该参数只注入本地模拟数据，不写入缓存，禁止进入生产包。

## 8. 发布与回滚

1. 先发内部测试轨道 / 国内商店灰度 10%；
2. 观察 24–48 小时崩溃率、推送送达率、后台上报断点；
3. 无异常再逐步放量；
4. 准备上一版本安装包与服务器兼容回滚方案；
5. 发布后 7 天保留值班与日志查询通道。

## 9. 发布前最后检查

- [ ] 关闭调试入口与 `SIMULATE_DEVICES`，并确认正式包未带 `INBOX_DEMO=true`；
- [x] 确认 `PUSH_PROVIDER` / `MAP_PROVIDER` 为生产值（默认 `jpush` / `amap`）；
- [ ] 正式包必须带 `--dart-define=PUSH_GATEWAY_URL=<网关域名>`，否则网关丢弃全部事件、
      消息中心只显示「未配置消息网关」
- [ ] 确认无测试服务器地址、测试账号、测试 Key（`Brand.demoServerUrl` 仍为 demo）；
- [ ] 确认日志不输出 Token、密码、完整位置；
- [x] 确认 `tool/release_check.sh` 通过；
- [ ] 归档构建产物、mapping、dSYM、测试矩阵结果与签名证书备份。
