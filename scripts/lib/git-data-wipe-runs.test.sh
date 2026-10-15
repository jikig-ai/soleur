#!/usr/bin/env bash
# Suite for scripts/lib/git-data-wipe-runs.sh (#10138, design W3 interim guard and the wipe_finish origin-run read).
#
# PROPERTY. (1) A wipe dispatch is refused when the run history cannot prove that no rollback (and, until the
# rollback arm clears the stamp, no legacy-titled run) happened after the soak stamp: a list that is unreadable,
# does not reach back to the stamp, or holds an unclassifiable title refuses. (2) wipe_finish accepts an origin run
# only when its title is exactly `git-data wipe <volume_id>`, it ran on main by workflow_dispatch and the named
# gate step of the job `wipe` concluded `success`. Nothing is read as "fine" when it could not be read.
#
# INSTRUMENT. Every fixture is SYNTHESIZED with jq -n (no live run ids, no live volume ids). The mutation battery
# edits a COPY of the library (under an assert_fixture_dir-guarded mktemp -d), confirms the edit landed on the
# expected number of diff lines, sources the copy in a subshell and requires the NAMED case to go RED.
#
# Run: bash scripts/lib/git-data-wipe-runs.test.sh
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/git-data-wipe-runs.sh"
cd "$REPO_ROOT" || { echo "FATAL: cannot cd to $REPO_ROOT" >&2; exit 2; }

PASS=0; FAIL=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1" >&2; }

# INSTRUMENT SELF-TEST: drive both helpers once; refuse to continue unless both counters moved.
pass "instrument self-test (pass)"
fail "instrument self-test (fail) — EXPECTED, subtracted below"
if [[ "$PASS" -ne 1 || "$FAIL" -ne 1 ]]; then
  printf '[FATAL] INSTRUMENT BROKEN: self-test left PASS=%d FAIL=%d, expected 1/1.\n' "$PASS" "$FAIL" >&2
  exit 2
fi
SELFTEST_FAILS=1    # proven by the check immediately above (PASS==1 and FAIL==1 there)
FAIL=$(( FAIL - SELFTEST_FAILS ))

[[ -f "$LIB" ]] || { printf '[FATAL] library not found: scripts/lib/git-data-wipe-runs.sh\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

TMPD="$(mktemp -d -t git-data-wipe-runs-test.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
cleanup() { rm -rf "$TMPD"; }
trap cleanup EXIT

# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires the verbatim body).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$TMPD"
MUT="$TMPD/mut"
assert_fixture_dir "$MUT"
mkdir -p "$MUT" || { echo "FATAL: mkdir $MUT" >&2; exit 2; }

# shellcheck source=scripts/lib/git-data-wipe-runs.sh
source "$LIB" || { printf '[FATAL] the library did not source\n' >&2; exit 2; }

# ---------------------------------------------------------------------------------------------------
# Fixtures. STAMP is the soak stamp (epoch); BEFORE/AFTER are ISO times either side of it.
# ---------------------------------------------------------------------------------------------------
STAMP_ISO="2026-10-01T12:00:00Z"
STAMP="$(date -u -d "$STAMP_ISO" +%s)"
BEFORE="2026-09-30T12:00:00Z"
AFTER="2026-10-02T12:00:00Z"
LEGACY='git-data cutover (#5274 / ADR-220 / ADR-239)'
run() { # TITLE CREATED [BRANCH] [EVENT] [CONCLUSION]
  jq -cn --arg t "$1" --arg c "$2" --arg b "${3:-main}" --arg e "${4:-workflow_dispatch}" --arg k "${5:-success}" \
    '{databaseId: 1, displayTitle: $t, createdAt: $c, headBranch: $b, event: $e, conclusion: $k}'
}
list() { jq -cs '.' ; }                       # rows on stdin -> a JSON array
mklist() { local r; for r in "$@"; do printf '%s\n' "$r"; done | list; }

# check_out LABEL EXPECTED-TOKEN EXPECTED-RC -- COMMAND...   (token = the whole stdout, rc = the function's)
check_out() {
  local label="$1" want="$2" wrc="$3" out rc=0; shift 4
  out="$("$@" 2>/dev/null)" || rc=$?
  if [[ "$out" == "$want" && "$rc" -eq "$wrc" ]]; then pass "$label -> $out (rc $rc)"
  else fail "$label: got '$out' rc=$rc, expected '$want' rc=$wrc"; fi
}

# ---------------------------------------------------------------------------------------------------
echo "== constants"
[[ "$WIPE_RUNS_LIST_LIMIT" == 100 ]] && pass "K1 the run-list limit is the explicit 100" || fail "K1 WIPE_RUNS_LIST_LIMIT is '$WIPE_RUNS_LIST_LIMIT', expected 100"
[[ "$WIPE_ORIGIN_JOB" == wipe && "$WIPE_ORIGIN_DETACH_STEP" == wipe_detach_gate && "$WIPE_ORIGIN_DELETE_STEP" == wipe_delete_gate ]] \
  && pass "K2 origin job and gate step names are the pinned wipe / wipe_detach_gate / wipe_delete_gate" \
  || fail "K2 origin names differ: $WIPE_ORIGIN_JOB $WIPE_ORIGIN_DETACH_STEP $WIPE_ORIGIN_DELETE_STEP"
[[ "$WIPE_LEGACY_TITLE" == "$LEGACY" ]] && pass "K3 the legacy title constant is the exact workflow name" || fail "K3 legacy title constant differs"

# ---------------------------------------------------------------------------------------------------
echo "== wipe_run_title_class"
tc() { check_out "T $1" "$2" 0 -- wipe_run_title_class "$1"; }
tc 'git-data wipe 123' wipe
tc 'git-data wipe_finish 999999999999' wipe_finish
tc 'git-data wipe_check 7' wipe_check
tc 'git-data snapshot_clear 7' snapshot_clear
tc 'git-data snapshot_clear' wipe_other
tc 'git-data snapshot_clear 7 ' wipe_other
tc 'git-data snapshot_clear abc' wipe_other
tc 'git-data snapshot_clear 1234567890123' wipe_other
tc 'git-data wipe 0123' wipe
tc 'git-data proof' other
tc 'git-data flip' other
tc 'git-data rollback' other
tc 'git-data unfreeze' other
tc 'git-data redeploy' other
tc "$LEGACY" legacy
tc 'git-data wipe 12x' wipe_other
tc 'git-data wipe 1234567890123' wipe_other
tc 'git-data wipe' wipe_other
tc 'git-data wipe ' wipe_other
tc 'git-data wiper 1' wipe_other
tc 'git-data wipe_finish ' wipe_other
tc $'git-data wipe 12\n' wipe_other
tc 'git-data rollback 12' unparseable
tc 'git-data proof ' unparseable
tc 'git-data  wipe 1' unparseable
tc 'Git-data wipe 1' unparseable
tc "$LEGACY " unparseable
tc 'something else' unparseable
tc '' unparseable
tc $'git-data proof\n' unparseable

# ---------------------------------------------------------------------------------------------------
echo "== wipe_last_rollback_epoch (the W3 interim guard)"
LR() { wipe_last_rollback_epoch "$1" "$STAMP"; }
ROLL_AFTER="$(mklist "$(run 'git-data flip' "$BEFORE")" "$(run 'git-data rollback' "$AFTER" main workflow_dispatch failure)")"
case_rollback_refuses() { # [list] -- expects the rollback refusal
  local out rc=0; out="$(LR "${1-$ROLL_AFTER}" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_precondition_rollback_after_stamp && "$rc" -eq 5 ]]
}
case_legacy_refuses() {
  local out rc=0; out="$(LR "${1-$(mklist "$(run "$LEGACY" "$AFTER")")}" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_precondition_legacy_run_after_stamp && "$rc" -eq 5 ]]
}
FULL_AFTER="$(for i in $(seq 1 100); do run 'git-data proof' "$AFTER"; done | list)"
case_unreaching_refuses() {
  local out rc=0; out="$(LR "${1-$FULL_AFTER}" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_precondition_run_list_unreaching && "$rc" -eq 5 ]]
}
case_wipe_other_ignored() {
  local out rc=0; out="$(LR "$(mklist "$(run 'git-data wipe 12x' "$AFTER")")" 2>/dev/null)" || rc=$?
  [[ "$out" == ok && "$rc" -eq 0 ]]
}
case_nonmain_ignored() {
  local out rc=0; out="$(LR "$(mklist "$(run 'git-data rollback' "$AFTER" feature/x)" "$(run 'git-data rollback' "$AFTER" main schedule)")" 2>/dev/null)" || rc=$?
  [[ "$out" == ok && "$rc" -eq 0 ]]
}
case_newline_title_ignored() { # a title ending in a newline is NOT the rollback title nor a clean `other`
  local out rc=0; out="$(LR "$(mklist "$(run $'git-data rollback\n' "$AFTER")")" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_precondition_run_title_unparseable && "$rc" -eq 5 ]]
}
case_at_stamp_refuses() {
  local out rc=0; out="$(LR "$(mklist "$(run 'git-data rollback' "$STAMP_ISO")")" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_precondition_rollback_after_stamp && "$rc" -eq 5 ]]
}
check_out "G1 an empty history is ok" ok 0 -- LR '[]'
check_out "G2 rollback and legacy runs OLDER than the stamp are ignored" ok 0 -- LR "$(mklist "$(run 'git-data rollback' "$BEFORE")" "$(run "$LEGACY" "$BEFORE")" "$(run 'git-data unfreeze' "$BEFORE")")"
case_rollback_refuses && pass "G3 a rollback run newer than the stamp refuses wipe_precondition_rollback_after_stamp (a FAILED rollback counts: its conclusion is not an input)" || fail "G3 a newer rollback was not refused"
case_at_stamp_refuses && pass "G4 a rollback created AT the stamp second refuses (>=, fail closed)" || fail "G4 a rollback at the stamp second was accepted"
case_legacy_refuses && pass "G5 a legacy-titled run newer than the stamp refuses wipe_precondition_legacy_run_after_stamp" || fail "G5 a newer legacy run was not refused"
case_wipe_other_ignored && pass "G6 an off-pattern wipe title (a refused dispatch with a free-text volume_id) is ignored" || fail "G6 a wipe_other title blocked or confused the guard"
check_out "G7 wipe, wipe_finish, wipe_check, proof, flip, unfreeze, redeploy runs after the stamp are all ok" ok 0 -- LR "$(mklist \
  "$(run 'git-data wipe 5' "$AFTER")" "$(run 'git-data wipe_finish 5' "$AFTER")" "$(run 'git-data wipe_check 5' "$AFTER")" "$(run 'git-data snapshot_clear 5' "$AFTER")" \
  "$(run 'git-data proof' "$AFTER")" "$(run 'git-data flip' "$AFTER")" "$(run 'git-data unfreeze' "$AFTER")" "$(run 'git-data redeploy' "$AFTER")")"
check_out "G8 an unclassifiable title after the stamp refuses (never a skip)" wipe_precondition_run_title_unparseable 5 -- LR "$(mklist "$(run 'who knows' "$AFTER")")"
check_out "G9 an unclassifiable title BEFORE the stamp is ignored" ok 0 -- LR "$(mklist "$(run 'who knows' "$BEFORE")")"
case_unreaching_refuses && pass "G10 a FULL list (100 rows) whose oldest row is newer than the stamp refuses wipe_precondition_run_list_unreaching" || fail "G10 a full list that does not reach the stamp was accepted"
check_out "G10b the same 99 rows (list not full) are ok: the window provably holds every run" ok 0 -- LR "$(for i in $(seq 1 99); do run 'git-data proof' "$AFTER"; done | list)"
check_out "G10c a full list whose oldest row is older than the stamp is ok" ok 0 -- LR "$( { for i in $(seq 1 99); do run 'git-data proof' "$AFTER"; done; run 'git-data proof' "$BEFORE"; } | list)"
case_nonmain_ignored && pass "G11 a rollback-titled run on another branch, or not by workflow_dispatch, is ignored" || fail "G11 a non-main or non-dispatch row was read as a rollback"
check_out "G12 a mixed list with a rollback hidden among 50 later clean rows still refuses" wipe_precondition_rollback_after_stamp 5 -- LR "$( { for i in $(seq 1 50); do run 'git-data proof' "$AFTER"; done; run 'git-data rollback' "$AFTER"; } | list)"
case_newline_title_ignored && pass "G13 'git-data rollback<newline>' is not a rollback title and not a known title: unparseable refusal (\\z anchoring)" || fail "G13 a newline-suffixed title slipped through"
check_out "G14 not JSON" wipe_precondition_run_list_unreadable 5 -- LR 'not json'
check_out "G14b an object instead of an array" wipe_precondition_run_list_unreadable 5 -- LR '{}'
check_out "G14c an empty body" wipe_precondition_run_list_unreadable 5 -- LR ''
check_out "G14d a row without createdAt" wipe_precondition_run_list_unreadable 5 -- LR '[{"displayTitle":"git-data proof","headBranch":"main","event":"workflow_dispatch"}]'
check_out "G14e a row with a date-only createdAt" wipe_precondition_run_list_unreadable 5 -- LR '[{"displayTitle":"git-data proof","createdAt":"2026-10-02","headBranch":"main","event":"workflow_dispatch"}]'
check_out "G14f a non-object row" wipe_precondition_run_list_unreadable 5 -- LR '["x"]'
check_out "G14g a null title" wipe_precondition_run_list_unreadable 5 -- LR '[{"displayTitle":null,"createdAt":"2026-10-02T00:00:00Z","headBranch":"main","event":"workflow_dispatch"}]'
check_out "G14h a malformed row OLDER than the stamp still refuses (it could hide anything)" wipe_precondition_run_list_unreadable 5 -- LR "$(jq -cs '.' <<<"$(run 'git-data proof' "$BEFORE") {\"displayTitle\":\"x\"}")"
check_out "G15 a missing stamp argument is a wiring fault" wipe_runs_bad_args 2 -- wipe_last_rollback_epoch '[]' ''
check_out "G15b a non-numeric stamp argument is a wiring fault" wipe_runs_bad_args 2 -- wipe_last_rollback_epoch '[]' 'yesterday'
check_out "G16 (must-PASS) extra unknown fields and another key order are fine" ok 0 -- LR '[{"zzz":1,"event":"workflow_dispatch","headBranch":"main","createdAt":"2026-09-30T12:00:00Z","displayTitle":"git-data rollback","extra":{"a":[1]}}]'
if ! case_rollback_refuses '[]'; then pass "G17 (harness) the rollback row is not vacuous: against an emptied fixture the same case goes RED"; else fail "G17 the rollback case survived an empty fixture"; fi
if ! case_legacy_refuses '[]'; then pass "G17b (harness) the legacy row goes RED against an emptied fixture"; else fail "G17b the legacy case survived an empty fixture"; fi
if ! case_unreaching_refuses '[]'; then pass "G17c (harness) the reach row goes RED against an emptied fixture"; else fail "G17c the reach case survived an empty fixture"; fi

# ---------------------------------------------------------------------------------------------------
echo "== wipe_origin_run_ok (the wipe_finish origin-run read)"
VID=123456789
view() { # TITLE BRANCH EVENT JOBS-JSON [WORKFLOWNAME: default the real workflow name]
  jq -cn --arg t "$1" --arg b "$2" --arg e "$3" --argjson j "$4" --arg w "${5-$WIPE_LEGACY_TITLE}" \
    '{displayTitle: $t, headBranch: $b, event: $e, workflowName: $w, createdAt: "2026-10-02T12:00:00Z", jobs: $j}'
}
jobs_of() { # JOBNAME STEP|CONC ...
  local n="$1" a; shift
  jq -cn --arg n "$n" --argjson s "$(for a in "$@"; do jq -cn --arg a "${a%|*}" --arg c "${a##*|}" '{name:$a, conclusion:(if $c=="null" then null else $c end)}'; done | jq -cs '.')" \
    '{name:$n, conclusion:"failure", steps:$s}'
}
GOOD_JOBS="[$(jobs_of wipe 'Checkout|success' "$WIPE_ORIGIN_DETACH_STEP|success" 'Detach|failure')]"
GOOD="$(view "git-data wipe $VID" main workflow_dispatch "$GOOD_JOBS")"
case_origin_good() { local out rc=0; out="$(wipe_origin_run_ok "${1-$GOOD}" "$VID" 2>/dev/null)" || rc=$?; [[ "$out" == ok && "$rc" -eq 0 ]]; }
case_origin_gate_refuses() { local out rc=0; out="$(wipe_origin_run_ok "$1" "$VID" "${2-detach}" 2>/dev/null)" || rc=$?; [[ "$out" == wipe_origin_run_gate_not_success && "$rc" -eq 5 ]]; }
OR() { wipe_origin_run_ok "$1" "${2-$VID}" ${3:+"$3"}; }
case_origin_good && pass "O1 a wipe run on main by workflow_dispatch whose wipe_detach_gate succeeded is ok (a LATER failed step is not constrained)" || fail "O1 the good origin run was refused"
check_out "O1b the same run with a leading-zero id (id is compared as the typed string)" ok 0 -- OR "$(view 'git-data wipe 0123' main workflow_dispatch "$GOOD_JOBS")" 0123
check_out "O2 another volume id in the title" wipe_origin_run_title_mismatch 5 -- OR "$(view 'git-data wipe 999' main workflow_dispatch "$GOOD_JOBS")"
check_out "O2b a title that merely STARTS with the typed id's digits (12345678 vs 123456789)" wipe_origin_run_title_mismatch 5 -- OR "$(view "git-data wipe ${VID}0" main workflow_dispatch "$GOOD_JOBS")"
check_out "O2c the wipe_finish title is not an origin run" wipe_origin_run_title_mismatch 5 -- OR "$(view "git-data wipe_finish $VID" main workflow_dispatch "$GOOD_JOBS")"
check_out "O2d the wipe_check title is not an origin run" wipe_origin_run_title_mismatch 5 -- OR "$(view "git-data wipe_check $VID" main workflow_dispatch "$GOOD_JOBS")"
check_out "O2e the snapshot_clear title is not an origin run" wipe_origin_run_title_mismatch 5 -- OR "$(view "git-data snapshot_clear $VID" main workflow_dispatch "$GOOD_JOBS")"
check_out "O2e a trailing space on the title" wipe_origin_run_title_mismatch 5 -- OR "$(view "git-data wipe $VID " main workflow_dispatch "$GOOD_JOBS")"
check_out "O2f the right title under ANOTHER workflow (a run-name is free text)" wipe_origin_run_workflow_mismatch 5 -- OR "$(view "git-data wipe $VID" main workflow_dispatch "$GOOD_JOBS" 'some other workflow')"
check_out "O2g a workflow name that merely contains the real one" wipe_origin_run_workflow_mismatch 5 -- OR "$(view "git-data wipe $VID" main workflow_dispatch "$GOOD_JOBS" "${WIPE_LEGACY_TITLE} copy")"
check_out "O2h no workflowName in the answer (the field was not requested) is unreadable, never trusted" wipe_origin_run_unreadable 5 -- OR "$(view "git-data wipe $VID" main workflow_dispatch "$GOOD_JOBS" | jq -c 'del(.workflowName)')"
check_out "O3 a run on another branch" wipe_origin_run_not_main 5 -- OR "$(view "git-data wipe $VID" feature/x workflow_dispatch "$GOOD_JOBS")"
check_out "O3b a run not started by workflow_dispatch" wipe_origin_run_not_dispatch 5 -- OR "$(view "git-data wipe $VID" main schedule "$GOOD_JOBS")"
BAD_STEP_FAIL="[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|failure")]"
BAD_STEP_SKIP="[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|skipped")]"
BAD_STEP_NULL="[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|null")]"
BAD_NO_STEP="[$(jobs_of wipe 'Checkout|success')]"
BAD_WRONG_JOB="[$(jobs_of cutover "$WIPE_ORIGIN_DETACH_STEP|success")]"
BAD_TWO_JOBS="[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|success"),$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|success")]"
BAD_TWO_STEPS="[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|success" "$WIPE_ORIGIN_DETACH_STEP|success")]"
BAD_CASE="[$(jobs_of wipe "WIPE_DETACH_GATE|success")]"
for spec in "failure|$BAD_STEP_FAIL" "skipped|$BAD_STEP_SKIP" "null|$BAD_STEP_NULL" "absent|$BAD_NO_STEP" "wrong-job|$BAD_WRONG_JOB" "two-wipe-jobs|$BAD_TWO_JOBS" "two-gate-steps|$BAD_TWO_STEPS" "case-variant|$BAD_CASE"; do
  if case_origin_gate_refuses "$(view "git-data wipe $VID" main workflow_dispatch "${spec#*|}")"; then pass "O4 gate '${spec%%|*}' -> wipe_origin_run_gate_not_success"
  else fail "O4 gate '${spec%%|*}' was not refused as gate_not_success"; fi
done
check_out "O4b a run with no jobs array" wipe_origin_run_unreadable 5 -- OR "$(jq -cn '{displayTitle:"git-data wipe 123456789",headBranch:"main",event:"workflow_dispatch"}')"
DEL_JOBS="[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|success" "$WIPE_ORIGIN_DELETE_STEP|success")]"
check_out "O5 delete mode: the wipe_delete_gate succeeded -> ok (the absent-volume branch)" ok 0 -- OR "$(view "git-data wipe $VID" main workflow_dispatch "$DEL_JOBS")" "$VID" delete
case_origin_gate_refuses "$GOOD" delete && pass "O5b delete mode on a run that only passed the DETACH gate refuses" || fail "O5b delete mode accepted a run with no delete gate"
case_origin_gate_refuses "$(view "git-data wipe $VID" main workflow_dispatch "[$(jobs_of wipe "$WIPE_ORIGIN_DETACH_STEP|success" "$WIPE_ORIGIN_DELETE_STEP|failure")]")" delete && pass "O5c delete mode with a FAILED delete gate refuses" || fail "O5c a failed delete gate was accepted"
check_out "O6 not JSON" wipe_origin_run_unreadable 5 -- OR 'not json'
check_out "O6b a JSON array" wipe_origin_run_unreadable 5 -- OR '[]'
check_out "O6c an empty body" wipe_origin_run_unreadable 5 -- OR ''
check_out "O6d a null title" wipe_origin_run_unreadable 5 -- OR '{"displayTitle":null,"jobs":[]}'
check_out "O7 an empty volume id is a wiring fault" wipe_runs_bad_args 2 -- OR "$GOOD" ''
check_out "O7b a non-numeric volume id" wipe_runs_bad_args 2 -- OR "$GOOD" 'abc'
check_out "O7c a 13-digit volume id" wipe_runs_bad_args 2 -- OR "$GOOD" 1234567890123
check_out "O7d an unknown gate mode" wipe_runs_bad_args 2 -- OR "$GOOD" "$VID" apply
check_out "O8 (must-PASS) extra fields and another key order" ok 0 -- OR '{"z":1,"jobs":[{"steps":[{"conclusion":"success","name":"wipe_detach_gate","number":9}],"name":"wipe"}],"event":"workflow_dispatch","headBranch":"main","workflowName":"git-data cutover (#5274 / ADR-220 / ADR-239)","displayTitle":"git-data wipe 123456789"}'
if ! case_origin_good '[]'; then pass "O9 (harness) the origin-ok case goes RED against an emptied fixture"; else fail "O9 the origin-ok case survived an empty fixture"; fi

case_origin_workflow_refuses() { # right title, branch, event and gate under another workflow: must refuse
  local out rc=0; out="$(wipe_origin_run_ok "$(view "git-data wipe $VID" main workflow_dispatch "$GOOD_JOBS" 'some other workflow')" "$VID" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_origin_run_workflow_mismatch && "$rc" -eq 5 ]]
}
case_origin_prefix_refuses() { # the typed id is a PREFIX of the title's id: must refuse
  local out rc=0; out="$(wipe_origin_run_ok "$(view "git-data wipe ${VID}0" main workflow_dispatch "$GOOD_JOBS")" "$VID" 2>/dev/null)" || rc=$?
  [[ "$out" == wipe_origin_run_title_mismatch && "$rc" -eq 5 ]]
}

# ---------------------------------------------------------------------------------------------------
echo "== mutation battery (each row edits a COPY of the library; the NAMED case must go RED)"
MUTANTS_RUN=0
# mutant_lib NAME EXPECTED-DIFF-LINES SED-PROGRAM -- sets MLIB; fails the row when the edit did not land as expected
mutant_lib() {
  local name="$1" want="$2" expr="$3" got
  MLIB="$MUT/$name.sh"
  assert_fixture_dir "$MUT"
  cp "$LIB" "$MLIB" || { fail "M-$name: cannot copy the library"; return 1; }
  sed -E -i "$expr" "$MLIB" || { fail "M-$name: sed failed"; return 1; }
  got="$(diff "$LIB" "$MLIB" | grep -cE '^[<>]' || true)"
  if [[ "$got" != "$want" ]]; then fail "M-$name: mutation landed on $got diff line(s), expected $want [$expr]"; return 1; fi
  bash -n "$MLIB" || { fail "M-$name: the mutant does not parse"; return 1; }
  MUTANTS_RUN=$((MUTANTS_RUN + 1))
  pass "M-$name: mutation landed on exactly $want diff line(s) of a pristine copy"
}
# red_in_mutant NAME CASE-FUNCTION [ARGS...] — sources the mutant in a subshell and requires the case to FAIL there.
red_in_mutant() {
  local name="$1" fn="$2"; shift 2
  if ( source "$MLIB" && "$fn" "$@" ); then fail "M-$name: the named case stayed GREEN against the mutant"
  else pass "M-$name: the named case goes RED against the mutant"; fi
}
# shellcheck disable=SC2016
if mutant_lib recency-at-stamp 2 's/\(\.createdAt \| epoch\) >= \$stamp/(.createdAt | epoch) > $stamp/'; then red_in_mutant recency-at-stamp case_at_stamp_refuses; fi
# shellcheck disable=SC2016
if mutant_lib rollback-predicate-dropped 2 's/\. == "git-data rollback"/false/'; then red_in_mutant rollback-predicate-dropped case_rollback_refuses; fi
# shellcheck disable=SC2016
if mutant_lib legacy-refusal-dropped 2 's/tclass == "legacy"\) then/tclass == "never") then/'; then red_in_mutant legacy-refusal-dropped case_legacy_refuses; fi
# shellcheck disable=SC2016
if mutant_lib reach-check-dropped 2 's/length >= \$limit/length > 100000/'; then red_in_mutant reach-check-dropped case_unreaching_refuses; fi
# shellcheck disable=SC2016
if mutant_lib wipe-other-unignored 2 's/startswith\("git-data wipe"\)/startswith("git-data wipe-never")/'; then red_in_mutant wipe-other-unignored case_wipe_other_ignored; fi
# shellcheck disable=SC2016
if mutant_lib branch-filter-dropped 2 's/\.headBranch == "main" and \.event == "workflow_dispatch"/true/'; then red_in_mutant branch-filter-dropped case_nonmain_ignored; fi
# shellcheck disable=SC2016
if mutant_lib end-anchor-loosened 2 's/redeploy\)\\\\z/redeploy)$/'; then red_in_mutant end-anchor-loosened case_newline_title_ignored; fi
# shellcheck disable=SC2016
if mutant_lib gate-conclusion-ignored 2 's/\.conclusion == "success"/.conclusion != "never"/'; then red_in_mutant gate-conclusion-ignored case_origin_gate_refuses "$(view "git-data wipe $VID" main workflow_dispatch "$BAD_STEP_FAIL")"; fi
# shellcheck disable=SC2016
if mutant_lib origin-title-prefix 2 's/\.displayTitle != \("git-data wipe " \+ \$vid\)/(.displayTitle | startswith("git-data wipe " + $vid) | not)/'; then red_in_mutant origin-title-prefix case_origin_prefix_refuses; fi
# shellcheck disable=SC2016
if mutant_lib origin-workflow-unchecked 2 's/elif \.workflowName != \$wf then/elif false then/'; then red_in_mutant origin-workflow-unchecked case_origin_workflow_refuses; fi

# ---------------------------------------------------------------------------------------------------
echo "== epilogue"
MUTANT_MIN=10
if [[ "$MUTANTS_RUN" -lt "$MUTANT_MIN" ]]; then
  printf '[FATAL] mutant floor: only %d mutants executed, expected >= %d.\n' "$MUTANTS_RUN" "$MUTANT_MIN" >&2
  exit 1
fi
# Row-count floor, reported with printf + exit (never through the helpers it backstops).
printf '== %d passed, %d failed\n' "$PASS" "$FAIL"
# SELFTEST_PASSES is a literal ADJACENT to its use: scripts/guard-vacuity-floor.test.sh slices the floor block into
# a mutant with every counter zeroed, and a subtrahend bound far away is unbound there. The self-test above asserts
# PASS==1 at that point, which proves the literal.
SELFTEST_PASSES=1
REAL=$(( PASS - SELFTEST_PASSES ))
MIN_ASSERTIONS=117
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity assertion floor: only %d real assertion(s) ran (PASS=%d minus %d self-test), expected >= %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
