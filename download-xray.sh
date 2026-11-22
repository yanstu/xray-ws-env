#!/bin/sh
# Download the official Xray zip, check SHA2-256, and install the binary.
# Transient network errors and checksum mismatches are retried.
set -eu

: "${XRAY_VERSION:?XRAY_VERSION required}"
attempts="${DOWNLOAD_ATTEMPTS:-5}"
dest="${XRAY_DEST:-/usr/local/bin/xray}"
workdir="${XRAY_WORKDIR:-/tmp/xray-download}"
base="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}"

case "$attempts" in
  ''|*[!0-9]*) echo "DOWNLOAD_ATTEMPTS must be a positive integer" >&2; exit 1 ;;
esac
if [ "$attempts" -lt 1 ]; then
  echo "DOWNLOAD_ATTEMPTS must be a positive integer" >&2
  exit 1
fi

mkdir -p "$workdir" "$(dirname "$dest")"
zip="$workdir/x.zip"
dgst="$workdir/x.dgst"

i=1
while [ "$i" -le "$attempts" ]; do
  echo "xray download attempt ${i}/${attempts}" >&2
  rm -f "$zip" "$dgst"
  if wget -q --timeout=30 --tries=1 -O "$zip" "${base}/Xray-linux-64.zip" \
    && wget -q --timeout=30 --tries=1 -O "$dgst" "${base}/Xray-linux-64.zip.dgst"; then
    sum=$(sha256sum "$zip" | cut -d' ' -f1)
    expect=$(grep -i 'SHA2-256' "$dgst" | head -1 | awk '{print $NF}')
    if [ -n "$expect" ] && [ "$sum" = "$expect" ]; then
      unzip -o "$zip" xray -d "$(dirname "$dest")"
      extracted="$(dirname "$dest")/xray"
      if [ "$extracted" != "$dest" ]; then
        mv -f "$extracted" "$dest"
      fi
      chmod +x "$dest"
      rm -rf "$workdir"
      exit 0
    fi
    echo "xray checksum mismatch on attempt ${i}" >&2
  else
    echo "xray download failed on attempt ${i}" >&2
  fi
  if [ "$i" -lt "$attempts" ]; then
    if [ "${DOWNLOAD_RETRY_SLEEP+x}" = x ]; then
      sleep "$DOWNLOAD_RETRY_SLEEP"
    else
      sleep $((i * 2))
    fi
  fi
  i=$((i + 1))
done

echo "xray download failed after ${attempts} attempts" >&2
exit 1
