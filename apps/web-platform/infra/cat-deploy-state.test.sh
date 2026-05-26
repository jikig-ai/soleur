#!/usr/bin/env bash
# Tests for cat-deploy-state.sh — verifies the JSON merge contract
# (#2185 base + #4116 services.inngest_heartbeat extension).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/cat-deploy-state.sh"

PASS=0
FAIL=0
TOTAL=0

assert() {
  local description="$1"
  local condition="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$condition"; then
    PASS=$((PASS + 1))
    echo "  PASS: $description"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $description"
    echo "        condition: $condition"
  fi
}

echo "=== cat-deploy-state.sh tests ==="
echo ""

assert "script exists and is executable" "[[ -x '$TARGET' ]]"

# --- no_prior_deploy sentinel + services field ---
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
NO_DEPLOY_OUT=$(CI_DEPLOY_STATE="$TMP/nonexistent.state" bash "$TARGET")
assert "no_prior_deploy sentinel exit_code = -2" \
  "[[ \$(printf '%s' '$NO_DEPLOY_OUT' | jq -r .exit_code) == '-2' ]]"
assert "no_prior_deploy carries services.inngest_heartbeat" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"

# --- successful state file merge ---
echo '{"exit_code":0,"target":"inngest","tag":"vinngest-v1.2.3"}' > "$TMP/ok.state"
OK_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" bash "$TARGET")
assert "OK state preserves exit_code" \
  "[[ \$(printf '%s' '$OK_OUT' | jq -r .exit_code) == '0' ]]"
assert "OK state preserves target field" \
  "[[ \$(printf '%s' '$OK_OUT' | jq -r .target) == 'inngest' ]]"
assert "OK state injects services.inngest_heartbeat" \
  "printf '%s' '$OK_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"

# --- pre-existing services.* keys preserved ---
echo '{"exit_code":0,"services":{"web":"healthy"}}' > "$TMP/svc.state"
SVC_OUT=$(CI_DEPLOY_STATE="$TMP/svc.state" bash "$TARGET")
assert "pre-existing services.web preserved" \
  "[[ \$(printf '%s' '$SVC_OUT' | jq -r .services.web) == 'healthy' ]]"
assert "services.inngest_heartbeat still added alongside services.web" \
  "printf '%s' '$SVC_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"

# --- corrupt state sentinel ---
echo 'not valid json {' > "$TMP/corrupt.state"
CORRUPT_OUT=$(CI_DEPLOY_STATE="$TMP/corrupt.state" bash "$TARGET")
assert "corrupt_state sentinel exit_code = -3" \
  "[[ \$(printf '%s' '$CORRUPT_OUT' | jq -r .exit_code) == '-3' ]]"
assert "corrupt_state carries services.inngest_heartbeat" \
  "printf '%s' '$CORRUPT_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
