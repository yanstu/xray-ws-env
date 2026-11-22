#!/bin/sh
# Exercises download retries and the entrypoint restart loop with fakes.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

python3 - "$tmp/payload.zip" <<'PY'
import sys, zipfile
path = sys.argv[1]
with zipfile.ZipFile(path, "w") as zf:
    zf.writestr("xray", "#!/bin/sh\necho real-xray\n")
PY

cat > "$tmp/wget" <<'EOF'
#!/bin/sh
state=${WGET_STATE:?}
out=""
prev=""
url=""
for a in "$@"; do
  if [ "$prev" = "-O" ]; then
    out=$a
  fi
  prev=$a
  url=$a
done
n=$(cat "$state")
n=$((n + 1))
printf '%s\n' "$n" > "$state"
mode=${WGET_MODE:?}
case "$mode" in
  fail-twice)
    if [ "$n" -le 2 ]; then
      exit 1
    fi
    ;;
  bad-then-good)
    if [ "$n" -le 2 ]; then
      printf 'not-a-zip' > "$out"
      if echo "$url" | grep -q '\.dgst$'; then
        printf 'SHA2-256= 0000\n' > "$out"
      fi
      exit 0
    fi
    ;;
  always-fail)
    exit 1
    ;;
  *)
    echo "unknown WGET_MODE=$mode" >&2
    exit 2
    ;;
esac
if echo "$url" | grep -q '\.dgst$'; then
  sum=$(sha256sum "$WGET_ZIP" | cut -d' ' -f1)
  printf 'SHA2-256= %s\n' "$sum" > "$out"
else
  cp "$WGET_ZIP" "$out"
fi
exit 0
EOF
chmod +x "$tmp/wget"

run_download() {
  mode=$1
  attempts=$2
  dest=$3
  state=$4
  printf '0\n' > "$state"
  set +e
  PATH="$tmp:$PATH" \
    WGET_STATE="$state" \
    WGET_MODE="$mode" \
    WGET_ZIP="$tmp/payload.zip" \
    XRAY_VERSION=v26.10.31 \
    DOWNLOAD_ATTEMPTS="$attempts" \
    DOWNLOAD_RETRY_SLEEP=0 \
    XRAY_DEST="$dest" \
    XRAY_WORKDIR="$tmp/work-$mode" \
    sh "$root/download-xray.sh"
  code=$?
  set -e
  return "$code"
}

dest="$tmp/bin/xray"
if run_download fail-twice 5 "$dest" "$tmp/wget-count"; then
  :
else
  fail "download should succeed after two failed attempts"
fi
calls=$(cat "$tmp/wget-count")
# Two failed zip fetches, then zip + digest.
if [ "$calls" -ne 4 ]; then
  fail "expected 4 wget calls after two failures, got $calls"
fi
test -x "$dest" || fail "binary was not installed"
"$dest" | grep -q real-xray || fail "installed binary did not run"

dest2="$tmp/bin2/xray"
if run_download bad-then-good 5 "$dest2" "$tmp/wget-count-2"; then
  :
else
  fail "download should retry after a checksum mismatch"
fi
test -x "$dest2" || fail "binary missing after checksum retry"

dest3="$tmp/bin3/xray"
if run_download always-fail 3 "$dest3" "$tmp/wget-count-3"; then
  fail "download should fail when every attempt fails"
fi
test ! -e "$dest3" || fail "binary should not exist after a failed download"
calls=$(cat "$tmp/wget-count-3")
if [ "$calls" -ne 3 ]; then
  fail "expected 3 wget calls when all attempts fail, got $calls"
fi

cat > "$tmp/xray-fail" <<'EOF'
#!/bin/sh
state=${XRAY_STATE:?}
n=$(cat "$state")
n=$((n + 1))
printf '%s\n' "$n" > "$state"
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' /tmp/config.json
exit 7
EOF
chmod +x "$tmp/xray-fail"

printf '0\n' > "$tmp/xray-count"
set +e
UUID=11111111-1111-1111-1111-111111111111 \
  PORT=8080 \
  WS_PATH=/ws \
  XRAY_BIN="$tmp/xray-fail" \
  XRAY_STATE="$tmp/xray-count" \
  XRAY_MAX_ATTEMPTS=3 \
  XRAY_RETRY_DELAY=0 \
  sh "$root/entrypoint.sh"
code=$?
set -e
if [ "$code" -ne 7 ]; then
  fail "entrypoint should exit 7 after giving up, got $code"
fi
runs=$(cat "$tmp/xray-count")
if [ "$runs" -ne 3 ]; then
  fail "expected 3 xray starts, got $runs"
fi

cat > "$tmp/xray-ok" <<'EOF'
#!/bin/sh
state=${XRAY_STATE:?}
n=$(cat "$state")
n=$((n + 1))
printf '%s\n' "$n" > "$state"
exit 0
EOF
chmod +x "$tmp/xray-ok"
printf '0\n' > "$tmp/xray-ok-count"
UUID=11111111-1111-1111-1111-111111111111 \
  XRAY_BIN="$tmp/xray-ok" \
  XRAY_STATE="$tmp/xray-ok-count" \
  XRAY_MAX_ATTEMPTS=5 \
  XRAY_RETRY_DELAY=0 \
  sh "$root/entrypoint.sh"
runs=$(cat "$tmp/xray-ok-count")
if [ "$runs" -ne 1 ]; then
  fail "clean exit should not retry, got $runs starts"
fi

cat > "$tmp/xray-sleep" <<'EOF'
#!/bin/sh
state=${XRAY_STATE:?}
n=$(cat "$state")
n=$((n + 1))
printf '%s\n' "$n" > "$state"
trap 'exit 0' TERM INT
sleep 30
EOF
chmod +x "$tmp/xray-sleep"
printf '0\n' > "$tmp/xray-sleep-count"
UUID=11111111-1111-1111-1111-111111111111 \
  XRAY_BIN="$tmp/xray-sleep" \
  XRAY_STATE="$tmp/xray-sleep-count" \
  XRAY_MAX_ATTEMPTS=5 \
  XRAY_RETRY_DELAY=0 \
  sh "$root/entrypoint.sh" &
entry_pid=$!
ready=0
i=0
while [ "$i" -lt 50 ]; do
  if [ "$(cat "$tmp/xray-sleep-count")" -ge 1 ]; then
    ready=1
    break
  fi
  i=$((i + 1))
  sleep 0.1
done
if [ "$ready" -ne 1 ]; then
  kill -TERM "$entry_pid" 2>/dev/null || true
  fail "xray stub did not start"
fi
kill -TERM "$entry_pid"
set +e
wait "$entry_pid"
code=$?
set -e
if [ "$code" -ne 0 ]; then
  fail "entrypoint should exit 0 on SIGTERM, got $code"
fi
sleep 0.3
runs=$(cat "$tmp/xray-sleep-count")
if [ "$runs" -ne 1 ]; then
  fail "SIGTERM should not restart xray, got $runs starts"
fi

echo "ok"
