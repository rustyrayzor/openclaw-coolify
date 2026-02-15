#!/usr/bin/env bash
# openclaw-approve: Utility to auto-approve all pending device requests
echo "🔎 Checking for pending device requests..."

# Find the binary
OPENCLAW=$(command -v openclaw || command -v clawdbot || echo "openclaw")

if ! command -v "$OPENCLAW" >/dev/null 2>&1; then
  echo "❌ Error: OpenClaw binary not found!"
  exit 1
fi

# Resolve gateway auth info from local state.
OPENCLAW_STATE="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$OPENCLAW_STATE/openclaw.json"
if [ ! -f "$CONFIG_FILE" ] && [ -f "/root/.openclaw/openclaw.json" ]; then
  CONFIG_FILE="/root/.openclaw/openclaw.json"
fi

json_get() {
  local query="$1"
  local file="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r "$query" "$file" 2>/dev/null || true
    return
  fi

  if command -v node >/dev/null 2>&1; then
    node -e '
const fs = require("fs");
const [file, key] = process.argv.slice(1);
try {
  const data = JSON.parse(fs.readFileSync(file, "utf8"));
  if (key === "gateway.port") {
    const v = data?.gateway?.port;
    if (v !== undefined && v !== null) console.log(String(v));
  } else if (key === "gateway.auth.token") {
    const v = data?.gateway?.auth?.token;
    if (v) console.log(v);
  }
} catch {}
' "$file" "$query" 2>/dev/null || true
  fi
}

json_pending_ids() {
  if command -v jq >/dev/null 2>&1; then
    jq -r '.pending[] | .requestId // .id // .request' 2>/dev/null || true
    return
  fi

  if command -v node >/dev/null 2>&1; then
    node -e '
let input = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (c) => (input += c));
process.stdin.on("end", () => {
  try {
    const data = JSON.parse(input);
    for (const item of data?.pending || []) {
      const id = item?.requestId || item?.id || item?.request;
      if (id) console.log(id);
    }
  } catch {}
});
' 2>/dev/null || true
  fi
}

GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
GATEWAY_TOKEN=""
if [ -f "$CONFIG_FILE" ]; then
  GATEWAY_PORT="$(json_get "gateway.port" "$CONFIG_FILE")"
  GATEWAY_TOKEN="$(json_get "gateway.auth.token" "$CONFIG_FILE")"
fi

if [ -z "$GATEWAY_PORT" ] || [ "$GATEWAY_PORT" = "null" ]; then
  GATEWAY_PORT="18789"
fi

OPENCLAW_ARGS=(--url "ws://127.0.0.1:${GATEWAY_PORT}")
if [ -n "$GATEWAY_TOKEN" ] && [ "$GATEWAY_TOKEN" != "null" ]; then
  OPENCLAW_ARGS+=(--token "$GATEWAY_TOKEN")
fi

# Try multiple common keys for the request ID
LIST_JSON="$($OPENCLAW devices list --json "${OPENCLAW_ARGS[@]}")"
IDS=$(printf '%s\n' "$LIST_JSON" | sed -n '/^{/,$p' | json_pending_ids | grep -v "null")

if [ -z "$IDS" ]; then
  echo "✅ No pending requests found."
  exit 0
fi

for ID in $IDS; do
  echo "🚀 Approving request: $ID"
  $OPENCLAW devices approve "$ID" "${OPENCLAW_ARGS[@]}"
done
