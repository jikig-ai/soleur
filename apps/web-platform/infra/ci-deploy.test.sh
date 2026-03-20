#!/usr/bin/env bash
set -euo pipefail

# Tests for ci-deploy.sh forced command script.
# Tests validation logic by sourcing the script with mock docker/curl/logger/chown.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_SCRIPT="$SCRIPT_DIR/ci-deploy.sh"

PASS=0
FAIL=0
TOTAL=0

run_deploy() {
  # Run ci-deploy.sh in a subshell with SSH_ORIGINAL_COMMAND set.
  # Mock out docker, curl, logger, chown so the script only tests validation logic.
  local cmd="${1:-}"
  (
    export SSH_ORIGINAL_COMMAND="$cmd"
    # Create temp bin dir with mocks
    MOCK_DIR=$(mktemp -d)
    trap 'rm -rf "$MOCK_DIR"' EXIT

    # Mock logger (accept any args silently)
    cat > "$MOCK_DIR/logger" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/logger"

    # Mock docker (accept any args silently)
    cat > "$MOCK_DIR/docker" << 'MOCK'
#!/bin/bash
# For 'docker run -d' print a fake container ID
if [[ "${1:-}" == "run" ]]; then
  echo "abc123"
fi
exit 0
MOCK
    chmod +x "$MOCK_DIR/docker"

    # Mock curl (simulate healthy endpoint)
    cat > "$MOCK_DIR/curl" << 'MOCK'
#!/bin/bash
# Handle -w '%{http_code}' for telegram-bridge health check
for arg in "$@"; do
  if [[ "$arg" == *"http_code"* ]]; then
    echo "200"
    exit 0
  fi
done
echo "OK"
exit 0
MOCK
    chmod +x "$MOCK_DIR/curl"

    # Mock chown
    cat > "$MOCK_DIR/chown" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$MOCK_DIR/chown"

    # Mock seq (for health check loops)
    cat > "$MOCK_DIR/seq" << 'MOCK'
#!/bin/bash
# Just return "1" so the loop runs once
echo "1"
MOCK
    chmod +x "$MOCK_DIR/seq"

    export PATH="$MOCK_DIR:$PATH"
    bash "$DEPLOY_SCRIPT" 2>&1
  )
}

assert_exit() {
  local description="$1"
  local expected_exit="$2"
  local cmd="${3:-}"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]]; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (expected exit $expected_exit, got $actual_exit)"
    echo "        output: $output"
  fi
}

assert_exit_contains() {
  local description="$1"
  local expected_exit="$2"
  local expected_text="$3"
  local cmd="${4:-}"

  TOTAL=$((TOTAL + 1))

  local output
  local actual_exit
  output=$(run_deploy "$cmd" 2>&1) && actual_exit=0 || actual_exit=$?

  if [[ "$actual_exit" -eq "$expected_exit" ]] && echo "$output" | grep -qF "$expected_text"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description (expected exit $expected_exit with '$expected_text')"
    echo "        actual exit: $actual_exit"
    echo "        output: $output"
  fi
}

echo "=== ci-deploy.sh tests ==="
echo ""

echo "--- Happy path ---"
assert_exit "web-platform deploy succeeds" 0 \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

assert_exit "telegram-bridge deploy succeeds" 0 \
  "deploy telegram-bridge ghcr.io/jikig-ai/soleur-telegram-bridge v2.3.1"

echo ""
echo "--- Empty/missing command ---"
assert_exit_contains "empty command rejected" 1 "no command provided" ""

echo ""
echo "--- Field count validation ---"
assert_exit_contains "single word rejected" 1 "expected 4 fields, got 1" "whoami"

assert_exit_contains "two fields rejected" 1 "expected 4 fields, got 2" "deploy web-platform"

assert_exit_contains "three fields rejected" 1 "expected 4 fields, got 3" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform"

assert_exit_contains "five fields rejected (extra arg)" 1 "expected 4 fields, got 5" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0 extra-arg"

echo ""
echo "--- Action validation ---"
assert_exit_contains "unknown action rejected" 1 "unknown action" \
  "exec web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Component validation ---"
assert_exit_contains "unknown component rejected" 1 "unknown component" \
  "deploy unknown-svc ghcr.io/jikig-ai/soleur-web-platform v1.0.0"

echo ""
echo "--- Image allowlist (exact match, not prefix) ---"
assert_exit_contains "suffix injection rejected" 1 "invalid image" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-attacker-repo v1.0.0"

assert_exit_contains "wrong image for component rejected" 1 "invalid image" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-telegram-bridge v1.0.0"

assert_exit_contains "arbitrary image rejected" 1 "invalid image" \
  "deploy web-platform evil-image:latest v1.0.0"

echo ""
echo "--- Tag format validation ---"
assert_exit_contains "latest tag rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform latest"

assert_exit_contains "tag without v prefix rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform 1.0.0"

assert_exit_contains "tag with extra suffix rejected" 1 "invalid tag format" \
  "deploy web-platform ghcr.io/jikig-ai/soleur-web-platform v1.0.0-rc1"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
