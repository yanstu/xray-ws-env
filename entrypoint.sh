#!/bin/sh
set -eu
: "${UUID:?UUID env required}"
PORT="${PORT:-8080}"
WS_PATH="${WS_PATH:-/ws}"
XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
MAX_ATTEMPTS="${XRAY_MAX_ATTEMPTS:-5}"
BASE_DELAY="${XRAY_RETRY_DELAY:-2}"
HEALTHY="${XRAY_HEALTHY_SECONDS:-30}"

case "$MAX_ATTEMPTS" in
  ''|*[!0-9]*) echo "XRAY_MAX_ATTEMPTS must be a positive integer" >&2; exit 1 ;;
esac
if [ "$MAX_ATTEMPTS" -lt 1 ]; then
  echo "XRAY_MAX_ATTEMPTS must be a positive integer" >&2
  exit 1
fi

cat > /tmp/config.json <<JSON
{"log":{"loglevel":"warning"},
 "dns":{"servers":["1.1.1.1","8.8.8.8"],"queryStrategy":"UseIPv4"},
 "inbounds":[{"port":${PORT},"listen":"0.0.0.0","protocol":"vless",
  "settings":{"clients":[{"id":"${UUID}"}],"decryption":"none"},
  "streamSettings":{"network":"ws","wsSettings":{"path":"${WS_PATH}"}}}],
 "outbounds":[{"protocol":"freedom","tag":"direct","settings":{"domainStrategy":"UseIPv4"}},{"protocol":"blackhole","tag":"block"}],
 "routing":{"rules":[{"type":"field","ip":["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.168.0.0/16","::1/128","fc00::/7","fe80::/10"],"outboundTag":"block"}]}}
JSON

pid=""
stop=0
on_stop() {
  stop=1
  if [ -n "$pid" ]; then
    kill -TERM "$pid" 2>/dev/null || true
  fi
}
trap on_stop TERM INT

attempt=0
delay="$BASE_DELAY"
while :; do
  attempt=$((attempt + 1))
  started=$(date +%s)
  "$XRAY_BIN" run -c /tmp/config.json &
  pid=$!
  set +e
  wait "$pid"
  code=$?
  set -e
  pid=""
  if [ "$stop" -eq 1 ]; then
    exit 0
  fi
  if [ "$code" -eq 0 ]; then
    exit 0
  fi
  now=$(date +%s)
  if [ $((now - started)) -ge "$HEALTHY" ]; then
    attempt=1
    delay="$BASE_DELAY"
  fi
  if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
    echo "xray exited ${code}; stopped after ${attempt} attempts" >&2
    exit "$code"
  fi
  echo "xray exited ${code}; retrying in ${delay}s (${attempt}/${MAX_ATTEMPTS})" >&2
  sleep "$delay"
  if [ "$delay" -gt 0 ]; then
    delay=$((delay * 2))
    if [ "$delay" -gt 30 ]; then
      delay=30
    fi
  fi
done
