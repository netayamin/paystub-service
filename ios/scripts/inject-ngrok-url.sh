#!/usr/bin/env bash
# When building for a physical iPhone, if ngrok is running (web UI on 4040),
# replace API_BASE_URL in the *built* app's Info.plist with the HTTPS tunnel URL.
# Source tree Info.plist is unchanged (stays 127.0.0.1 for Simulator).

set -u

if [ "${PLATFORM_NAME:-}" != "iphoneos" ]; then
  exit 0
fi

APP_BUNDLE="${WRAPPER_NAME:-${PRODUCT_NAME}.app}"
PLIST=""
for candidate in \
  "${TARGET_BUILD_DIR}/${APP_BUNDLE}/Info.plist" \
  "${CODESIGNING_FOLDER_PATH}/Info.plist"; do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    PLIST="$candidate"
    break
  fi
done

if [ -z "$PLIST" ]; then
  echo "note: inject-ngrok-url: built Info.plist not found yet (skip)"
  exit 0
fi

if ! curl -s -o /dev/null --connect-timeout 1 "http://127.0.0.1:4040/api/tunnels" 2>/dev/null; then
  echo "note: ngrok not on 4040 — device app uses Info.plist; 127.0.0.1 is ignored on device (→ EC2 in app code)."
  echo "      For local Mac API: run  ngrok http 8000  then rebuild."
  exit 0
fi

URL="$(/usr/bin/python3 <<'PY'
import json
import urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:4040/api/tunnels", timeout=2) as r:
        d = json.load(r)
    for t in d.get("tunnels", []):
        if t.get("proto") == "https":
            u = (t.get("public_url") or "").rstrip("/")
            if u:
                print(u)
            break
except Exception:
    pass
PY
)"

if [ -z "$URL" ]; then
  echo "note: no HTTPS ngrok tunnel in /api/tunnels"
  exit 0
fi

/usr/libexec/PlistBuddy -c "Set :API_BASE_URL ${URL}" "$PLIST" && \
  echo "Injected API_BASE_URL → ${URL}"
