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
assert "no_prior_deploy carries services.inngest_heartbeat_timer" \
  "printf '%s' '$NO_DEPLOY_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- successful state file merge ---
echo '{"exit_code":0,"target":"inngest","tag":"vinngest-v1.2.3"}' > "$TMP/ok.state"
OK_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" bash "$TARGET")
assert "OK state preserves exit_code" \
  "[[ \$(printf '%s' '$OK_OUT' | jq -r .exit_code) == '0' ]]"
assert "OK state preserves target field" \
  "[[ \$(printf '%s' '$OK_OUT' | jq -r .target) == 'inngest' ]]"
assert "OK state injects services.inngest_heartbeat" \
  "printf '%s' '$OK_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "OK state injects services.inngest_heartbeat_timer" \
  "printf '%s' '$OK_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- pre-existing services.* keys preserved ---
echo '{"exit_code":0,"services":{"web":"healthy"}}' > "$TMP/svc.state"
SVC_OUT=$(CI_DEPLOY_STATE="$TMP/svc.state" bash "$TARGET")
assert "pre-existing services.web preserved" \
  "[[ \$(printf '%s' '$SVC_OUT' | jq -r .services.web) == 'healthy' ]]"
assert "services.inngest_heartbeat still added alongside services.web" \
  "printf '%s' '$SVC_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "services.inngest_heartbeat_timer still added alongside services.web" \
  "printf '%s' '$SVC_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- corrupt state sentinel ---
echo 'not valid json {' > "$TMP/corrupt.state"
CORRUPT_OUT=$(CI_DEPLOY_STATE="$TMP/corrupt.state" bash "$TARGET")
assert "corrupt_state sentinel exit_code = -3" \
  "[[ \$(printf '%s' '$CORRUPT_OUT' | jq -r .exit_code) == '-3' ]]"
assert "corrupt_state carries services.inngest_heartbeat" \
  "printf '%s' '$CORRUPT_OUT' | jq -e '.services.inngest_heartbeat' >/dev/null"
assert "corrupt_state carries services.inngest_heartbeat_timer" \
  "printf '%s' '$CORRUPT_OUT' | jq -e '.services.inngest_heartbeat_timer' >/dev/null"

# --- #5417 container restart / OOM observability fields (AC7) ---
# Use a guaranteed-absent container so docker inspect fails → safe sentinels,
# and a non-existent rate file so the rolling rate defaults to 0.
CR_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" CONTAINER_NAME="soleur-absent-test-xyz" \
  CONTAINER_RESTART_RATE_FILE="$TMP/nope.rate" bash "$TARGET")
# Collision guard: the top-level exit_code MUST remain the DEPLOY sentinel (0),
# NOT the container's State.ExitCode (which is exposed as container_exit_code).
assert "deploy exit_code preserved (container exit code did NOT clobber it)" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .exit_code) == '0' ]]"
assert "restart_count present with absent-container sentinel -1" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .restart_count) == '-1' ]]"
assert "oom_killed present (boolean false sentinel)" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .oom_killed) == 'false' ]]"
assert "container_exit_code present (distinct key from deploy exit_code)" \
  "printf '%s' '$CR_OUT' | jq -e 'has(\"container_exit_code\")' >/dev/null"
assert "restart_rate_per_hour present (0 when no rate file)" \
  "[[ \$(printf '%s' '$CR_OUT' | jq -r .restart_rate_per_hour) == '0' ]]"
assert "oom_journal_tail present and a string" \
  "printf '%s' '$CR_OUT' | jq -e '.oom_journal_tail | type == \"string\"' >/dev/null"

# Rolling-rate passthrough from the container-restart-monitor's persisted file.
echo '7' > "$TMP/has.rate"
RATE_OUT=$(CI_DEPLOY_STATE="$TMP/ok.state" CONTAINER_NAME="soleur-absent-test-xyz" \
  CONTAINER_RESTART_RATE_FILE="$TMP/has.rate" bash "$TARGET")
assert "restart_rate_per_hour reads the monitor's persisted rate (7)" \
  "[[ \$(printf '%s' '$RATE_OUT' | jq -r .restart_rate_per_hour) == '7' ]]"

echo ""
echo "=== Results: $PASS/$TOTAL passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
