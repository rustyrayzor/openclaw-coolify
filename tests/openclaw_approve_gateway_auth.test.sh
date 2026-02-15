#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

STATE_DIR="$TMP_DIR/state"
mkdir -p "$STATE_DIR"
cat >"$STATE_DIR/openclaw.json" <<'EOF'
{
  "gateway": {
    "port": 18789,
    "auth": {
      "token": "test-gateway-token"
    }
  }
}
EOF

FAKE_BIN_DIR="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN_DIR"
CALLS_LOG="$TMP_DIR/calls.log"

cat >"$FAKE_BIN_DIR/openclaw" <<EOF
#!/usr/bin/env bash
set -euo pipefail

echo "\$*" >>"$CALLS_LOG"

if [[ "\${1:-}" == "devices" && "\${2:-}" == "list" ]]; then
  echo '{"pending":[{"requestId":"req-1"}]}'
  exit 0
fi

if [[ "\${1:-}" == "devices" && "\${2:-}" == "approve" ]]; then
  exit 0
fi

echo "unexpected openclaw args: \$*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN_DIR/openclaw"

OUTPUT_FILE="$TMP_DIR/output.log"
PATH="$FAKE_BIN_DIR:$PATH" \
OPENCLAW_STATE_DIR="$STATE_DIR" \
bash <(tr -d '\r' < "$ROOT_DIR/scripts/openclaw-approve.sh") >"$OUTPUT_FILE" 2>&1

LIST_CALL="$(grep '^devices list' "$CALLS_LOG" || true)"
APPROVE_CALL="$(grep '^devices approve req-1' "$CALLS_LOG" || true)"

if [[ -z "$LIST_CALL" ]]; then
  echo "Expected devices list call."
  cat "$CALLS_LOG"
  cat "$OUTPUT_FILE"
  exit 1
fi

if [[ -z "$APPROVE_CALL" ]]; then
  echo "Expected devices approve call."
  cat "$CALLS_LOG"
  cat "$OUTPUT_FILE"
  exit 1
fi

for EXPECTED in "--url ws://127.0.0.1:18789" "--token test-gateway-token"; do
  if [[ "$LIST_CALL" != *"$EXPECTED"* ]]; then
    echo "devices list call missing $EXPECTED"
    cat "$CALLS_LOG"
    cat "$OUTPUT_FILE"
    exit 1
  fi

  if [[ "$APPROVE_CALL" != *"$EXPECTED"* ]]; then
    echo "devices approve call missing $EXPECTED"
    cat "$CALLS_LOG"
    cat "$OUTPUT_FILE"
    exit 1
  fi
done

echo "PASS: openclaw-approve uses explicit gateway URL and token."
