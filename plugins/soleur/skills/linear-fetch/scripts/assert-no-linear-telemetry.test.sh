#!/usr/bin/env bash
# Tests for assert-no-linear-telemetry.sh — TR7 telemetry-redaction gate.
#
# Run via:  bash plugins/soleur/skills/linear-fetch/scripts/assert-no-linear-telemetry.test.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/assert-no-linear-telemetry.sh"

PASS=0
FAIL=0
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }

# Helper: pipe $1 through script, capture exit code.
run_assert() {
  set +e
  printf '%s' "$1" | bash "$SCRIPT" >/dev/null 2>/dev/null
  RC=$?
  set -e
}

# ------------------------------------------------------------------------
# Clean cases — must exit 0.
# ------------------------------------------------------------------------
echo "Test 1: empty payload"
run_assert ""
[[ "$RC" == "0" ]] && pass "exit 0 on empty" || fail "rc=$RC"

echo "Test 2: generic telemetry text (no Linear refs)"
run_assert "linear-fetch applied"
[[ "$RC" == "0" ]] && pass "exit 0 on generic" || fail "rc=$RC"

echo "Test 3: JSON-like telemetry without Linear refs"
run_assert '{"rule": "hr-gdpr-gate", "action": "applied", "duration_ms": 12}'
[[ "$RC" == "0" ]] && pass "exit 0" || fail "rc=$RC"

# ------------------------------------------------------------------------
# Forbidden patterns — must exit 1.
# ------------------------------------------------------------------------
echo "Test 4: Linear identifier SOL-39"
run_assert "telemetry for SOL-39 processed"
[[ "$RC" == "1" ]] && pass "exit 1 on SOL-39" || fail "rc=$RC"

echo "Test 5: Linear identifier ENG-1234"
run_assert "ENG-1234 in payload"
[[ "$RC" == "1" ]] && pass "exit 1 on ENG-1234" || fail "rc=$RC"

echo "Test 6: uploads.linear.app URL"
run_assert "see https://uploads.linear.app/x.png"
[[ "$RC" == "1" ]] && pass "exit 1 on CDN URL" || fail "rc=$RC"

echo "Test 7: uploads.linear.app case-insensitive"
run_assert "Uploads.Linear.App/X.PNG"
[[ "$RC" == "1" ]] && pass "exit 1 on case-insensitive CDN" || fail "rc=$RC"

echo "Test 8: UUID-style ID"
run_assert "issue 9e0a3888-fd38-49cd-87cb-83cdcecca199 done"
[[ "$RC" == "1" ]] && pass "exit 1 on UUID" || fail "rc=$RC"

# ------------------------------------------------------------------------
# Edge cases — should NOT trigger false positives.
# ------------------------------------------------------------------------
echo "Test 9: PR-123 alone should NOT trigger (matches identifier shape but no Linear ref)"
# Actually PR-123 DOES match [A-Z]{2,}-[0-9]+ — this is the spec's R2
# false-positive class. The assertion is intentionally conservative:
# any [A-Z]{2,}-[0-9]+ in telemetry is forbidden, even if it's a GitHub
# PR reference. Telemetry should use generic strings or specific
# whitelisted IDs (hashed/anonymized) instead.
run_assert "see PR-123 for context"
[[ "$RC" == "1" ]] && pass "exit 1 on PR-123 (conservative)" || fail "rc=$RC"

echo "Test 10: lowercase identifier sol-39 should NOT trigger (case-sensitive on prefix)"
run_assert "sol-39 is lowercase"
[[ "$RC" == "0" ]] && pass "exit 0 on lowercase" || fail "rc=$RC"

# ------------------------------------------------------------------------
# File-path arg mode.
# ------------------------------------------------------------------------
echo "Test 11: file-path argument with clean content"
tmp=$(mktemp)
printf 'linear-fetch applied\n' > "$tmp"
set +e
bash "$SCRIPT" "$tmp" >/dev/null 2>/dev/null
RC=$?
set -e
rm -f "$tmp"
[[ "$RC" == "0" ]] && pass "exit 0 on clean file" || fail "rc=$RC"

echo "Test 12: file-path argument with forbidden content"
tmp=$(mktemp)
printf 'SOL-39 in file\n' > "$tmp"
set +e
bash "$SCRIPT" "$tmp" >/dev/null 2>/dev/null
RC=$?
set -e
rm -f "$tmp"
[[ "$RC" == "1" ]] && pass "exit 1 on dirty file" || fail "rc=$RC"

# ------------------------------------------------------------------------
echo
echo "Results: $PASS passed, $FAIL failed"
exit $((FAIL > 0 ? 1 : 0))
