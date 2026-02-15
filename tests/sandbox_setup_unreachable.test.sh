#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

FAKE_BIN_DIR="$TMP_DIR/bin"
mkdir -p "$FAKE_BIN_DIR"

cat >"$FAKE_BIN_DIR/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Simulate a Docker CLI that exists but cannot reach its daemon.
if [[ "${1:-}" == "version" ]]; then
  echo "Cannot connect to the Docker daemon at ${DOCKER_HOST:-unset}" >&2
  exit 1
fi

# Existing script probes image inspect first.
if [[ "${1:-}" == "image" && "${2:-}" == "inspect" ]]; then
  exit 1
fi

echo "unexpected docker invocation: $*" >&2
exit 1
EOF
chmod +x "$FAKE_BIN_DIR/docker"

OUTPUT_FILE="$TMP_DIR/output.log"
set +e
PATH="$FAKE_BIN_DIR:$PATH" \
DOCKER_HOST="tcp://docker-proxy:2375" \
bash <(tr -d '\r' < "$ROOT_DIR/scripts/sandbox-setup.sh") >"$OUTPUT_FILE" 2>&1
STATUS=$?
set -e

if [[ $STATUS -ne 0 ]]; then
  echo "Expected sandbox-setup.sh to continue when Docker is unreachable."
  cat "$OUTPUT_FILE"
  exit 1
fi

if ! grep -q "Skipping sandbox image prebuild" "$OUTPUT_FILE"; then
  echo "Expected skip message in output."
  cat "$OUTPUT_FILE"
  exit 1
fi

echo "PASS: sandbox-setup.sh skips prebuild when Docker is unreachable."
