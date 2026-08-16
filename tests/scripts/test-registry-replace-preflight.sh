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
#
# STUB_RUNS_DRAIN_AFTER makes the stub state-dependent: it returns STUB_RUNS_JSON for that many
# calls, then `[]`. That is what lets P3's WAIT arm be tested for real — a stub with a single
# fixed answer can only prove "refuses immediately" or "never refuses", never "waited, then
# proceeded once the push drained", which is the behaviour the modal delivery path depends on.
mk_runs() {
  cat > "$TMP/gh.sh" <<'STUB'
#!/usr/bin/env bash
if [[ -n "${STUB_RUNS_RC:-}" && "${STUB_RUNS_RC}" != "0" ]]; then exit "${STUB_RUNS_RC}"; fi
if [[ -n "${STUB_RUNS_DRAIN_AFTER:-}" ]]; then
  cnt=0
  [[ -f "$STUB_CALL_FILE" ]] && cnt="$(cat "$STUB_CALL_FILE")"
  cnt=$(( cnt + 1 )); printf '%s' "$cnt" > "$STUB_CALL_FILE"
  if [[ "$cnt" -gt "$STUB_RUNS_DRAIN_AFTER" ]]; then printf '%s' '[]'; exit 0; fi
fi
printf '%s' "${STUB_RUNS_JSON:-[]}"
exit 0
STUB
  chmod +x "$TMP/gh.sh"
}
mk_query; mk_runs

run_sut() {
  # `env -u GITHUB_ACTIONS` IS LOAD-BEARING, not hygiene. The SUT refuses every command seam when
  # GITHUB_ACTIONS is set (the production-path guard), and CI sets it to `true` for every job. So
  # without this the whole suite measured 18/18 on a developer laptop and 6/18 in the CI job that
  # actually gates the merge — the exact green-here-red-there shape this PR exists to remove.
  # The one test that NEEDS the guard active sets GITHUB_ACTIONS=true explicitly, downstream.
  # WAIT_SECS=0 by default so the ordinary P3 cases assert the REFUSAL without sleeping; the two
  # wait-arm tests below override it. A caller may pre-set it in the environment.
  #
  # Args before a literal `--` are STUB_*/env assignments; args after it are passed to the SUT
  # itself. Without the split, `env … -- --manual bash "$SUT"` makes env treat `--manual` as the
  # COMMAND to run, so the flag never reaches the script and the test would pass for the wrong
  # reason — while asserting that a flag works.
  local -a _envs=() _args=()
  local _seen=0
  for _a in "$@"; do
    if [[ "$_a" == "--" ]]; then _seen=1; continue; fi
    if [[ "$_seen" == 1 ]]; then _args+=("$_a"); else _envs+=("$_a"); fi
  done
  env -u GITHUB_ACTIONS \
      REGISTRY_PREFLIGHT_WAIT_SECS="${WANT_WAIT_SECS:-0}" \
      REGISTRY_PREFLIGHT_POLL_SECS="${WANT_POLL_SECS:-1}" \
      STUB_CALL_FILE="$TMP/calls.$RANDOM" \
      REGISTRY_PREFLIGHT_QUERY_CMD="$TMP/query.sh" \
      REGISTRY_PREFLIGHT_RUNS_CMD="$TMP/gh.sh" \
      REGISTRY_PREFLIGHT_ZOT_WRITERS="web-platform-release.yml" \
      "${_envs[@]}" bash "$SUT" "${_args[@]+"${_args[@]}"}" 2>"$TMP/err" ; RC=$?
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
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"in_progress"}]' > "$TMP/out"
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

# --- P3: a QUEUED run must gate too. Merging fires the release and the dispatcher on the SAME
# push, so at preflight time the release is very likely queued. `--status` takes one value, so the
# old single-status filter reported 0 for exactly the case P3 exists to catch.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"queued"}]' > "$TMP/out"
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "P3 synthesized red: a QUEUED release run REFUSES the replace (not just in_progress)"
else
  fail "P3 missed a queued run: rc=$RC — this is the case the same-merge race actually produces"
fi

# --- P3 WAIT ARM: the modal delivery case must resolve ITSELF, not hand off to an operator. ----
# Merging a user_data change fires the release and this dispatcher on the same push, so "a
# release is queued" is the EXPECTED state. Refusing there made every ordinary delivery end in a
# comment telling a non-technical operator to type `gh workflow run`. These two pin the split:
# drains inside the budget -> proceed; still busy at the budget -> refuse.
WANT_WAIT_SECS=6 WANT_POLL_SECS=1 \
  run_sut STUB_LOCAL_CACHE_ROWS="" STUB_GHCR_ROWS="" \
          STUB_RUNS_JSON='[{"status":"queued"}]' STUB_RUNS_DRAIN_AFTER=2 > "$TMP/out"
if [[ "$RC" -eq 0 ]] && grep -q 'verdict=CLEAR' "$TMP/out" && grep -q 'waiting for the push to drain' "$TMP/out"; then
  pass "P3 wait: a queued run that DRAINS inside the budget proceeds without an operator step"
else
  fail "P3 wait: expected CLEAR after the writers drained, got rc=$RC: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi

WANT_WAIT_SECS=3 WANT_POLL_SECS=1 \
  run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"in_progress"}]' > "$TMP/out"
# The verdict line goes to stdout; abort()'s explanation goes to stderr. Assert both, so a
# refusal that stopped saying HOW LONG it waited still reds.
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out" && grep -q 'after waiting' "$TMP/err"; then
  pass "P3 wait: a run still in flight at the budget REFUSES, and says how long it waited"
else
  fail "P3 wait: expected a bounded wait then REFUSED, got rc=$RC: $(head -1 "$TMP/out")"
fi

# --- the manual arm is reachable BY FLAG, and downgrades P1 only. ---------------------------
# `REGISTRY_PREFLIGHT_MANUAL` was read by the script and set by NO caller, so the documented
# recovery from a dark replace did not exist while the dispatcher's refusal comment asserted it
# did. The supported route is now a flag, because github.event_name is unforgeable where an env
# var of the same name is exactly what the seam guard refuses.
LC_ROWS="$(printf 'pull registry=local-cache image=web\n')"
run_sut STUB_LOCAL_CACHE_ROWS="$LC_ROWS" STUB_GHCR_ROWS="" STUB_RUNS_JSON="[]" -- --manual > "$TMP/out" 2>/dev/null || true
if grep -q 'verdict=CLEAR' "$TMP/out" && grep -qi 'MANUAL re-fire' "$TMP/out"; then
  pass "manual arm: --manual downgrades P1 to a NOTE so a replace outage cannot block its own recovery"
else
  fail "manual arm: --manual did not reach the P1 skip — the documented recovery path is inert: $(head -2 "$TMP/out" | tr '\n' ' ')"
fi

# ...but it must NOT be a blanket bypass: P3 still gates under --manual.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON='[{"status":"in_progress"}]' -- --manual > "$TMP/out" 2>/dev/null || true
if [[ "$RC" -ne 0 ]] && grep -q 'predicate=P3' "$TMP/out"; then
  pass "manual arm: --manual skips P1 ONLY — P3 still refuses a replace mid-push"
else
  fail "manual arm: --manual widened into a blanket bypass, which would allow a replace mid-push: rc=$RC"
fi

# An unknown argument must be refused, not ignored — a silently-dropped flag is how a caller
# believes it passed --manual when it did not.
run_sut STUB_LOCAL_CACHE_ROWS="" STUB_RUNS_JSON="[]" -- --manaul > "$TMP/out" || true
if [[ "$RC" -ne 0 ]] && grep -qi 'unknown argument' "$TMP/err"; then
  pass "a misspelled flag is refused rather than silently ignored"
else
  fail "an unknown argument was accepted — a typo'd --manual would silently keep P1 gating: rc=$RC"
fi

# --- the seam guard: a seam set on the production path must REFUSE, not manufacture CLEAR ------
SEAM_OUT="$(env GITHUB_ACTIONS=true REGISTRY_PREFLIGHT_QUERY_CMD=/bin/true \
  REGISTRY_PREFLIGHT_RUNS_CMD=/bin/true bash "$SUT" 2>"$TMP/seamerr")"; SEAM_RC=$?
if [[ "$SEAM_RC" -ne 0 ]] && grep -q 'predicate=SEAM' <<<"$SEAM_OUT"; then
  pass "seam guard: a test seam set inside GitHub Actions REFUSES rather than reporting CLEAR"
else
  fail "seam guard absent: seams manufactured a verdict on the production path (rc=$SEAM_RC)"
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
# HARNESS CANARY + a floor that does NOT dispatch through the helper it guards. Neutering fail()
# to a no-op previously left this suite fully GREEN, and the floor's only voice was that same
# helper — so one edit disarmed the assertions AND their backstop.
_cp=$PASS; _cf=$FAIL
pass "canary: a true condition registers as PASS"
fail "canary: a false condition MUST register as FAIL (this line is EXPECTED)"
if [[ "$PASS" -ne $((_cp + 1)) || "$FAIL" -ne $((_cf + 1)) ]]; then
  echo "  FATAL: the assertion helpers are not counting — every verdict above is void." >&2
  exit 2
fi
FAIL=$((FAIL - 1))
TOTAL=$((PASS+FAIL))
if [[ "$TOTAL" -lt 22 ]]; then
  echo "  FATAL: anti-vacuity: ran $TOTAL assertions, expected >= 22. Fix the dispatch, do not lower the floor." >&2
  exit 2
fi

echo "=== Results: $PASS/$((PASS+FAIL)) passed, $FAIL failed ==="
[[ "$FAIL" -eq 0 ]]
