#!/usr/bin/env bash
# Tests for cat-inngest-verify-state.sh — the /hooks/inngest-verify-status reporter
# (#5450, P1a). Mirrors cat-infra-config-state.test.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/cat-inngest-verify-state.sh"

PASS=0
FAIL=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then echo "  PASS: $desc"; PASS=$((PASS + 1));
  else echo "  FAIL: $desc"; echo "    expected: $expected"; echo "    actual:   $actual"; FAIL=$((FAIL + 1)); fi
}

echo "=== cat-inngest-verify-state.sh tests ==="
assert_eq "script exists and is executable" "1" "$([[ -x "$TARGET" ]] && echo 1 || echo 0)"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# no prior verify
OUT=$(INNGEST_VERIFY_STATE="$TMP/none.state" bash "$TARGET")
assert_eq "no_prior_verify sentinel exit_code=-2" "-2" "$(echo "$OUT" | jq -r .exit_code)"
assert_eq "no_prior_verify reason" "no_prior_verify" "$(echo "$OUT" | jq -r .reason)"

# good terminal state passthrough
echo '{"exit_code":0,"start_ts":123,"reason":"verify_passed","marker_fired":true}' > "$TMP/ok.state"
OUT=$(INNGEST_VERIFY_STATE="$TMP/ok.state" bash "$TARGET")
assert_eq "passes through exit_code" "0" "$(echo "$OUT" | jq -r .exit_code)"
assert_eq "passes through start_ts (freshness anchor)" "123" "$(echo "$OUT" | jq -r .start_ts)"
assert_eq "passes through marker_fired" "true" "$(echo "$OUT" | jq -r .marker_fired)"

# corrupt state
printf 'not json{' > "$TMP/bad.state"
OUT=$(INNGEST_VERIFY_STATE="$TMP/bad.state" bash "$TARGET")
assert_eq "corrupt_state sentinel exit_code=-3" "-3" "$(echo "$OUT" | jq -r .exit_code)"

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[[ "$FAIL" -gt 0 ]] && exit 1 || exit 0
