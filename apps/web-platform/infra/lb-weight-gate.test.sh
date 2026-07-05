#!/usr/bin/env bash
# Tests for lb-weight-gate.sh — the fail-closed, SHAPE-ONLY programmatic ADR-068 §(c)
# LB-weight gate. Asserts on EXIT CODES **and** the structured `gate_fail sub_condition=…`
# stderr line (the machine-readable contract a future orchestrator parses), accumulate-
# then-exit. Asserting the sub_condition — not just a non-zero rc — makes a refactor that
# rejects for the WRONG reason go RED.
#
# The gate is pure over injected env; these tests run it under `env -i PATH=…` so a
# "missing" var is genuinely absent (not inherited from the harness). Timestamps are
# computed RELATIVE TO A COMPUTED `now` — never date-faked / hard-coded.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="${SCRIPT_DIR}/lb-weight-gate.sh"

PASS=0
FAIL=0
TOTAL=0

# --- Computed-now timestamps (NO date-faking) --------------------------------
NOW=$(date -u +%s)
ISO() { date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; }
ELAPSED_CUTOVER=$(ISO "$(( NOW - 4 * 86400 ))")   # 4d ago > default 3d soak → elapsed
FRESH_CUTOVER=$(ISO "$(( NOW - 1 * 86400 ))")     # 1d ago < 3d soak → not elapsed
FUTURE_CUTOVER=$(ISO "$(( NOW + 2 * 86400 ))")    # future → reject
BOUNDARY_CUTOVER=$(ISO "$(( NOW - 3 * 86400 ))")  # exactly 3d ago → delta >= soak → passes
NOW_CUTOVER=$(ISO "$NOW")                          # marker == now → future-check ok, soak fails
# A tz-offset (+02:00) instant equal to ELAPSED_CUTOVER's UTC instant: wall = UTC + 2h, so
# the "+02:00" string parses back to the same 4d-ago epoch. Exercises the ISO_RE offset arm.
TZOFFSET_CUTOVER="$(date -u -d "@$(( NOW - 4 * 86400 + 2 * 3600 ))" +%Y-%m-%dT%H:%M:%S)+02:00"

# --- Default (all-hold) injected config --------------------------------------
declare -A DEF
reset_def() {
  DEF=(
    [SOLEUR_PROXY_BIND]='10.0.1.10'
    [SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.11'
    [SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11"}'
    [GIT_DATA_STORE_ENABLED]='true'
    [GIT_DATA_LUKS_CUTOVER_AT]="$ELAPSED_CUTOVER"
    [GIT_DATA_LUKS_SOAK_DAYS]='3'
  )
}

GATE_OUT=""
GATE_ERR=""
GATE_RC=0
run_with_def() {
  local -a args=()
  local k
  for k in "${!DEF[@]}"; do args+=("${k}=${DEF[$k]}"); done
  local out rc errfile
  errfile=$(mktemp)
  # Guarded so set -e does not abort on the gate's (intended) non-zero exit. stderr is
  # captured (not discarded) so tests can assert the structured `sub_condition=…` line.
  out=$(env -i PATH="$PATH" "${args[@]}" bash "$GATE" 2>"$errfile") && rc=0 || rc=$?
  GATE_OUT="$out"
  GATE_ERR="$(cat "$errfile")"
  rm -f "$errfile"
  GATE_RC="$rc"
}

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1 (rc=${GATE_RC})"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

assert_zero()    { if [[ "$GATE_RC" -eq 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_nonzero() { if [[ "$GATE_RC" -ne 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_stdout_contains() {
  if [[ "$GATE_OUT" == *"$2"* ]]; then pass "$1"; else fail "$1 — stdout missing '$2'"; fi
}
# Assert the machine-readable failure reason on stderr. `$2` is the expected sub_condition
# id; we match the full `sub_condition=<id>` token so a substring of another id can't alias.
assert_stderr_contains() {
  if [[ "$GATE_ERR" == *"sub_condition=$2"* ]]; then pass "$1"
  else fail "$1 — stderr missing 'sub_condition=$2' (got: ${GATE_ERR})"; fi
}
# Negative-case shorthand: assert BOTH non-zero rc AND the expected sub_condition.
assert_rejects_with() {
  assert_nonzero "$1"
  assert_stderr_contains "$1 [sub_condition]" "$2"
}

echo "=== lb-weight-gate.sh test suite ==="

# 1. Both conditions hold → exit 0 AND SHAPE-ONLY probe marker on stdout.
reset_def; run_with_def
assert_zero "both conditions hold → exit 0"
assert_stdout_contains "success prints requires_runtime_bind_probe=true" "requires_runtime_bind_probe=true"

# 2. Condition A — each single missing/empty relay var → reject with its sub_condition.
reset_def; unset 'DEF[SOLEUR_PROXY_BIND]'; run_with_def
assert_rejects_with "SOLEUR_PROXY_BIND missing" "A_proxy_bind_empty"
reset_def; DEF[SOLEUR_PROXY_BIND]=''; run_with_def
assert_rejects_with "SOLEUR_PROXY_BIND empty" "A_proxy_bind_empty"
reset_def; DEF[SOLEUR_PROXY_BIND]='   '; run_with_def
assert_rejects_with "SOLEUR_PROXY_BIND whitespace-only (trims to empty)" "A_proxy_bind_empty"

reset_def; unset 'DEF[SOLEUR_PROXY_PEER_ALLOWLIST]'; run_with_def
assert_rejects_with "SOLEUR_PROXY_PEER_ALLOWLIST missing" "A_peer_allowlist_empty"
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]=''; run_with_def
assert_rejects_with "SOLEUR_PROXY_PEER_ALLOWLIST empty" "A_peer_allowlist_empty"
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='  ,  '; run_with_def
assert_rejects_with "SOLEUR_PROXY_PEER_ALLOWLIST all-whitespace/commas parses empty" "A_peer_allowlist_empty"

reset_def; unset 'DEF[SOLEUR_HOST_ROSTER]'; run_with_def
assert_rejects_with "SOLEUR_HOST_ROSTER missing" "A_host_roster_empty"
reset_def; DEF[SOLEUR_HOST_ROSTER]=''; run_with_def
assert_rejects_with "SOLEUR_HOST_ROSTER empty" "A_host_roster_empty"

# 3. Roster missing web-2 specifically → reject.
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-3":"10.0.1.11"}'; run_with_def
assert_rejects_with "roster without web-2 entry" "A_web2_not_in_roster"

# 4. Roster loader-rejects — the fail-closed checks the loader lacks.
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11","web-2":"10.0.1.99"}'; run_with_def
assert_rejects_with "roster duplicate key" "A_host_roster_duplicate_key"
reset_def; DEF[SOLEUR_HOST_ROSTER]='["10.0.1.10","10.0.1.11"]'; run_with_def
assert_rejects_with "roster non-object (array)" "A_host_roster_not_object"
reset_def; DEF[SOLEUR_HOST_ROSTER]='not json at all'; run_with_def
assert_rejects_with "roster invalid JSON" "A_host_roster_invalid_json"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-2":"10.0.1.11","   ":"10.0.1.10"}'; run_with_def
assert_rejects_with "roster whitespace-only key" "A_host_roster_blank_key"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"","web-2":"10.0.1.11"}'; run_with_def
assert_rejects_with "roster blank value" "A_host_roster_bad_value"

# 5. Allowlist ⊄ roster hosts (outbound-dial direction) → reject.
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.11,10.9.9.9'; run_with_def
assert_rejects_with "allowlist peer not in roster addresses" "A_allowlist_not_subset_of_roster"

# 5b. web-2's roster (dial) address ⊄ allowlist (inbound accept set) → reject. Here the
#     allowlist is a valid SUBSET of roster addresses (10.0.1.10 is web-1's addr) so the
#     A.subset check passes, but web-2's addr (10.0.1.11) is NOT an accepted inbound peer →
#     post-flip inbound relay from web-2 would be rejected → workspace-gone.
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.10'; run_with_def
assert_rejects_with "roster has web-2 but allowlist omits its dial address" "A_web2_addr_not_in_allowlist"

# 6. Condition B — git-data cut-over config-shape.
reset_def; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_rejects_with "GIT_DATA_STORE_ENABLED=false" "B_git_data_store_disabled"
reset_def; unset 'DEF[GIT_DATA_STORE_ENABLED]'; run_with_def
assert_rejects_with "GIT_DATA_STORE_ENABLED missing" "B_git_data_store_disabled"

reset_def; unset 'DEF[GIT_DATA_LUKS_CUTOVER_AT]'; run_with_def
assert_rejects_with "LUKS cutover marker absent" "B_luks_cutover_marker_absent"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='   '; run_with_def
assert_rejects_with "LUKS cutover marker whitespace-only (trims to empty)" "B_luks_cutover_marker_absent"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='not-a-timestamp'; run_with_def
assert_rejects_with "LUKS cutover marker unparseable" "B_luks_cutover_marker_unparseable"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='2026-13-45T99:99:99Z'; run_with_def
assert_rejects_with "LUKS cutover marker garbage-but-ISO-shaped" "B_luks_cutover_marker_unparseable"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FUTURE_CUTOVER"; run_with_def
assert_rejects_with "LUKS cutover marker future-dated" "B_luks_cutover_marker_future"
# Pre-1970 marker: parses to a NEGATIVE epoch (nonsensical, predates the git-data store).
# Without the pre-epoch guard `delta = now - negative` is huge → soak trivially "elapsed".
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='1960-01-01'; run_with_def
assert_rejects_with "LUKS cutover marker pre-1970 (negative epoch)" "B_luks_cutover_marker_pre_epoch"

reset_def; DEF[GIT_DATA_LUKS_SOAK_DAYS]='0'; run_with_def
assert_rejects_with "GIT_DATA_LUKS_SOAK_DAYS=0 (floor)" "B_luks_soak_days_invalid"
reset_def; DEF[GIT_DATA_LUKS_SOAK_DAYS]='-1'; run_with_def
assert_rejects_with "GIT_DATA_LUKS_SOAK_DAYS negative" "B_luks_soak_days_invalid"

reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_rejects_with "soak not elapsed (1d < 3d)" "B_luks_soak_not_elapsed"
# marker == now → future-check passes (delta >= 0) but soak has not elapsed (delta ~ 0 < 3d).
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$NOW_CUTOVER"; run_with_def
assert_rejects_with "soak boundary delta==0 (marker==now)" "B_luks_soak_not_elapsed"

# 7. Default soak (unset SOAK_DAYS → 3) with an elapsed marker still holds.
reset_def; unset 'DEF[GIT_DATA_LUKS_SOAK_DAYS]'; run_with_def
assert_zero "default soak days (3) with 4d-elapsed marker → exit 0"

# 8. Positive-tolerance / boundary cases — a future OVER-strict regression must go RED here.
# 8a. Soak boundary: marker exactly soak_days old → delta >= soak_secs → passes.
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$BOUNDARY_CUTOVER"; run_with_def
assert_zero "soak boundary (marker exactly 3d old) → exit 0"
# 8b. Extra valid host beyond web-1/web-2, allowlist all-in-roster incl. web-2's addr →
#     still PASSES (extra roster hosts not yet in the allowlist are tolerated).
reset_def
DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11","web-3":"10.0.1.12"}'
DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.10,10.0.1.11'
run_with_def
assert_zero "roster with extra host + allowlist all-in-roster (web-2 addr present) → exit 0"
# 8c. tz-offset (+02:00) marker equal to the 4d-ago instant → parses & elapsed → passes.
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$TZOFFSET_CUTOVER"; run_with_def
assert_zero "tz-offset (+02:00) cutover marker accepted & elapsed → exit 0"

# --- Minimum-cardinality guard (an empty loop must not GREEN with zero coverage) ---
MIN_CASES=58
echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed, ${TOTAL} total ==="
if [[ "$TOTAL" -lt "$MIN_CASES" ]]; then
  echo "GUARD FAIL: ran ${TOTAL} assertions, expected >= ${MIN_CASES}" >&2
  exit 2
fi
if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
