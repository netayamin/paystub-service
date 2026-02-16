#!/usr/bin/env bash
# Start ngrok for port 8000 and set iOS Info.plist API_BASE_URL to the ngrok HTTPS URL.
# Usage: from repo root, run: ./scripts/ngrok-ios.sh   OR   make ngrok-ios
# Requires: backend running on 8000, ngrok installed. After this, rebuild the iOS app.

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLIST="${REPO_ROOT}/ios/DropFeed/Info.plist"

# Start ngrok in background if not already running
if ! curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:4040/api/tunnels 2>/dev/null | grep -q 200; then
  echo "Starting ngrok http 8000 in background..."
  ngrok http 8000 --log=stdout > /tmp/ngrok.log 2>&1 &
  NGROK_PID=$!
  echo "Waiting for ngrok API (up to 10s)..."
  for i in $(seq 1 10); do
    if curl -s -o /dev/null http://127.0.0.1:4040/api/tunnels 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

# Get HTTPS tunnel URL from ngrok local API
RESP="$(curl -s http://127.0.0.1:4040/api/tunnels 2>/dev/null)" || true
if [ -z "$RESP" ]; then
  echo "Error: ngrok API not reachable at http://127.0.0.1:4040. Is ngrok running?"
  echo "Run in another terminal: ngrok http 8000"
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  URL="$(echo "$RESP" | jq -r '.tunnels[] | select(.proto=="https") | .public_url' | head -1)"
else
  URL="$(python3 -c "
import sys, json, urllib.request
try:
    d = json.load(urllib.request.urlopen('http://127.0.0.1:4040/api/tunnels'))
    for t in d.get('tunnels', []):
        if t.get('proto') == 'https':
            print(t.get('public_url', ''))
            break
except Exception as e:
    sys.exit(1)
" 2>/dev/null)" || true
fi

if [ -z "$URL" ]; then
  echo "Error: could not get HTTPS tunnel URL from ngrok. Response: $RESP"
  exit 1
fi

# Trim trailing slash for consistency
URL="${URL%/}"

# Update Info.plist
plutil -replace API_BASE_URL -string "$URL" "$PLIST"
echo "Set API_BASE_URL to: $URL"
echo "Rebuild the iOS app (Xcode) so it uses this base URL."
