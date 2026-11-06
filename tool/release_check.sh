#!/usr/bin/env bash
# TrackerOne 发布前自检。用法：
#   tool/release_check.sh              # 全量：ARB + analyze + test
#   tool/release_check.sh --fast       # 只做配置/ARB 检查
#   SKIP_TEST=1 tool/release_check.sh  # 跳过测试
set -euo pipefail
cd "$(dirname "$0")/.."

FAST=0
if [[ "${1:-}" == "--fast" ]]; then FAST=1; fi

fail=0
step() { printf '\n== %s ==\n' "$1"; }
ok() { printf '  ✅ %s\n' "$1"; }
warn() { printf '  ⚠️  %s\n' "$1"; }
bad() { printf '  ❌ %s\n' "$1"; fail=1; }

step "ARB / 语言"
python3 - <<'PY' || exit 1
import json, os, re, sys
root = 'lib/l10n'
template = json.load(open(os.path.join(root, 'app_en.arb'), encoding='utf-8'))
keys = {k for k in template if not k.startswith('@')}
langs = ['ar','ca','cs','de','el','en','es','et','fa','fi','fr','he','hr','id','it','ja','kab','ko','lt','lv','nb','nl','pl','pt','pt_BR','ru','sk','sl','sr','th','tr','uk','vi','zh','zh_TW']
missing = []
problems = []
ph = re.compile(r'\{[a-zA-Z0-9_]+\}')
for lang in langs:
    path = os.path.join(root, f'app_{lang}.arb')
    if not os.path.exists(path):
        missing.append(lang)
        continue
    try:
        data = json.load(open(path, encoding='utf-8'))
    except Exception as error:
        problems.append(f'{lang}: invalid JSON: {error}')
        continue
    local = {k for k in data if not k.startswith('@')}
    if local != keys:
        problems.append(f'{lang}: missing {sorted(keys-local)[:5]} extra {sorted(local-keys)[:5]}')
    for key in keys & local:
        source = set(ph.findall(template[key]))
        target = set(ph.findall(str(data[key])))
        if source != target:
            problems.append(f'{lang}.{key}: placeholders {source} != {target}')
        value = str(data[key])
        if not value.strip():
            problems.append(f'{lang}.{key}: empty value')
        if 'QZX' in value:
            problems.append(f'{lang}.{key}: leaked sentinel')
print(f'  语言文件: {len(langs)} 个目标')
if missing:
    print(f'  ❌ 缺少: {", ".join(missing)}')
    sys.exit(1)
if problems:
    print('  ❌ 问题:')
    for item in problems[:30]:
        print('    -', item)
    sys.exit(1)
print('  ✅ 35 语言 key 与占位符一致')
PY

step "构建配置"
if [[ ! -f android/key.properties ]]; then
  bad "android/key.properties 缺失：release 构建会直接失败（不再回退 debug 签名）"
else
  ok "android/key.properties 已存在"
fi
if grep -q 'com.example.trackerone' android/app/build.gradle.kts; then
  bad "applicationId 仍是占位包名 com.example.trackerone"
elif ! grep -q 'applicationId = "com.trackerone.app"' android/app/build.gradle.kts; then
  bad "applicationId 未设置为 com.trackerone.app"
else
  ok "applicationId 已替换为 com.trackerone.app"
fi
if grep -rq 'com.example.trackerone' ios/Runner.xcodeproj/project.pbxproj; then
  bad "iOS Bundle ID 仍是 com.example.trackerone"
elif ! grep -q 'PRODUCT_BUNDLE_IDENTIFIER = com.trackerone.app;' ios/Runner.xcodeproj/project.pbxproj; then
  bad "iOS Bundle ID 未设置为 com.trackerone.app"
else
  ok "iOS Bundle ID 已替换为 com.trackerone.app"
fi
if grep -rq 'YOUR_TEAM_ID' ios/ExportOptions.plist 2>/dev/null; then
  bad "ios/ExportOptions.plist 仍含 YOUR_TEAM_ID"
else
  warn "请确认已配置 iOS 签名团队（ios/ExportOptions.plist）"
fi

step "敏感文件"
for file in android/key.properties android/app/upload-keystore.jks ios/ExportOptions.plist; do
  if [[ -f "$file" ]] && ! grep -qE "^${file}$" .gitignore 2>/dev/null; then
    if git check-ignore -q "$file" 2>/dev/null; then
      ok "$file 已被 git 忽略"
    else
      bad "$file 未被 git 忽略"
    fi
  fi
done

if [[ "$FAST" == "1" ]]; then
  step "完成"
  [[ "$fail" == "0" ]] && ok "快速检查通过" || bad "存在阻断项"
  exit "$fail"
fi

step "静态分析"
if flutter analyze; then ok "flutter analyze"; else bad "flutter analyze"; fi

if [[ "${SKIP_TEST:-0}" != "1" ]]; then
  step "测试"
  if flutter test; then ok "flutter test"; else bad "flutter test"; fi
fi

step "完成"
if [[ "$fail" == "0" ]]; then
  ok "发布自检通过"
else
  bad "存在阻断项，请修复后重试"
fi
exit "$fail"
