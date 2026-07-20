#!/usr/bin/env bash
# Tests for inngest-server-flip-guard.sh — the P1-5 arm-atomicity ExecStartPre guard
# (#6178, ADR-100). Driven via the GUARD_POSTGRES_URI / GUARD_FLIP_FLAG fixture seams
# (no doppler). The guard blocks inngest-server start ONLY when the URI is prod AND the
# flag is not in {armed, flipping, flushed, done}; every other combination allows the start.
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

# --- Allowed: prod URI + flag in {armed, flipping, flushed, done} ---
# `flushed` is the #6553 fix: the flip FSM sets flag=flushed then calls start_server
# (inngest-cutover-flip.sh:188-189, and the flushed-resume arm :240), so the guard MUST
# allow a prod-URI start at flushed — else it blocks the FSM's own controlled start.
for flag in armed flipping flushed "done"; do
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

# --- FSM<->guard lockstep drift guard (#6553 / ADR-100 class invariant) ---
# The guard's ALLOW allowlist MUST be a SUPERSET of every FSM state in which the cutover
# flip oneshot invokes `start_server`. Otherwise the guard blocks the FSM's own controlled
# start (the #6553 bug). Both sets are derived from source, so a future `flag_set <X>;
# start_server` (or a `<X>)` case arm that starts the server) that the guard omits FAILS here.
echo "TEST: FSM start-states are a subset of the guard allowlist (lockstep drift guard)"
FSM="$SCRIPT_DIR/inngest-cutover-flip.sh"
if [[ ! -f "$FSM" ]]; then
  fail "FSM source $FSM not found — cannot verify lockstep"
else
  # Guard allowlist: the tokens before ')' on the `flag_ok=true` case line.
  guard_allow=$(grep -E 'flag_ok=true' "$TARGET" | head -1 | sed -E 's/\).*//' \
    | tr '|' '\n' | sed -E 's/[[:space:]]//g' | grep -E '^[a-z-]+$' | LC_ALL=C sort -u)
  # FSM start-states: walk top-down tracking the nearest preceding `flag_set <arg>` OR case-arm
  # label `<state>)`, and emit that state at every line that STARTS THE SERVER. "Starts the
  # server" is deliberately BROAD — ANY `start_server` call shape (bare, `if ! start_server`,
  # `start_server || flag_set aborted`, …) OR a direct `systemctl_cmd start "$SERVER_UNIT"` (the
  # helper's body — a future arm could inline it, bypassing the `start_server` name). A narrow
  # "bare `start_server` on its own line" match is VACUOUS: the FSM's own idiom is compound
  # (`if ! redis_flushall`), so a resume/repair arm written `if ! start_server` in a
  # non-allowlisted state would run the server where the runtime guard blocks it — the #6553 bug —
  # with this test green. The `start_server()`/`flag_set()` DEFINITION lines and comments are
  # skipped first, so the helper body's own `systemctl_cmd start` is not counted as a call.
  raw_starts=$(awk '
    /^[[:space:]]*#/                                   { next }
    /^[[:space:]]*flag_set[[:space:]]+["'\'']?[a-z-]+/  { s=$2; gsub(/["'\'']/,"",s); cur=s; next }
    /^[[:space:]]*[a-z][a-z_-]*\)[[:space:]]*$/         { s=$1; sub(/\).*/,"",s); cur=s; next }
    /^[[:space:]]*start_server\(\)/                     { next }
    /(^|[^A-Za-z_])start_server([^A-Za-z_(]|$)/         { if (cur!="") print cur; next }
    /systemctl_cmd start[[:space:]]+"\$SERVER_UNIT"/    { if (cur!="") print cur; next }
  ' "$FSM")
  fsm_states=$(printf '%s\n' "$raw_starts" | grep -vE '^$' | LC_ALL=C sort -u)
  start_site_count=$(printf '%s\n' "$raw_starts" | grep -cE '^[a-z-]+$' || true)

  # Count-drift latch (also gives the case-arm-label rule independent coverage): the FSM starts
  # the server at exactly EXPECTED_START_SITES places today — the forward-path
  # `flag_set flushed; start_server` and the `flushed)` resume arm. A change to this count means a
  # start site was added/removed OR a derivation rule silently dropped one; re-verify each new
  # state is in the guard allowlist, then bump EXPECTED_START_SITES.
  EXPECTED_START_SITES=2

  if [[ "$start_site_count" -ne "$EXPECTED_START_SITES" ]]; then
    fail "FSM start_server call-site count = $start_site_count, expected $EXPECTED_START_SITES — a start site was added/removed (or a derivation rule dropped one). Re-verify each new state is in the guard allowlist, then update EXPECTED_START_SITES. Derived states: [$(printf '%s' "$fsm_states" | tr '\n' ' ')]"
  # Non-vacuity: the derivation MUST find the known start-state (flushed). A silent empty
  # derivation would make the subset check pass vacuously.
  elif ! printf '%s\n' "$fsm_states" | grep -qx 'flushed'; then
    fail "lockstep derivation did not find the known 'flushed' start-state (derivation broken?); got: [$(printf '%s' "$fsm_states" | tr '\n' ' ')]"
  else
    missing=$(LC_ALL=C comm -23 <(printf '%s\n' "$fsm_states") <(printf '%s\n' "$guard_allow"))
    if [[ -n "$missing" ]]; then
      fail "FSM starts the server in state(s) the guard allowlist OMITS: [$(printf '%s' "$missing" | tr '\n' ' ')] — widen inngest-server-flip-guard.sh (ADR-100 class invariant: allowlist must cover every start_server state)"
    else
      pass "guard allowlist [$(printf '%s' "$guard_allow" | tr '\n' ' ')] covers all FSM start-states [$(printf '%s' "$fsm_states" | tr '\n' ' ')] ($start_site_count start sites)"
    fi
  fi
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
if [[ "$FAIL" -gt 0 ]]; then exit 1; fi
