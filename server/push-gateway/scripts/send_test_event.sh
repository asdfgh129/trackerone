#!/usr/bin/env bash
# 模拟 Traccar webhook 调用推送网关，用于本地联调。
#
#   GATEWAY_URL=https://push.example.com SECRET=xxx ./send_test_event.sh
#
# 环境变量：
#   GATEWAY_URL  网关地址，默认 http://127.0.0.1:8080
#   SECRET       与网关 TRACCAR_WEBHOOK_SECRET 一致
#   EVENT_ID     事件 id（重复测试幂等时复用同一个）
#   ALIAS        已注册的别名，默认 u42@1
#   USER_ID      Traccar 用户 id，默认 42
set -euo pipefail

GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8080}"
SECRET="${SECRET:-dev-secret}"
EVENT_ID="${EVENT_ID:-900001}"
ALIAS="${ALIAS:-u42@1}"
USER_ID="${USER_ID:-42}"

BODY=$(cat <<JSON
{"version":1,"userId":${USER_ID},"userEmail":"tester@example.com","deviceId":1,
 "deviceName":"测试车","uniqueId":"test-device",
 "event":{"id":${EVENT_ID},"deviceId":1,"type":"geofenceEnter",
   "eventTime":"2026-01-01T08:15:00.000+00:00","attributes":{"geofenceName":"公司"}},
 "position":{"id":1,"deviceId":1,"latitude":39.9042,"longitude":116.4074,
   "fixTime":"2026-01-01T08:14:58.000+00:00","attributes":{"batteryLevel":78}},
 "message":{"title":"围栏进入","body":"测试车 进入「公司」"},
 "issuedAt":1767225600000}
JSON
)

# 先确保别名存在（网关若配置了 TRACCAR_BASE_URL，需要真实 Traccar Token）。
if [ "${REGISTER_ALIAS:-0}" = "1" ]; then
  curl -sS -X POST "${GATEWAY_URL}/v1/aliases" \
    -H "Authorization: Bearer ${TRACCAR_TOKEN:?需要设置 TRACCAR_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"alias\":\"${ALIAS}\",\"platform\":\"android\",\"vendor\":\"xiaomi\",\"appVersion\":\"0.4.0\",\"deviceModel\":\"Xiaomi 14\"}"
  echo
fi

SIGNATURE=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $2}')

curl -sS -X POST "${GATEWAY_URL}/v1/events" \
  -H 'Content-Type: application/json' \
  -H "X-Traccar-Signature: sha256=${SIGNATURE}" \
  -H 'X-Locale: zh' \
  -d "$BODY"
echo
