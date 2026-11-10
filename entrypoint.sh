#!/bin/sh
set -e
: "${UUID:?UUID env required}"
PORT="${PORT:-8080}"
WS_PATH="${WS_PATH:-/ws}"
cat > /tmp/config.json <<JSON
{"log":{"loglevel":"warning"},
 "dns":{"servers":["1.1.1.1","8.8.8.8"],"queryStrategy":"UseIPv4"},
 "inbounds":[{"port":${PORT},"listen":"0.0.0.0","protocol":"vless",
  "settings":{"clients":[{"id":"${UUID}"}],"decryption":"none"},
  "streamSettings":{"network":"ws","wsSettings":{"path":"${WS_PATH}"}}}],
 "outbounds":[{"protocol":"freedom","tag":"direct","settings":{"domainStrategy":"UseIPv4"}},{"protocol":"blackhole","tag":"block"}],
 "routing":{"rules":[{"type":"field","ip":["0.0.0.0/8","10.0.0.0/8","100.64.0.0/10","127.0.0.0/8","169.254.0.0/16","172.16.0.0/12","192.168.0.0/16","::1/128","fc00::/7","fe80::/10"],"outboundTag":"block"}]}}
JSON
exec /usr/local/bin/xray run -c /tmp/config.json
