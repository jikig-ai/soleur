#!/usr/bin/env bash
# Tests for scripts/vendor-pin-gate-verdict.sh — the fail-closed verdict of
# the `vendor-pin-required` aggregator gate (#8203).
#
# The verdict is an ALLOW-LIST, so the interesting coverage is the DENY side:
# every state that is not explicitly enumerated must fail closed. A deny-list
# implementation (`!= 'failure'`) would pass T1/T2 and silently green T4-T11 —
# which is the point of enumerating them.
#
# The third argument is the detector's declared `vendor` flag; the skipped arm
# is bound to it (skipped is only admissible with vendor='false'), so the
# matrix exercises the flag on every row that could combine with skipped.
#
# Mirrors tests/scripts/test-tenant-integration-gate-verdict.sh (#5585) and
# tests/scripts/test-sentry-destroy-gate-verdict.sh (#6589), including their
# anti-vacuity floor (#7898).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERDICT="$REPO_ROOT/scripts/vendor-pin-gate-verdict.sh"
pass=0; fail=0

_report() {
  local label="$1" status="$2" detail="${3:-}"
  if [[ "$status" == "ok" ]]; then
    pass=$((pass + 1)); echo "[ok] $label"
  else
    fail=$((fail + 1)); echo "[FAIL] $label $detail" >&2
  fi
}

[[ -f "$VERDICT" ]] || { echo "ERROR: $VERDICT does not exist — RED phase expected this." >&2; exit 1; }

# _expect <want_rc> <label> <detect> <verify> <vendor_flag>
_expect() {
  local want="$1" label="$2" detect="${3-}" verify="${4-}" flag="${5-}"
  local rc=0
  bash "$VERDICT" "$detect" "$verify" "$flag" >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq "$want" ]]; then
    _report "$label" ok
  else
    _report "$label" fail "got rc=$rc want rc=$want (detect='$detect' verify='$verify' flag='$flag')"
  fi
}

# ── PASS branches (the only two) ────────────────────────────────────────────
# T1: vendored-tree PR, every NOTICE upstream-blob-sha resolved upstream.
_expect 0 "T1 detect=success verify=success flag=true -> PASS" success success true
# T2: PR does not touch the vendored surface (flag=false), or merge_group
# candidate -> verify skipped.
_expect 0 "T2 detect=success verify=skipped flag=false -> PASS (unrelated PR / merge_group)" success skipped false

# ── FLAG-BINDING branches — the skipped arm bound to the declared flag ──────
# A skipped worker is only admissible when detection positively declared the
# vendored surface untouched. flag=true or flag=<empty> with a skipped worker
# means "vendored diff, nothing verified" — the exact fail-open this gate
# exists to close (a detector step exiting between checkout and
# $GITHUB_OUTPUT produces success+empty+skipped = green without this check).
_expect 1 "T2b verify=skipped flag=true -> FAIL closed (skipped worker on vendored diff)" success skipped true
_expect 1 "T2c verify=skipped flag=<empty> -> FAIL closed (skipped worker, flag never emitted)" success skipped ""

# ── FAIL-CLOSED branches ────────────────────────────────────────────────────
# T3: the verification found an unresolvable upstream blob — the #8181 binding
# broken. The whole point.
_expect 1 "T3 detect=success verify=failure -> FAIL (unresolved upstream blob)" success failure true
# T4: a cancelled verification taught us nothing. Must not green.
_expect 1 "T4 detect=success verify=cancelled -> FAIL closed" success cancelled true
# T5: empty verify result — the job never ran because its chain broke. This is
# the state a deny-list (`!= 'failure'`) would silently green, laundering
# "unknown" into "approved".
_expect 1 "T5 detect=success verify=<empty> -> FAIL closed (never-ran, not approved)" success "" true
# T6: detect-changes failed -> we do not know whether the vendored surface was
# touched (DROP-1 fail-open class).
_expect 1 "T6 detect=failure -> FAIL closed (path detection unknown)" failure success true
_expect 1 "T6b detect=failure verify=skipped -> FAIL closed" failure skipped false
# T7: detect-changes cancelled.
_expect 1 "T7 detect=cancelled -> FAIL closed" cancelled success true
# T8: detect-changes skipped — cannot happen today, but must not fail open if
# it ever can (the DROP-1 fail-open class).
_expect 1 "T8 detect=skipped -> FAIL closed" skipped success true
# T9: both empty (workflow-level failure).
_expect 1 "T9 detect=<empty> verify=<empty> -> FAIL closed" "" "" ""
# T10: a future GitHub-added result string must not fail open.
_expect 1 "T10 unknown future result string -> FAIL closed" success "neutral" true
# T11: a future flag value must not fail open on the skipped arm.
_expect 1 "T11 verify=skipped flag=maybe -> FAIL closed (unknown flag)" success skipped "maybe"

# ── The deny-list mutation ──────────────────────────────────────────────────
# Proves the allow-list is load-bearing: a `!= failure` implementation passes
# T1/T2/T3 and silently greens T4/T5. If this test ever goes vacuous, the
# guard has been rewritten as a deny-list.
t_allowlist_is_loadbearing() {
  local denylist_rc=0
  # Simulate the deny-list a well-meaning refactor would write.
  bash -c '
    detect="${1:-}"; verify="${2:-}"
    if [[ "$verify" != "failure" ]]; then exit 0; fi
    exit 1
  ' _ success "" >/dev/null 2>&1 || denylist_rc=$?
  local real_rc=0
  bash "$VERDICT" success "" true >/dev/null 2>&1 || real_rc=$?
  if [[ "$denylist_rc" -eq 0 && "$real_rc" -eq 1 ]]; then
    _report "T12 allow-list rejects the empty result a deny-list would green (non-vacuity)" ok
  else
    _report "T12 allow-list rejects the empty result a deny-list would green" fail \
      "denylist_rc=$denylist_rc (want 0) real_rc=$real_rc (want 1)"
  fi
}
t_allowlist_is_loadbearing

# The PASS message must name both inputs so a CI reader can tell WHY it passed —
# "PASS" alone cannot distinguish "verification was green" from "verification
# never ran".
t_pass_message_names_inputs() {
  local out; out=$(bash "$VERDICT" success skipped false 2>&1)
  if [[ "$out" == *"detect-changes=success"* && "$out" == *"verify-upstream-blobs=skipped"* ]]; then
    _report "T13 PASS message names both job results" ok
  else
    _report "T13 PASS message names both job results" fail "got: $out"
  fi
}
t_pass_message_names_inputs

# ── Skipped-arm disclosure, both directions, with an isolated summary file ──
# A green required check on a PR where the verification never ran must carry
# the ::notice, not read as a verified tree — and the arm that DID verify must
# not claim it was skipped. GITHUB_STEP_SUMMARY is pointed at a temp file so
# the summary assertions are isolated from any ambient env.
_summary_file=$(mktemp)
trap 'rm -f "$_summary_file"' EXIT

skipped_out=$(GITHUB_STEP_SUMMARY="$_summary_file" bash "$VERDICT" success skipped false 2>&1)
if [[ "$skipped_out" == *"::notice::"* && "$skipped_out" == *"SKIPPED arm"* ]]; then
  _report "T14 skipped PASS arm emits the honesty ::notice" ok
else
  _report "T14 skipped PASS arm emits the honesty ::notice" fail "got: $skipped_out"
fi
if [[ "$skipped_out" == *"did NOT execute against this tree"* ]]; then
  _report "T14b skipped notice states the verification did not execute" ok
else
  _report "T14b skipped notice states the verification did not execute" fail "got: $skipped_out"
fi
if grep -q 'SKIPPED arm' "$_summary_file"; then
  _report "T14c skipped arm lands the disclosure in \$GITHUB_STEP_SUMMARY" ok
else
  _report "T14c skipped arm lands the disclosure in \$GITHUB_STEP_SUMMARY" fail "summary file: $(cat "$_summary_file")"
fi

# Negative half: the verified-success arm must not emit the skipped notice and
# must not write to the summary — an unconditional notice would pass every
# check above while telling every green PR its verification never ran.
: >"$_summary_file"
ran_out=$(GITHUB_STEP_SUMMARY="$_summary_file" bash "$VERDICT" success success true 2>&1)
if [[ "$ran_out" == *"::notice::"* ]]; then
  _report "T15 PASS/success arm emits no skipped-arm notice" fail "got: $ran_out"
else
  _report "T15 PASS/success arm emits no skipped-arm notice" ok
fi
if [[ -s "$_summary_file" ]]; then
  _report "T15b PASS/success arm writes nothing to \$GITHUB_STEP_SUMMARY" fail "summary file: $(cat "$_summary_file")"
else
  _report "T15b PASS/success arm writes nothing to \$GITHUB_STEP_SUMMARY" ok
fi

# An unset GITHUB_STEP_SUMMARY (local runs) must not turn the disclosure into a
# crash: the annotation still goes out and the verdict still exits 0.
if unset_out=$(env -u GITHUB_STEP_SUMMARY bash "$VERDICT" success skipped false 2>&1) &&
  [[ "$unset_out" == *"::notice::"* ]]; then
  _report "T16 skipped arm still exits 0 and annotates with GITHUB_STEP_SUMMARY unset" ok
else
  _report "T16 skipped arm still exits 0 and annotates with GITHUB_STEP_SUMMARY unset" fail
fi

# ── Cancelled arm diagnostics (#7055). `cancelled` still fails closed (T4),
# but the DIAGNOSTIC must name eviction and the remedy, or the author debugs a
# verification failure that does not exist — and a FAILED detect must not
# inherit the eviction explanation, which would misdiagnose a real detection
# failure as a concurrency artifact. ──
evict_err=$(bash "$VERDICT" success cancelled true 2>&1 >/dev/null) || true
if [[ "$evict_err" == *"EVICTION"* ]]; then
  _report "T17 verify=cancelled diagnostic names concurrency eviction" ok
else
  _report "T17 verify=cancelled diagnostic names concurrency eviction" fail "got: $evict_err"
fi
if [[ "$evict_err" == *"Re-run failed jobs"* ]]; then
  _report "T17b verify=cancelled diagnostic names the re-run remedy" ok
else
  _report "T17b verify=cancelled diagnostic names the re-run remedy" fail "got: $evict_err"
fi
noevict_err=$(bash "$VERDICT" failure cancelled true 2>&1 >/dev/null) || true
if [[ "$noevict_err" == *"EVICTION"* ]]; then
  _report "T17c detect=failure does not inherit the eviction diagnostic" fail "got: $noevict_err"
else
  _report "T17c detect=failure does not inherit the eviction diagnostic" ok
fi

# Generic fail paths must surface as an ::error:: annotation, not a silent
# non-zero — the check's red state has to be self-explaining in the run log.
generic_err=$(bash "$VERDICT" failure success true 2>&1 >/dev/null) || true
if [[ "$generic_err" == *"::error::"* ]]; then
  _report "T18 generic FAIL arm emits an ::error:: annotation" ok
else
  _report "T18 generic FAIL arm emits an ::error:: annotation" fail "got: $generic_err"
fi

# ── anti-vacuity floor (#7898 review). A floor, not an equality — adding a
# row must not red the suite; raise it when you add one. Emitted with printf +
# exit rather than through _report, because a floor dispatched through the
# helpers it backstops is disarmed by the same one-line edit that disarms them.
readonly MIN_ASSERTIONS=26
if [[ "$((pass + fail))" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] only %d assertions ran; floor is %d -- the suite was gutted\n' \
    "$((pass + fail))" "$MIN_ASSERTIONS" >&2
  exit 1
fi

echo "=== $pass passed, $fail failed ==="
[[ "$fail" -eq 0 ]]
