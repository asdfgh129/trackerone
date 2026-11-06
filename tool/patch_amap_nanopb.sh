#!/usr/bin/env bash
#
# 高德 iOS SDK 的 MAMapKit 静态库内嵌了一份 nanopb，导出
#   _pb_istream_from_buffer / _pb_ostream_from_buffer / _pb_release
# 三个全局符号。Firebase（Crashlytics/Messaging/Analytics）也会引入 nanopb，
# 链接 Runner 时就会报 “duplicate symbol”。
#
# 这里用 nmedit 把高德那份改成局部符号：高德内部调用不受影响，也不会再和
# Firebase 的全局符号冲突。pod install 会覆盖 Pods 目录，因此由 Podfile 的
# post_install 每次自动调用。
#
# 用法：tool/patch_amap_nanopb.sh <path-to-MAMapKit-binary>

set -euo pipefail

FRAMEWORK="${1:-}"
if [[ -z "$FRAMEWORK" || ! -f "$FRAMEWORK" ]]; then
  echo "patch_amap_nanopb: framework binary not found: ${FRAMEWORK:-<empty>}" >&2
  exit 1
fi

SYMBOLS="$(mktemp)"
WORK="$(mktemp -d)"
trap 'rm -rf "$SYMBOLS" "$WORK"' EXIT

TARGET_SYMBOLS=(
  _pb_istream_from_buffer
  _pb_ostream_from_buffer
  _pb_release
)

ARCHS="$(lipo -archs "$FRAMEWORK")"
THIN_FILES=()
NEEDS_PATCH=0

for arch in $ARCHS; do
  thin="$WORK/$arch.a"
  lipo "$FRAMEWORK" -thin "$arch" -output "$thin"

  # nmedit 只接受“当前仍是全局”的符号；补丁已生效时直接跳过。
  globals="$(nm -gU "$thin" 2>/dev/null | awk '{print $NF}')"
  : > "$SYMBOLS"
  for symbol in "${TARGET_SYMBOLS[@]}"; do
    if grep -qx "$symbol" <<< "$globals"; then
      printf '%s\n' "$symbol" >> "$SYMBOLS"
      NEEDS_PATCH=1
    fi
  done
  if [[ -s "$SYMBOLS" ]]; then
    nmedit -R "$SYMBOLS" "$thin"
  fi
  THIN_FILES+=("$thin")
done

if [[ "$NEEDS_PATCH" -eq 0 ]]; then
  echo "patch_amap_nanopb: already patched (${ARCHS// /, })"
  exit 0
fi

lipo -create "${THIN_FILES[@]}" -output "$FRAMEWORK"

# 校验：全局符号里不应再出现这三个。
if nm -gU "$FRAMEWORK" 2>/dev/null | grep -Eq ' _pb_(istream_from_buffer|ostream_from_buffer|release)$'; then
  echo "patch_amap_nanopb: nanopb symbols still global" >&2
  exit 1
fi

echo "patch_amap_nanopb: localized nanopb symbols for ${ARCHS// /, }"
