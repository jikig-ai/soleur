#!/usr/bin/env bash
# Suite for scripts/lib/git-data-store-dirty-scan.sh (#10175, the git-data-host-rotate "store never written" gate).
#
# PROPERTY. A rotate proceeds only when no run of git-data-cutover.yml has ever executed the flag-write step
# (success, failure, cancelled or unknown all count: a failed write may have landed), in ANY attempt of any
# run. A scan that cannot read every run, finds a count mismatch, or meets a renamed step refuses. An
# unreadable, in-flight or unattributable run stops the scan; nothing is read as "clean" when it could not
# be read.
#
# INSTRUMENT. Every fixture is SYNTHESIZED with jq -n. The scan rows run the library under a `gh` shell
# function that models exactly the three `gh api` shapes the library issues, refuses any other argv (exit 64
# plus a line in gh.refused) and an epilogue row asserts it never refused. The mutation battery edits a COPY
# of the library and expects a fixture-visible change; each mutation is confirmed to have landed.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/git-data-store-dirty-scan.sh"
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

[[ -f "$LIB" ]] || { printf '[FATAL] library not found: scripts/lib/git-data-store-dirty-scan.sh\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

TMPD="$(mktemp -d -t git-data-store-dirty-scan-test.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
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
FX="$TMPD/fx"; MUT="$TMPD/mut"
for d in "$FX" "$MUT"; do assert_fixture_dir "$d"; mkdir -p "$d"; done
GH_CALLS="$TMPD/gh.calls"; GH_REFUSED="$TMPD/gh.refused"
: > "$GH_CALLS"; : > "$GH_REFUSED"

# shellcheck source=scripts/lib/git-data-store-dirty-scan.sh
source "${MUTANT:-$LIB}" || { printf '[FATAL] the library did not source\n' >&2; exit 2; }

JOB="$GDSD_JOB_NAME"; WRITE="$GDSD_WRITE_STEP"
export GITHUB_REPOSITORY="example-org/example-repo"
BASE="repos/${GITHUB_REPOSITORY}/actions/workflows/${GDSD_WORKFLOW_FILE}/runs"

# ---------------------------------------------------------------------------------------------------
# Fixture builders. steps 'name|conc'... -> an array; fx JOBNAME JOBCONC STEPS -> a jobs body.
# CONCLUSION "null" is a JSON null.
# ---------------------------------------------------------------------------------------------------
steps() {
  local a
  for a in "$@"; do
    jq -cn --arg n "${a%|*}" --arg c "${a##*|}" '{name:$n,conclusion:(if $c=="null" then null else $c end)}'
  done | jq -cs '.'
}
fx() {
  jq -cn --arg n "$1" --arg c "$2" --argjson s "$3" \
    '{jobs:[{name:$n,conclusion:(if $c=="null" then null else $c end),steps:$s}]}'
}
OTHER='Some other step'
clean_body() { fx "$JOB" success "$(steps "$OTHER|success" "$WRITE|skipped")"; }
dirty_body() { fx "$JOB" "${1:-success}" "$(steps "$OTHER|success" "$WRITE|${1:-success}")"; }

# gh shim: models the three `gh api` shapes the library issues; anything else is refused loudly.
gh() {
  printf '%s\n' "$*" >> "$GH_CALLS"
  # The two list calls run the library's REAL --jq program (arg 4 / arg 5) over a JSON page built from the fixtures,
  # so a reordered or truncated projection changes what the scan reads.
  if [[ "${1-}" == api && "${2-}" == "${BASE}?per_page=1" && "${3-}" == --jq && -n "${4-}" ]]; then
    [[ -f "$FX/total" ]] || return 1
    jq -n --argjson n "$(cat "$FX/total")" '{total_count: $n}' | jq -r "$4"; return $?
  fi
  if [[ "${1-}" == api && "${2-}" == --paginate && "${3-}" == "${BASE}?per_page=100" && "${4-}" == --jq && -n "${5-}" ]]; then
    [[ -f "$FX/list.tsv" ]] || return 1
    jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | {workflow_runs: map({id: (.[0] | tonumber? // .[0]), status: .[1], run_attempt: (.[2] | tonumber? // .[2]), created_at: .[3]})}' "$FX/list.tsv" | jq -r "$5"; return $?
  fi
  if [[ "${1-}" == api && "${2-}" =~ ^repos/${GITHUB_REPOSITORY}/actions/runs/([0-9]+)/attempts/([0-9]+)/jobs\?per_page=100$ && "$#" -eq 2 ]]; then
    [[ -f "$FX/${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.json" ]] || return 1
    cat "$FX/${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.json"; return 0
  fi
  printf 'REFUSED: %s\n' "$*" >> "$GH_REFUSED"
  return 64
}

# newfx: reset the fixture directory. addrun ID STATUS ATTEMPT [N:BODY ...]: add a listed run + attempt files.
newfx() { rm -rf "$FX"; assert_fixture_dir "$FX"; mkdir -p "$FX"; : > "$FX/list.tsv"; }
CREATED="${CREATED:-2026-10-01T00:00:00Z}"   # after the seam landed unless a row overrides it
addrun() {
  local id="$1" st="$2" at="$3" kv; shift 3
  printf '%s\t%s\t%s\t%s\n' "$id" "$st" "$at" "$CREATED" >> "$FX/list.tsv"
  for kv in "$@"; do printf '%s' "${kv#*:}" > "$FX/${id}.${kv%%:*}.json"; done
}
settotal() { printf '%s\n' "$1" > "$FX/total"; }
# scan_nopins: the scan with NO pinned-run proof (most rows model arbitrary histories; the literal --no-pins is the
# only way to say so); the pin rows below drive the real default (GDSD_PINNED_RUNS) by calling the scan with no
# argument, and an EMPTY argument must NOT disable the proof (row K10).
scan_nopins() { git_data_store_dirty_scan --no-pins; }
# check_scan: the production composition list | scan (the pipeline status is the scan's own).
check_scan() { # LABEL EXPECTED-REGEX EXPECTED-RC
  local out rc=0
  out="$(git_data_store_dirty_list | scan_nopins)" || rc=$?
  if [[ "$out" =~ ^$2$ && "$rc" -eq "$3" ]]; then pass "$1 -> $out (rc $rc)"
  else fail "$1: got '$out' rc=$rc, expected /$2/ rc=$3"; fi
}
check_verdict() { # LABEL EXPECTED-TOKEN BODY [preseam]
  local out rc=0 want_rc=1
  [[ "$2" == clean ]] && want_rc=0
  out="$(git_data_store_dirty_job_verdict "$3" "${4-}")" || rc=$?
  if [[ "$out" == "$2" && "$rc" -eq "$want_rc" ]]; then pass "$1 -> $2 (rc $rc)"
  else fail "$1: got token '$out' rc=$rc, expected '$2' rc=$want_rc"; fi
}

if [[ "${1-}" == "--mutant-run" ]]; then
  # Child mode: the mutant was sourced above (MUTANT); report whether any scan row now differs.
  killed=0
  newfx; addrun 3 completed 1 "1:$(clean_body)"; addrun 2 completed 1 "1:$(dirty_body success)"; settotal 2
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "store_dirty 2" ]] || killed=1
  newfx; : > "$FX/list.tsv"; settotal 3
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "scan_unreadable" ]] || killed=1
  newfx; addrun 5 completed 2 "1:$(dirty_body success)" "2:$(clean_body)"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "store_dirty 5" ]] || killed=1
  newfx; addrun 6 completed 1 "1:$(dirty_body cancelled)"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "store_dirty 6" ]] || killed=1
  newfx; addrun 7 completed 1 "1:$(fx "$JOB" success "$(steps "$OTHER|success")")"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "scan_unreadable 7" ]] || killed=1
  newfx; addrun 8 completed 1 "1:$(fx "$JOB" cancelled "$(steps)")"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "store_clean" ]] || killed=1
  newfx; addrun 9 in_progress 1 "1:$(clean_body)"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "cutover_in_flight 9" ]] || killed=1
  newfx; addrun 10 completed 1 "1:$(clean_body)"; addrun 11 queued 2 "1:$(dirty_body success)"; settotal 2
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "store_dirty 11" ]] || killed=1
  P1C="$(printf '%s\n' "$GDSD_PINNED_RUNS" | tr ' ' '\n' | sed -n 1p)"; P2C="$(printf '%s\n' "$GDSD_PINNED_RUNS" | tr ' ' '\n' | sed -n 2p)"
  newfx; addrun "$P1C" completed 1 "1:$(clean_body)"; settotal 1
  [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan)" == "scan_unreadable pinned_run_missing" ]] || killed=1
  newfx; addrun "9${P1C}" completed 1 "1:$(clean_body)"; addrun "$P2C" completed 1 "1:$(clean_body)"; settotal 2
  [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan)" == "scan_unreadable pinned_run_missing" ]] || killed=1
  newfx; CREATED=2020-01-01T00:00:00Z addrun "$P1C" completed 1 "1:$(clean_body)"; CREATED="$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)" addrun "$P2C" completed 1 "1:$(clean_body)"; settotal 2
  [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan 2>&1 >/dev/null)" == *"::warning::"* ]] || killed=1
  newfx; settotal 0
  [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan "" 2>/dev/null)" == "scan_unreadable pinned_run_missing" ]] || killed=1
  [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan "  " 2>/dev/null)" == "scan_unreadable pinned_run_missing" ]] || killed=1
  newfx; CREATED=2026-09-20T00:00:00Z addrun 15 completed 1 "1:$(fx "$JOB" failure "$(steps)")"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "store_clean" ]] || killed=1
  newfx; addrun 13 completed 1 "1:$(fx "${JOB}_x" success "$(steps "$WRITE|success")")"; settotal 1
  [[ "$(git_data_store_dirty_list | scan_nopins)" == "scan_unreadable 13" ]] || killed=1
  [[ "$killed" -eq 1 ]] && echo "MUTANT-KILLED" || echo "MUTANT-SURVIVED"
  exit 0
fi

# ---------------------------------------------------------------------------------------------------
echo "== classifier (one run attempt)"
check_verdict "C1 write step skipped (mode proof, resume arm B, nothing_to_rollback)" clean "$(clean_body)"
check_verdict "C2 write step success (a flip or rollback wrote)" dirty "$(dirty_body success)"
check_verdict "C3 write step failure (a write may have landed)" dirty "$(dirty_body failure)"
check_verdict "C4 write step cancelled" dirty "$(dirty_body cancelled)"
check_verdict "C5 write step listed with no conclusion" dirty "$(fx "$JOB" cancelled "$(steps "$OTHER|success" "$WRITE|null")")"
check_verdict "C6 write step ABSENT on a job that ran (rename drift)" unreadable "$(fx "$JOB" success "$(steps "$OTHER|success")")"
check_verdict "C6b write step ABSENT on a run that predates the seam (read-only-proof era): clean" clean "$(fx "$JOB" success "$(steps "$OTHER|success")")" preseam
check_verdict "C7 empty-steps job cancelled while queued (must not deadlock)" clean "$(fx "$JOB" cancelled "$(steps)")"
check_verdict "C7b empty-steps job skipped (approval rejected)" clean "$(fx "$JOB" skipped "$(steps)")"
check_verdict "C7c empty-steps job with no conclusion (queued or waiting)" unreadable "$(fx "$JOB" null "$(steps)")"
check_verdict "C7d a step-less job of a post-seam run with a final conclusion is unreadable (stripped steps)" unreadable "$(fx "$JOB" success "$(steps)")"
check_verdict "C7e a step-less job of a PRE-seam run is clean (could not write; old step lists are stripped)" clean "$(fx "$JOB" failure "$(steps)")" preseam
check_verdict "C8 no job named cutover (a decoy name) in a post-seam run: a rename, never clean" unreadable "$(fx "${JOB}_decoy" success "$(steps "$WRITE|success")")"
check_verdict "C8b case variant of the job name is not the job (post-seam: unreadable)" unreadable "$(fx "$(tr '[:lower:]' '[:upper:]' <<<"$JOB")" success "$(steps "$WRITE|success")")"
check_verdict "C8c a pre-seam run may list no cutover job at all: clean" clean "$(fx "${JOB}_decoy" success "$(steps "$WRITE|success")")" preseam
check_verdict "C8d an empty jobs array in a post-seam run is unreadable" unreadable '{"jobs":[]}'
check_verdict "C8e a caller-wrapper job name ('caller / cutover') is unreadable, not clean" unreadable "$(fx "caller / $JOB" success "$(steps "$WRITE|success")")"
check_verdict "C9 write step name case variant is not the step" unreadable "$(fx "$JOB" success "$(steps "$(tr '[:lower:]' '[:upper:]' <<<"$WRITE")|success")")"
check_verdict "C10 not JSON" unreadable "not json"
check_verdict "C11 empty body" unreadable ""
check_verdict "C12 jobs not an array" unreadable '{"jobs":{"x":1}}'
check_verdict "C13 a JSON array at top level" unreadable '[]'
check_verdict "C14 null steps on a job that ran" unreadable "$(jq -cn --arg n "$JOB" '{jobs:[{name:$n,conclusion:"success",steps:null}]}')"
check_verdict "C15 two jobs, the second is cutover and dirty (first decoy is clean)" dirty \
  "$(jq -cn --arg n "$JOB" --arg w "$WRITE" '{jobs:[{name:"notify",conclusion:"success",steps:[]},{name:$n,conclusion:"success",steps:[{name:$w,conclusion:"success"}]}]}')"

# (#10138) A wipe-family run (mode wipe / wipe_finish / wipe_check) lists the `cutover` job as SKIPPED with no steps
# and a separate `wipe` job that ran. It reads clean ONLY because the skipped `cutover` job stays listed (row 3 of the
# classifier); the `wipe` job's steps are never consulted, so no wipe step can read as the flag write. Synthesized.
wipe_family_body() { # CUTOVER-LISTED(yes|no) [WIPE-STEP-NAME]
  jq -cn --arg c "$JOB" --arg w "${2:-$WRITE}" --arg listed "$1" \
    '{jobs: ((if $listed == "yes" then [{name:$c, conclusion:"skipped", steps:[]}] else [] end)
             + [{name:"wipe", conclusion:"success", steps:[{name:"Checkout",conclusion:"success"},{name:$w,conclusion:"success"}]},
                {name:"notify-failure", conclusion:"skipped", steps:[]}])}'
}
check_verdict "C16 a wipe-family run (cutover job skipped and listed, wipe job ran) is clean" clean "$(wipe_family_body yes 'wipe_detach_gate')"
check_verdict "C16b the same run with the cutover job NOT listed is unreadable (it is the listed skipped job that keeps it clean)" unreadable "$(wipe_family_body no 'wipe_detach_gate')"
check_verdict "C16c a step of the wipe job that happens to carry the write step's name is never read as the flag write" clean "$(wipe_family_body yes)"

# ---------------------------------------------------------------------------------------------------
echo "== scan (list | scan, gh shim)"
newfx; addrun 101 completed 1 "1:$(clean_body)"; settotal 1
check_scan "S1 one clean run" 'store_clean' 0
newfx; addrun 102 completed 1 "1:$(wipe_family_body yes wipe_detach_gate)"; settotal 1
check_scan "S1b a listed wipe-family run reads clean through the whole list | scan composition" 'store_clean' 0
newfx; settotal 0
check_scan "S2 never-flipped history: zero runs and total_count 0" 'store_clean' 0
# --- proof the history is complete: the pinned runs must still be listed, completed (default pins = GDSD_PINNED_RUNS)
pinrun() { printf '%s\n' "$GDSD_PINNED_RUNS" | tr ' ' '\n' | sed -n "${1}p"; }
P1ID="$(pinrun 1)"; P2ID="$(pinrun 2)"
[[ "$P1ID" =~ ^[0-9]+$ && "$P2ID" =~ ^[0-9]+$ ]] || { printf '[FATAL] GDSD_PINNED_RUNS is not two run ids: %s\n' "$GDSD_PINNED_RUNS" >&2; exit 2; }
check_scan_pins() { # LABEL EXPECTED-REGEX EXPECTED-RC   (default pins)
  local out rc=0
  out="$(git_data_store_dirty_list | git_data_store_dirty_scan)" || rc=$?
  if [[ "$out" =~ ^$2$ && "$rc" -eq "$3" ]]; then pass "$1 -> $out (rc $rc)"
  else fail "$1: got '$out' rc=$rc, expected /$2/ rc=$3"; fi
}
newfx; addrun "$P2ID" completed 1 "1:$(clean_body)"; addrun "$P1ID" completed 1 "1:$(clean_body)"; settotal 2
check_scan_pins "K1 both pinned runs listed and completed, clean history" 'store_clean' 0
newfx; addrun "$P2ID" completed 1 "1:$(clean_body)"; settotal 1
check_scan_pins "K2 the older pinned run has EXPIRED (retention): the scan refuses instead of reading clean" 'scan_unreadable pinned_run_missing' 1
newfx; settotal 0
check_scan_pins "K3 an empty listing with total_count 0 is the expired-everything state: refuse" 'scan_unreadable pinned_run_missing' 1
newfx; addrun "$P2ID" completed 1 "1:$(clean_body)"; addrun "$P1ID" in_progress 1 "1:$(clean_body)"; settotal 2
check_scan_pins "K4 a pinned run that is not completed does not count as proof" 'scan_unreadable pinned_run_missing' 1
newfx; addrun 999 completed 1 "1:$(clean_body)"; addrun "$P2ID" completed 1 "1:$(clean_body)"; addrun "$P1ID" completed 1 "1:$(clean_body)"; settotal 3
check_scan_pins "K5 extra newer clean runs beside both pins stay clean" 'store_clean' 0
newfx; addrun "$P2ID" completed 1 "1:$(clean_body)"; addrun "$P1ID" completed 1 "1:$(dirty_body success)"; settotal 2
check_scan_pins "K6 a dirty pinned run is still dirty (the pin proves completeness, not cleanliness)" "store_dirty $P1ID" 1
# K7: the age warning keys on the OLDEST pin: one pin from 2020 and one from today still warns.
RECENT="$(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%SZ)"
newfx; CREATED=2020-01-01T00:00:00Z addrun "$P1ID" completed 1 "1:$(clean_body)"; CREATED="$RECENT" addrun "$P2ID" completed 1 "1:$(clean_body)"; settotal 2
out="$(git_data_store_dirty_list | git_data_store_dirty_scan 2>&1 >/dev/null)"
if [[ "$out" == *"::warning::"* ]]; then pass "K7 an old OLDEST pin (beside a recent one) triggers the age warning"; else fail "K7 no warning for a 2020 oldest pin: '$out'"; fi
newfx; CREATED="$RECENT" addrun "$P1ID" completed 1 "1:$(clean_body)"; CREATED="$RECENT" addrun "$P2ID" completed 1 "1:$(clean_body)"; settotal 2
out="$(git_data_store_dirty_list | git_data_store_dirty_scan 2>&1 >/dev/null)"
if [[ -z "$out" ]]; then pass "K7b two recent pins print no warning"; else fail "K7b a warning for recent pins: '$out'"; fi
newfx; CREATED=2020-01-01T00:00:00Z addrun "$P1ID" completed 1 "1:$(clean_body)"; CREATED=2020-01-01T00:00:00Z addrun "$P2ID" completed 1 "1:$(clean_body)"; settotal 2
out="$(git_data_store_dirty_list | git_data_store_dirty_scan 2>&1)"
if [[ "$out" == *store_clean* && "$(printf '%s' "$out" | sed -n '$p')" == store_clean ]]; then pass "K8 the verdict stays ONE last line on stdout beside the warning"; else fail "K8 verdict line disturbed: '$out'"; fi
newfx; addrun "$P2ID" completed 1 "1:$(clean_body)"; addrun "$P1ID" completed 1 "1:$(clean_body)"; settotal 2
if [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan "abc" 2>/dev/null)" == "scan_unreadable pinned_run_missing" ]]; then pass "K9 a malformed pin argument fails closed"; else fail "K9 a malformed pin was accepted"; fi
newfx; settotal 0
if [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan "" 2>/dev/null)" == "scan_unreadable pinned_run_missing" ]]; then pass "K10 an EMPTY pin argument does not disable the proof (empty history stays refused)"; else fail "K10 an empty argument turned the proof off"; fi
if [[ "$(git_data_store_dirty_list | git_data_store_dirty_scan "  " 2>/dev/null)" == "scan_unreadable pinned_run_missing" ]]; then pass "K10b a whitespace-only pin argument does not disable the proof either"; else fail "K10b a blank argument turned the proof off"; fi
newfx; addrun "9${P1ID}" completed 1 "1:$(clean_body)"; addrun "$P2ID" completed 1 "1:$(clean_body)"; settotal 2
check_scan_pins "K11 a run whose id merely ENDS with a pinned id is not the pin (no substring match)" 'scan_unreadable pinned_run_missing' 1
newfx; addrun "$P1ID" completed 1 "1:$(clean_body)"; settotal 1
check_scan_pins "K12 only the OLDER pin listed, the NEWER pin missing: every pin is checked, not just the first" 'scan_unreadable pinned_run_missing' 1
newfx; addrun 103 completed 1 "1:$(clean_body)"; addrun 102 completed 1 "1:$(dirty_body success)"; settotal 2
check_scan "S3 newest run clean, an OLDER run wrote (mutation 1: older dirty must not be masked)" 'store_dirty 102' 1
newfx; addrun 203 completed 1 "1:$(clean_body)"; addrun 202 completed 1 "1:$(clean_body)"; addrun 201 completed 1 "1:$(dirty_body failure)"; settotal 3
check_scan "S4 clean, clean, then a failure-conclusion write (mutation 3)" 'store_dirty 201' 1
newfx; addrun 301 completed 1 "1:$(dirty_body cancelled)"; settotal 1
check_scan "S5 write step cancelled" 'store_dirty 301' 1
newfx; addrun 401 completed 1 "1:$(fx "$JOB" success "$(steps "$OTHER|success")")"; settotal 1
check_scan "S6 renamed step on a job that ran (mutation 5)" 'scan_unreadable 401' 1
newfx; : > "$FX/list.tsv"; settotal 3
check_scan "S7 empty listing but total_count 3 (the guard's own dispatch checking nothing, mutation 2)" 'scan_unreadable' 1
newfx; addrun 501 completed 1 "1:$(clean_body)"; settotal 2
check_scan "S8 truncated pagination: collected 1, total 2" 'scan_unreadable' 1
newfx; addrun 502 completed 1 "1:$(clean_body)"; settotal 0
check_scan "S9 collected more than total_count" 'scan_unreadable' 1
newfx; addrun 503 completed 1 "1:$(clean_body)"
check_scan "S10 total_count call fails (no total file)" 'scan_unreadable' 1
newfx; settotal 1
check_scan "S11 list call fails (rows missing and non-empty total)" 'scan_unreadable' 1
rm -f "$FX/list.tsv"; settotal 0
check_scan "S11b list file absent, total 0: gh exits 1, so unreadable" 'scan_unreadable' 1
newfx; addrun 601 completed 1; settotal 1
check_scan "S12 attempt body missing (gh api exits 1)" 'scan_unreadable 601' 1
newfx; addrun 701 completed 1 "1:"; settotal 1
check_scan "S13 attempt body empty" 'scan_unreadable 701' 1
newfx; addrun 801 in_progress 1 "1:$(clean_body)"; addrun 800 completed 1 "1:$(dirty_body success)"; settotal 2
check_scan "S14 an in-flight run is named before any older verdict" 'cutover_in_flight 801' 1
newfx; addrun 901 queued 1; addrun 900 completed 1 "1:$(clean_body)"; settotal 2
check_scan "S15 a queued run executed nothing: skipped, store clean" 'store_clean' 0
newfx; addrun 911 waiting 1; addrun 910 completed 1 "1:$(dirty_body success)"; settotal 2
check_scan "S15b a waiting run does not hide an older dirty run" 'store_dirty 910' 1
newfx; addrun 921 queued 2 "1:$(dirty_body success)"; settotal 1
check_scan "S16 a queued RE-RUN: attempt 1 wrote, attempt 2 not started yet" 'store_dirty 921' 1
newfx; addrun 931 weird 1 "1:$(clean_body)"; settotal 1
check_scan "S17 an unknown run status fails closed" 'scan_unreadable 931' 1
newfx; addrun 941 completed 1 "1:$(clean_body)"; settotal 1
sed -i 's/^941\t/not-a-number\t/' "$FX/list.tsv"
check_scan "S18 a non-numeric run id is never handed to gh" 'scan_unreadable' 1
newfx; addrun 951 completed 0 "1:$(clean_body)"; settotal 1
check_scan "S19 run_attempt 0 fails closed" 'scan_unreadable' 1

# Runs that predate the write step (the 2026-09-14..09-29 read-only-proof runs really exist in prd).
newfx; CREATED=2026-09-20T10:00:00Z addrun 1401 completed 1 "1:$(fx "$JOB" success "$(steps "Proof|success")")"; settotal 1
check_scan "Z1 a pre-seam run has no write step and could not write: clean" 'store_clean' 0
newfx; CREATED=2026-09-30T02:18:17Z addrun 1402 completed 1 "1:$(fx "$JOB" success "$(steps "Proof|success")")"; settotal 1
check_scan "Z2 a run created exactly at the seam instant is NOT pre-seam: absent step is unreadable" 'scan_unreadable 1402' 1
newfx; CREATED=garbage addrun 1403 completed 1 "1:$(fx "$JOB" success "$(steps "Proof|success")")"; settotal 1
check_scan "Z3 an unparseable created_at is never read as pre-seam" 'scan_unreadable 1403' 1
newfx; CREATED=2026-09-20T10:00:00Z addrun 1404 completed 1 "1:$(dirty_body success)"; settotal 1
check_scan "Z4 pre-seam with a PRESENT write step that ran is still dirty (the date only excuses absence)" 'store_dirty 1404' 1

# Re-run fixtures (mutation 8): every attempt is read, not only the latest.
newfx; addrun 1001 completed 2 "1:$(dirty_body success)" "2:$(clean_body)"; settotal 1
check_scan "R1 attempt 1 wrote, attempt 2 (latest) skipped the write: dirty" 'store_dirty 1001' 1
newfx; addrun 1002 completed 2 "1:$(clean_body)" "2:$(dirty_body success)"; settotal 1
check_scan "R2 attempt 2 wrote" 'store_dirty 1002' 1
newfx; addrun 1003 completed 3 "1:$(clean_body)" "2:$(clean_body)"; settotal 1
check_scan "R3 attempt 3 body missing: unreadable, never skipped" 'scan_unreadable 1003' 1
newfx; addrun 1004 completed 2 "1:$(fx "$JOB" cancelled "$(steps)")" "2:$(clean_body)"; settotal 1
check_scan "R4 attempt 1 empty-steps cancelled job (mutation 9): clean, no permanent deadlock" 'store_clean' 0

# Must-PASS fixtures that are not the canonical clean shape.
newfx
addrun 1103 completed 1 "1:$(fx "$JOB" success "$(steps "Confirm|success" "Freeze|skipped" "$WRITE|skipped" "Redeploy|success")")"
addrun 1102 completed 1 "1:$(fx "$JOB" success "$(steps "Proof|success" "$WRITE|skipped")" | jq -c '.jobs += [{name:"notify",conclusion:"skipped",steps:[]}]')"
addrun 1101 completed 1 "1:$(fx "$JOB" skipped "$(steps)")"
settotal 3
check_scan "P1 resume-arm-B run (write skipped), a proof run with no write step in an extra-job body, a skipped run" 'store_clean' 0

# Different JSON key order and extra fields must not matter.
newfx; addrun 1201 completed 1 "1:$(jq -cn --arg n "$JOB" --arg w "$WRITE" '{jobs:[{steps:[{conclusion:"skipped",number:3,name:$w}],id:7,conclusion:"success",name:$n}],total_count:1}')"; settotal 1
check_scan "P2 reordered keys and extra fields" 'store_clean' 0

# ---------------------------------------------------------------------------------------------------
echo "== harness"
# H1: the shim never refused an argv the library issued.
if [[ ! -s "$GH_REFUSED" ]]; then pass "H1 gh shim refused nothing the library issued"
else fail "H1 gh shim refused: $(head -3 "$GH_REFUSED" | tr '\n' ';')"; fi
# H2: the shim DOES refuse an unexpected shape (it is not a catch-all).
if ! gh run list --workflow x >/dev/null 2>&1 && [[ -s "$GH_REFUSED" ]]; then pass "H2 gh shim refuses an unexpected argv"; else fail "H2 gh shim is a catch-all"; fi
: > "$GH_REFUSED"
# H3: the library never calls a gh subcommand other than `api`.
non_api_calls="$(grep -vE '^api ' "$GH_CALLS" | grep -vE '^run list --workflow x$' || true)"
if [[ -z "$non_api_calls" ]]; then pass "H3 only gh api was called"; else fail "H3 a non-api gh call was made"; fi
# H4: the scan reads its stdin to the end and does not leave the list half-consumed for a caller.
newfx; addrun 1301 completed 1 "1:$(clean_body)"; addrun 1300 completed 1 "1:$(clean_body)"; settotal 2
out="$(git_data_store_dirty_list | scan_nopins)"
if [[ "$out" == store_clean ]]; then pass "H4 two clean runs scanned"; else fail "H4 got '$out'"; fi
# H5: GITHUB_REPOSITORY is validated (an injected value never reaches gh).
if ( GITHUB_REPOSITORY='a/b;rm -rf x' git_data_store_dirty_list >/dev/null 2>&1 ); then fail "H5 a malformed GITHUB_REPOSITORY was accepted"; else pass "H5 a malformed GITHUB_REPOSITORY is refused"; fi
if ( unset GITHUB_REPOSITORY; git_data_store_dirty_list >/dev/null 2>&1 ); then fail "H6 an unset GITHUB_REPOSITORY was accepted"; else pass "H6 an unset GITHUB_REPOSITORY is refused"; fi

# ---------------------------------------------------------------------------------------------------
echo "== mutation battery (each edits a COPY of the library; each must change a fixture verdict)"
PRISTINE="$MUT/pristine.sh"; cp "$LIB" "$PRISTINE"
mutate() { # LABEL SED-EXPR EXPECTED-FAILING-FIXTURE-LABEL-PREFIX
  local label="$1" expr="$2" mfile="$MUT/m.sh" got
  cp "$PRISTINE" "$mfile"
  sed -i -E "$expr" "$mfile"
  if cmp -s "$PRISTINE" "$mfile"; then fail "M[$label] the mutation did NOT land"; return; fi
  # Re-run the full fixture set against the mutant in a subshell; a mutant is killed when ANY verdict differs.
  got="$( MUTANT="$mfile" bash "$0" --mutant-run 2>/dev/null | tail -1 )"
  if [[ "$got" == "MUTANT-KILLED" ]]; then pass "M[$label] killed"; else fail "M[$label] SURVIVED ($got)"; fi
}

# Control: the UNMUTATED copy must be reported SURVIVED by the child (a red baseline voids every row).
CTRL="$(MUTANT="$PRISTINE" bash "$0" --mutant-run 2>/dev/null | tail -1)"
if [[ "$CTRL" == "MUTANT-SURVIVED" ]]; then pass "M0 control: the unmutated library passes every battery fixture"; else fail "M0 control is RED ($CTRL): the battery is void"; fi

mutate "dirty verdict returns clean"        's/dirty\) echo "store_dirty \$rid"; return 1 ;;/dirty) : ;;/'
mutate "only the latest attempt is read"    's/for \(\(n = 1; n <= last; n\+\+\)\); do/for ((n = last; n <= last; n++)); do/'
mutate "count cross-check dropped"          's/\[\[ "\$\{#lines\[@\]\}" -ne "\$expect" \]\]/false/'
mutate "absent step reads as clean"         's/\(if \$preseam then "clean" else "unreadable" end\)/(if $preseam then "clean" else "clean" end)/'
mutate "seam cutoff dropped (every run pre-seam)" 's/ && "\$created" < "\$GDSD_SEAM_ADDED_AT"//'
mutate "cancelled write step reads as clean" 's/elif \(\$w.conclusion \/\/ ""\) == "skipped" then "clean"/elif ($w.conclusion \/\/ "") != "success" then "clean"/'
mutate "in_progress run skipped"            's/in_progress\) echo "cutover_in_flight \$rid"; return 1 ;;/in_progress) continue ;;/'
mutate "queued re-run attempts skipped"     's/last=\$\(\(attempt - 1\)\)/last=0/'
mutate "pinned-run proof dropped"            's/\[\[ -n "\$pre" \]\] \|\| \{ echo "scan_unreadable pinned_run_missing"; return 1; \}/true/'
mutate "a missing cutover job reads clean"   's/if \$j == null then \(if \$preseam then "clean" else "unreadable" end\)/if $j == null then "clean"/'
mutate "pin matching by substring"          's/\[\[ "\$rid" == "\$pin" && "\$status" == completed \]\]/[[ "$rid" == *"$pin" \&\& "$status" == completed ]]/'
mutate "only the first pin is checked"       's/for pin in \$pins; do/for pin in ${pins%% *}; do/'
mutate "the age warning keys on the newest pin" 's/"\$pre" < "\$oldest"/"$oldest" < "$pre"/'
# Two layers keep an empty or blank argument from disabling the proof (`:-` and the whitespace normalisation), so a
# single removal is EQUIVALENT for an empty string; the whitespace-only fixture kills the normalisation removal and the
# combined mutant kills the pair.
mutate "the blank-argument normalisation is removed" 's/^  \[\[ -n "\$\{pins\/\/\[\[:space:\]\]\/\}" \]\] \|\| pins="\$GDSD_PINNED_RUNS"$/  :/'
mutate "both empty-argument guards are removed" 's/local pins="\$\{1:-\$GDSD_PINNED_RUNS\}"/local pins="${1-$GDSD_PINNED_RUNS}"/;s/^  \[\[ -n "\$\{pins\/\/\[\[:space:\]\]\/\}" \]\] \|\| pins="\$GDSD_PINNED_RUNS"$/  :/'
mutate "the list projection drops run_attempt" 's/\[\.id, \.status, \.run_attempt, \.created_at\]/[.id, .status, .created_at, .created_at]/'
mutate "pre-seam step-less job stays unreadable" 's/\(if \$preseam or \(/(if false or (/'
mutate "empty-steps cancelled job unreadable" 's/then "clean" else "unreadable" end\)/then "unreadable" else "unreadable" end)/'

# ---------------------------------------------------------------------------------------------------
echo "== epilogue"
if [[ -s "$GH_REFUSED" ]]; then fail "E1 gh shim refused an argv during the run: $(head -3 "$GH_REFUSED" | tr '\n' ';')"; else pass "E1 gh shim never refused"; fi
# Row-count floor, reported with printf + exit (never through the helpers it backstops).
printf '== %d passed, %d failed\n' "$PASS" "$FAIL"
# SELFTEST_PASSES is a literal ADJACENT to its use: scripts/guard-vacuity-floor.test.sh slices the floor block into
# a mutant with every counter zeroed, and a subtrahend bound far away is unbound there. The self-test above asserts
# PASS==1 at that point, which proves the literal.
SELFTEST_PASSES=1
REAL=$(( PASS - SELFTEST_PASSES ))
MIN_ASSERTIONS=99
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity assertion floor: only %d real assertion(s) ran (PASS=%d minus %d self-test), expected >= %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
exit 0
