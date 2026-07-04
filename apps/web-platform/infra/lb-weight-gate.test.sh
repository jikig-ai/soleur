#!/usr/bin/env bash
# Tests for lb-weight-gate.sh — the fail-closed, SHAPE-ONLY programmatic ADR-068 §(c)
# LB-weight gate. Asserts on EXIT CODES (not summary literals), accumulate-then-exit.
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
GATE_RC=0
run_with_def() {
  local -a args=()
  local k
  for k in "${!DEF[@]}"; do args+=("${k}=${DEF[$k]}"); done
  local out rc
  # Guarded so set -e does not abort on the gate's (intended) non-zero exit.
  out=$(env -i PATH="$PATH" "${args[@]}" bash "$GATE" 2>/dev/null) && rc=0 || rc=$?
  GATE_OUT="$out"
  GATE_RC="$rc"
}

pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); TOTAL=$((TOTAL + 1)); }
fail() { echo "  FAIL: $1 (rc=${GATE_RC})"; FAIL=$((FAIL + 1)); TOTAL=$((TOTAL + 1)); }

assert_zero()    { if [[ "$GATE_RC" -eq 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_nonzero() { if [[ "$GATE_RC" -ne 0 ]]; then pass "$1"; else fail "$1"; fi; }
assert_stdout_contains() {
  if [[ "$GATE_OUT" == *"$2"* ]]; then pass "$1"; else fail "$1 — stdout missing '$2'"; fi
}

echo "=== lb-weight-gate.sh test suite ==="

# 1. Both conditions hold → exit 0 AND SHAPE-ONLY probe marker on stdout.
reset_def; run_with_def
assert_zero "both conditions hold → exit 0"
assert_stdout_contains "success prints requires_runtime_bind_probe=true" "requires_runtime_bind_probe=true"

# 2. Condition A — each single missing/empty relay var → non-zero.
reset_def; unset 'DEF[SOLEUR_PROXY_BIND]'; run_with_def
assert_nonzero "SOLEUR_PROXY_BIND missing → non-zero"
reset_def; DEF[SOLEUR_PROXY_BIND]=''; run_with_def
assert_nonzero "SOLEUR_PROXY_BIND empty → non-zero"

reset_def; unset 'DEF[SOLEUR_PROXY_PEER_ALLOWLIST]'; run_with_def
assert_nonzero "SOLEUR_PROXY_PEER_ALLOWLIST missing → non-zero"
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]=''; run_with_def
assert_nonzero "SOLEUR_PROXY_PEER_ALLOWLIST empty → non-zero"
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='  ,  '; run_with_def
assert_nonzero "SOLEUR_PROXY_PEER_ALLOWLIST all-whitespace/commas parses empty → non-zero"

reset_def; unset 'DEF[SOLEUR_HOST_ROSTER]'; run_with_def
assert_nonzero "SOLEUR_HOST_ROSTER missing → non-zero"
reset_def; DEF[SOLEUR_HOST_ROSTER]=''; run_with_def
assert_nonzero "SOLEUR_HOST_ROSTER empty → non-zero"

# 3. Roster missing web-2 specifically → non-zero.
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-3":"10.0.1.11"}'; run_with_def
assert_nonzero "roster without web-2 entry → non-zero"

# 4. Roster loader-rejects — the fail-closed checks the loader lacks.
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"10.0.1.10","web-2":"10.0.1.11","web-2":"10.0.1.99"}'; run_with_def
assert_nonzero "roster duplicate key → non-zero"
reset_def; DEF[SOLEUR_HOST_ROSTER]='["10.0.1.10","10.0.1.11"]'; run_with_def
assert_nonzero "roster non-object (array) → non-zero"
reset_def; DEF[SOLEUR_HOST_ROSTER]='not json at all'; run_with_def
assert_nonzero "roster invalid JSON → non-zero"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-2":"10.0.1.11","   ":"10.0.1.10"}'; run_with_def
assert_nonzero "roster whitespace-only key → non-zero"
reset_def; DEF[SOLEUR_HOST_ROSTER]='{"web-1":"","web-2":"10.0.1.11"}'; run_with_def
assert_nonzero "roster blank value → non-zero"

# 5. Allowlist ⊄ roster hosts → non-zero.
reset_def; DEF[SOLEUR_PROXY_PEER_ALLOWLIST]='10.0.1.11,10.9.9.9'; run_with_def
assert_nonzero "allowlist peer not in roster addresses → non-zero"

# 6. Condition B — git-data cut-over config-shape.
reset_def; DEF[GIT_DATA_STORE_ENABLED]='false'; run_with_def
assert_nonzero "GIT_DATA_STORE_ENABLED=false → non-zero"
reset_def; unset 'DEF[GIT_DATA_STORE_ENABLED]'; run_with_def
assert_nonzero "GIT_DATA_STORE_ENABLED missing → non-zero"

reset_def; unset 'DEF[GIT_DATA_LUKS_CUTOVER_AT]'; run_with_def
assert_nonzero "LUKS cutover marker absent → non-zero"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='not-a-timestamp'; run_with_def
assert_nonzero "LUKS cutover marker unparseable → non-zero"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]='2026-13-45T99:99:99Z'; run_with_def
assert_nonzero "LUKS cutover marker garbage-but-ISO-shaped → non-zero"
reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FUTURE_CUTOVER"; run_with_def
assert_nonzero "LUKS cutover marker future-dated → non-zero"

reset_def; DEF[GIT_DATA_LUKS_SOAK_DAYS]='0'; run_with_def
assert_nonzero "GIT_DATA_LUKS_SOAK_DAYS=0 → non-zero (floor)"
reset_def; DEF[GIT_DATA_LUKS_SOAK_DAYS]='-1'; run_with_def
assert_nonzero "GIT_DATA_LUKS_SOAK_DAYS negative → non-zero"

reset_def; DEF[GIT_DATA_LUKS_CUTOVER_AT]="$FRESH_CUTOVER"; run_with_def
assert_nonzero "soak not elapsed (1d < 3d) → non-zero"

# 7. Default soak (unset SOAK_DAYS → 3) with an elapsed marker still holds.
reset_def; unset 'DEF[GIT_DATA_LUKS_SOAK_DAYS]'; run_with_def
assert_zero "default soak days (3) with 4d-elapsed marker → exit 0"

# --- Minimum-cardinality guard (an empty loop must not GREEN with zero coverage) ---
MIN_CASES=24
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
