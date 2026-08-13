#!/usr/bin/env bash
# Tests scripts/registry-replace-preflight.sh (#7555) — the read-only preflight for the
# registry-host-replace dispatcher.
#
# Plan AC16 requires the pull-path pre-check to be "exercised by a test with a synthesized red
# reading". Every fixture here is SYNTHESIZED (cq-test-fixtures-synthesized-only); nothing is
# captured from a live query.
#
# The two cases that matter most are the ones a happy-path suite would omit:
#   * P0 fail-closed — a query that could not RUN must never read as "no events found".
#   * P2 must NOT gate — its emitter has been unreachable since #7071, so a gate keyed on it
#     would read CLEAN whether the fleet is healthy or its fallback is destroyed.

set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$ROOT/scripts/registry-replace-preflight.sh"

PASS=0; FAIL=0
pass() { echo "  pass: $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -r "$SUT" ]] || { echo "  FAIL: SUT not readable at $SUT"; echo "=== Results: 0/1 passed, 1 failed ==="; exit 1; }

TMP="$(mktemp -d)" || exit 2
trap 'rm -rf "$TMP"' EXIT

# --- stubs -------------------------------------------------------------------------------
# QUERY stub: dispatches on the --grep value, so a stub that ignores argv cannot pass. Exits
# with STUB_QUERY_RC when set, which is how the P0 credential arm is driven.
mk_query() {
  cat > "$TMP/query.sh" <<'STUB'
#!/usr/bin/env bash
marker=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --grep) marker="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$marker" ]] || { echo "stub: no --grep passed (the SUT must name what it queries)" >&2; exit 64; }
if [[ -n "${STUB_QUERY_RC:-}" && "${STUB_QUERY_RC}" != "0" ]]; then exit "${STUB_QUERY_RC}"; fi
case "$marker" in
  'registry=local-cache')   printf '%s' "${STUB_LOCAL_CACHE_ROWS:-}" ;;
  'registry=ghcr-fallback') printf '%s' "${STUB_GHCR_ROWS:-}" ;;
  *) : ;;
esac
exit 0
STUB
  chmod +x "$TMP/query.sh"
}
# gh stub: only `run list` is used.
mk_runs() {
  cat > "$TMP/gh.sh" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${STUB_RUNS_RC:-}" && "${STUB_RUNS_RC}" != "0" ]]; then exit "${STUB_RUNS_RC}"; fi
printf '%s' "${STUB_RUNS_JSON:-[]}"
exit 0
STUB
  chmod +x "$TMP/gh.sh"
}
mk_query; mk_runs

run_sut() {
  env REGISTRY_PREFLIGHT_QUERY_CMD="$TMP/query.sh" \
      REGISTRY_PREFLIGHT_RUNS_CMD="$TMP/gh.sh" \
      "$@" bash "$SUT" 2>"$TMP/err" ; RC=$?
}

# --- CONTROL: everything clean -> CLEAR ---------------------------------------------------
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'verdict=CLEAR' "$TMP/out"; then
  pass "control: a clean pull path and no in-flight release yields verdict=CLEAR"
else
  fail "control: expected CLEAR/rc=0, got rc=$RC: $(head -1 "$TMP/out")"
fi

# --- P0: the query could not RUN (missing credentials, rc=3) -> REFUSED, fail-closed -------
# The whole point: a failed read must never be reported as "no local-cache events found".
run_sut STUB_QUERY_RC=3 STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P0' "$TMP/out"; then
  pass "P0 synthesized red: a credential failure (rc=3) REFUSES rather than reading as clean"
else
  fail "P0: expected REFUSED/P0, got rc=$RC: $(head -1 "$TMP/out")"
fi
if grep -qi 'not a clean reading' "$TMP/err"; then
  pass "P0 says WHY on stderr (a failed read is not a clean reading)"
else
  fail "P0 aborted mutely — the operator cannot tell a dead query from a healthy fleet"
fi

# A non-credential query failure must also fail closed, not fall through.
run_sut STUB_QUERY_RC=7 STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P0' "$TMP/out"; then
  pass "P0 synthesized red: a generic query failure (rc=7) also REFUSES"
else
  fail "P0 generic failure fell through: rc=$RC: $(head -1 "$TMP/out")"
fi

# --- P1: sustained local-cache pulls -> REFUSED (the #6400 hazard) ------------------------
run_sut STUB_LOCAL_CACHE_ROWS="$(printf 'pull registry=local-cache image=web\npull registry=local-cache image=inngest\n')" \
        STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P1' "$TMP/out"; then
  pass "P1 synthesized red: local-cache pull events REFUSE the replace"
else
  fail "P1: expected REFUSED/P1, got rc=$RC: $(head -1 "$TMP/out")"
fi
if grep -qi 'last' "$TMP/err"; then
  pass "P1 explains the hazard (the fleet is on its last tier)"
else
  fail "P1 aborted without naming why local-cache is disqualifying"
fi

# --- P2: MUST NOT GATE. A ghcr-fallback hit is advisory only. ------------------------------
# If a future edit promotes P2 to a gate, this case flips and the suite reds. That is the point:
# the operand is dark since #7071, so gating on it would read CLEAN in both worlds.
run_sut STUB_LOCAL_CACHE_ROWS="" \
        STUB_GHCR_ROWS="$(printf 'pull registry=ghcr-fallback image=web\n')" \
        STUB_RUNS_JSON="[]" > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'verdict=CLEAR' "$TMP/out"; then
  pass "P2 is ADVISORY: a ghcr-fallback hit does NOT gate the dispatch"
else
  fail "P2 gated the dispatch — its emitter is unreachable since #7071, so it cannot be a gate (rc=$RC)"
fi
if grep -q 'ghcr_fallback_hits=1' "$TMP/out"; then
  pass "P2 still REPORTS the count it refuses to gate on"
else
  fail "P2 dropped the count entirely — advisory must mean reported, not ignored"
fi
if grep -qi 'advisory' "$TMP/out"; then
  pass "P2's zero is explicitly marked as not-evidence in the output"
else
  fail "P2 emitted a bare count with no note that zero says nothing (a future reader will gate on it)"
fi

# --- P3: an in-progress release -> REFUSED -------------------------------------------------
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"databaseId":123}]' > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "P3 synthesized red: an in-progress release run REFUSES the replace"
else
  fail "P3: expected REFUSED/P3, got rc=$RC: $(head -1 "$TMP/out")"
fi

# A failure to LIST runs must fail closed too — unknown is not zero.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_RC=1 > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "P3 fail-closed: an unlistable run set REFUSES rather than assuming zero"
else
  fail "P3 assumed zero in-flight releases when it could not list them: rc=$RC"
fi

# --- P4 must stay absent, and the reason must stay recorded -------------------------------
if grep -q 'P4' "$SUT" && grep -qi 'DELIBERATELY ABSENT' "$SUT"; then
  pass "P4's deliberate absence is recorded in-file (or it gets re-added)"
else
  fail "P4's exclusion rationale is missing — a serving probe will be re-added"
fi
if grep -qiE 'GET /v2/|serving probe' "$SUT" && ! grep -qE '^\s*[^#]*curl.*(/v2/|health)' "$SUT"; then
  pass "P4 is named but not implemented (no live serving probe in the code path)"
else
  fail "a live serving probe appears to have been added — see ADR-169 ground 2"
fi

# --- The anti-recoupling guard the CTO decision requires ----------------------------------
if grep -q 'registry-pull-path-health.sh' "$SUT" && grep -qi 'NOT scripts/registry-pull-path-health.sh' "$SUT"; then
  pass "the header pre-empts re-coupling to the D10 recut gate"
else
  fail "the header does not warn against calling registry-pull-path-health.sh — it will be re-coupled"
fi
if grep -qE '^\s*[^#]*registry-pull-path-health\.sh' "$SUT"; then
  fail "the preflight actually INVOKES the D10 recut gate — a volume-preserving replace must not"
else
  pass "the preflight does not invoke the D10 recut gate"
fi

# --- anti-vacuity floor -------------------------------------------------------------------
TOTAL=$((PASS+FAIL))
if [[ "$TOTAL" -lt 15 ]]; then
  fail "anti-vacuity: ran $TOTAL assertions, expected >= 15. Fix the dispatch, do not lower the floor."
fi

echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
