#!/usr/bin/env bash
#
# 生成 Flutter 平台工程（android / ios），避免覆盖已有的 lib/ 与文档。
#
# 用法：
#   tool/bootstrap.sh              # 生成 android + ios
#   PLATFORMS=android tool/bootstrap.sh
#   FORCE=1 tool/bootstrap.sh      # 已存在时强制重新生成（会覆盖平台配置！）
#
# 可用环境变量：
#   ORG       反向域名，默认 com.example
#   APP_NAME  工程名，默认 trackerone
#   PLATFORMS 平台列表，默认 android,ios
#   FORCE     1 = 覆盖已存在的平台目录

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORG="${ORG:-com.example}"
APP_NAME="${APP_NAME:-trackerone}"
PLATFORMS="${PLATFORMS:-android,ios}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "错误：未找到 flutter。请先安装 Flutter 并加入 PATH。" >&2
  echo "参考 docs/10-setup-runbook.md 第 2 节。" >&2
  exit 1
fi

echo "==> Flutter 版本"
flutter --version

if [[ -d "$ROOT/android" || -d "$ROOT/ios" ]]; then
  if [[ "${FORCE:-0}" != "1" ]]; then
    echo "" >&2
    echo "android/ 或 ios/ 已存在，已停止以避免覆盖你手改过的原生配置。" >&2
    echo "如确认要重新生成，执行：FORCE=1 tool/bootstrap.sh" >&2
    exit 1
  fi
  echo "==> FORCE=1：将覆盖现有平台工程"
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/trackerone-platform.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "==> 在临时目录生成平台工程：$TMP_DIR"
flutter create \
  --platforms="$PLATFORMS" \
  --org "$ORG" \
  --project-name "$APP_NAME" \
  --no-pub \
  "$TMP_DIR/platform" >/dev/null

for platform in ${PLATFORMS//,/ }; do
  rm -rf "$ROOT/$platform"
  cp -R "$TMP_DIR/platform/$platform" "$ROOT/$platform"
  echo "    已复制 $platform/"
done

echo ""
echo "==> 完成。平台工程位置：$ROOT/{$PLATFORMS}"
echo "下一步："
echo "  flutter pub get"
echo "  flutter analyze"
echo "  flutter test"
