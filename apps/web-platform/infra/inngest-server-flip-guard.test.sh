#!/usr/bin/env bash
# Tests for inngest-server-flip-guard.sh — the P1-5 arm-atomicity ExecStartPre guard
# (#6178, ADR-100). Driven via the GUARD_POSTGRES_URI / GUARD_FLIP_FLAG fixture seams
# (no doppler). The guard blocks inngest-server start ONLY when the URI is prod AND the
# flag is not in {armed, flipping, done}; every other combination allows the start.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/inngest-server-flip-guard.sh"

# A representative prod URI (contains the dedicated Supabase project ref marker) and a
# dark/non-prod URI (a different ref). Synthesized fixtures — no real credentials.
readonly PROD_URI="postgres://postgres.pigsfuxruiopinouvjwy:REDACTED@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"
readonly DARK_URI="postgres://postgres.darkdevref00000000:REDACTED@aws-0-eu-west-1.pooler.supabase.com:5432/postgres"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }

# run_guard <uri> <flag-present:0|1> <flag> -> echoes exit code.
run_guard() {
  local uri="$1" has_flag="$2" flag="${3:-}"
  local rc=0
  if [[ "$has_flag" == "1" ]]; then
    GUARD_POSTGRES_URI="$uri" GUARD_FLIP_FLAG="$flag" bash "$TARGET" >/dev/null 2>&1 || rc=$?
  else
    # Flag genuinely unset in the env (no GUARD_FLIP_FLAG, no INNGEST_CUTOVER_FLIP).
    GUARD_POSTGRES_URI="$uri" bash "$TARGET" >/dev/null 2>&1 || rc=$?
  fi
  printf '%s' "$rc"
}

assert_rc() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then pass "$desc";
  else fail "$desc (expected rc=$expected, got rc=$actual)"; fi
}
assert_blocks() {
  local desc="$1" rc="$2"
  if [[ "$rc" != "0" ]]; then pass "$desc"; else fail "$desc (expected non-zero, got rc=0 — start NOT blocked)"; fi
}

echo "=== inngest-server-flip-guard.sh test suite ==="

# --- Blocked: prod URI + flag unset / empty / stray ---
echo "TEST: prod URI + unset flag => BLOCK (non-zero)"
assert_blocks "prod + unset flag blocks" "$(run_guard "$PROD_URI" 0)"
echo "TEST: prod URI + empty flag => BLOCK (non-zero)"
assert_blocks "prod + empty flag blocks" "$(run_guard "$PROD_URI" 1 "")"
echo "TEST: prod URI + rollback flag => BLOCK (non-zero; rollback is not an allowed start state)"
assert_blocks "prod + rollback blocks" "$(run_guard "$PROD_URI" 1 "rollback")"
echo "TEST: prod URI + aborted flag => BLOCK (non-zero)"
assert_blocks "prod + aborted blocks" "$(run_guard "$PROD_URI" 1 "aborted")"

# --- Allowed: prod URI + flag in {armed, flipping, done} ---
for flag in armed flipping "done"; do
  echo "TEST: prod URI + '$flag' flag => ALLOW (exit 0)"
  assert_rc "prod + '$flag' allows start" "0" "$(run_guard "$PROD_URI" 1 "$flag")"
done

# --- Allowed: dark (non-prod) URI + ANY flag (incl. unset) ---
echo "TEST: dark URI + unset flag => ALLOW (exit 0)"
assert_rc "dark + unset allows start" "0" "$(run_guard "$DARK_URI" 0)"
for flag in armed rollback aborted "" garbage; do
  echo "TEST: dark URI + '${flag:-unset}' flag => ALLOW (exit 0)"
  assert_rc "dark + '${flag:-unset}' allows start" "0" "$(run_guard "$DARK_URI" 1 "$flag")"
done

# --- Purity: the guard must not echo the connection string (AC-NOBODY) ---
echo "TEST: guard never echoes the Postgres URI (AC-NOBODY)"
out=$(GUARD_POSTGRES_URI="$PROD_URI" GUARD_FLIP_FLAG="" bash "$TARGET" 2>&1 || true)
if [[ "$out" == *"pigsfuxruiopinouvjwy"* || "$out" == *"pooler.supabase.com"* || "$out" == *"REDACTED"* ]]; then
  fail "guard leaked a connection-string fragment into its output"
else
  pass "guard output carries no connection-string fragment"
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
