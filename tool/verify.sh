#!/usr/bin/env bash
#
# 本地验证：依赖解析 → 代码生成 → 静态分析 → 单元测试。
# 在 Flutter 安装完成、平台工程生成之后运行。
#
# 用法：
#   tool/verify.sh
#
# 说明：
# - 不会安装任何 SDK，也不会修改 lib/ 与 docs/；
# - `flutter gen-l10n` 与 build_runner 失败时不阻断后续分析（首次可跳过）。

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "" >&2
  echo "✗ $1" >&2
  exit 1
}

if ! command -v flutter >/dev/null 2>&1; then
  fail "未找到 flutter。请先安装 Flutter 并加入 PATH（见 docs/10-setup-runbook.md）。"
fi

echo "==> Flutter"
flutter --version || fail "flutter --version 失败"

echo ""
echo "==> flutter pub get"
flutter pub get || fail "依赖解析失败：先检查 pubspec.yaml 版本约束"

echo ""
echo "==> 代码生成（失败不阻断）"
flutter gen-l10n || echo "  ! gen-l10n 失败，稍后手动处理"
if [[ -d lib ]] && grep -rq "part '.*\.g\.dart'" lib 2>/dev/null; then
  dart run build_runner build --delete-conflicting-outputs \
    || echo "  ! build_runner 失败，稍后手动处理"
else
  echo "  跳过 build_runner（暂无 drift 生成文件）"
fi

echo ""
echo "==> flutter analyze"
flutter analyze || fail "静态分析未通过"

echo ""
echo "==> flutter test"
flutter test || fail "单元测试未通过"

echo ""
echo "✓ 验证通过。下一步："
echo "  tool/bootstrap.sh（如尚未生成 android/ios）"
echo "  flutter run --dart-define=...（见 docs/10 第 8、9 节）"
