#!/usr/bin/env bash
# Suite for scripts/lib/git-data-rotate-stamp.sh (#10166, the git-data flip's d6_replace_stale gate).
#
# PROPERTY. Only a run whose git_data_host_replace job SUCCEEDED with the last-step marker
# ("Rotate completed (d6 marker)") succeeded can discharge D6; a plain replace, a plan-only rotate and a
# legacy (pre-marker) success cannot. A rotate attempt that did not complete and is NEWER than a stamped
# run blocks the flip instead of being skipped in favour of the older success. An unreadable, in-flight
# or unattributable run stops the scan; nothing is ever read as "stale" when it could not be read.
#
# INSTRUMENT. Every fixture is SYNTHESIZED with jq -n (no captured run). The scan rows run the library
# under a `gh` shell function that models exactly `gh run view <id> --json jobs`, reads $FX/<id>.json,
# exits 1 on a missing file, refuses any other argv (exit 64 plus a line in gh.refused) and cats its
# stdin, so a stdin-consuming regression shows up as a missing row. An epilogue row asserts the function
# never refused. The mutation battery edits a COPY of the library and expects a fixture-visible change.
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/scripts/lib/git-data-rotate-stamp.sh"
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

[[ -f "$LIB" ]] || { printf '[FATAL] library not found: scripts/lib/git-data-rotate-stamp.sh\n' >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { printf '[FATAL] jq is required\n' >&2; exit 2; }

TMPD="$(mktemp -d -t git-data-rotate-stamp-test.XXXXXXXX)" || { echo "FATAL: mktemp failed" >&2; exit 2; }
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

# shellcheck source=scripts/lib/git-data-rotate-stamp.sh
source "$LIB" || { printf '[FATAL] the library did not source\n' >&2; exit 2; }

JOB="$GDRS_JOB_NAME"; PRE="$GDRS_PRECONDITION_STEP"; APPLY="$GDRS_APPLY_STEP"; MARK="$GDRS_MARKER_STEP"

# ---------------------------------------------------------------------------------------------------
# Fixture builders. st NAME CONCLUSION -> one step object; steps 'name|conc'... -> an array;
# fx JOBNAME JOBCONC STEPS -> a `gh run view --json jobs` body. CONCLUSION "null" is a JSON null.
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
CONFIRM='Validate dispatch inputs (rotate confirm token)'

check_verdict() { # LABEL EXPECTED-TOKEN BODY
  local out rc=0 want_rc=1
  [[ "$2" == stamped ]] && want_rc=0
  out="$(git_data_rotate_run_verdict "$3")" || rc=$?
  if [[ "$out" == "$2" && "$rc" -eq "$want_rc" ]]; then pass "$1 -> $2 (rc $rc)"
  else fail "$1: got token '$out' rc=$rc, expected '$2' rc=$want_rc"; fi
}

# ---------------------------------------------------------------------------------------------------
# Classifier rows.
# ---------------------------------------------------------------------------------------------------
echo "== classifier"
# R1 — the #10166 repro: a plain replace. Precondition skipped, apply success, the confirm-token step
# success (it concludes success on EVERY target), marker skipped. It must NOT stamp.
check_verdict "R1 plain replace (repro)" skip "$(fx "$JOB" success "$(steps "$CONFIRM|success" "$PRE|skipped" "$APPLY|success" "$MARK|skipped")")"
# R2 — plan-only rotate: precondition success, apply skipped, job success, marker skipped.
check_verdict "R2 plan-only rotate" skip "$(fx "$JOB" success "$(steps "$CONFIRM|success" "$PRE|success" "$APPLY|skipped" "$MARK|skipped")")"
# R3 — legacy successful rotate (pre-marker): the marker step does not exist.
check_verdict "R3 missing marker (legacy rotate success)" skip "$(fx "$JOB" success "$(steps "$CONFIRM|success" "$PRE|success" "$APPLY|success")")"
# R4 — a real rotate stamps; row 4 is self-sufficient so the companions below stay stamped.
R4="$(fx "$JOB" success "$(steps "$CONFIRM|success" "$PRE|success" "$APPLY|success" "$MARK|success")")"
check_verdict "R4 real rotate" stamped "$R4"
check_verdict "R4b stamped with an unrelated extra step and shuffled order" stamped \
  "$(fx "$JOB" success "$(steps "$MARK|success" "Some other step|success" "$APPLY|success" "$PRE|success")")"
check_verdict "R4c stamped with the precondition and apply steps absent" stamped \
  "$(fx "$JOB" success "$(steps "$MARK|success")")"
# R5/R6 — a rotate attempt that did not complete after the apply began.
check_verdict "R5 failed rotate (apply failure, job failure)" rotate_failed \
  "$(fx "$JOB" failure "$(steps "$PRE|success" "$APPLY|failure" "$MARK|skipped")")"
check_verdict "R6 cancelled mid-apply" rotate_failed \
  "$(fx "$JOB" cancelled "$(steps "$PRE|success" "$APPLY|cancelled" "$MARK|skipped")")"
# R5b — the shape of run 38140050880 (a real failed rotate recorded BEFORE PR #10155): its apply step carries
# the old name, so it is ABSENT under the constants. Absence is name drift, not "nothing happened".
LEGACY_APPLY="Terraform apply (git-data-host -replace) — both-volumes-preserved assert"
check_verdict "R5b failed rotate recorded under the pre-#10155 apply step name" rotate_failed \
  "$(fx "$JOB" failure "$(steps "$PRE|success" "$LEGACY_APPLY|failure" "$MARK|skipped")")"
# R6b — cancelled or timed out while the apply step was running: the step is listed with no conclusion.
check_verdict "R6b apply step listed with no conclusion (cancelled mid-flight)" rotate_failed \
  "$(fx "$JOB" cancelled "$(steps "$PRE|success" "$APPLY|null" "$MARK|skipped")")"
# R7 — refused at the precondition: nothing was mutated, so it must NOT block (the false-block guard).
check_verdict "R7 refused at the precondition" skip \
  "$(fx "$JOB" failure "$(steps "$PRE|failure" "$APPLY|skipped" "$MARK|skipped")")"
# R7b — a FAILED PLAIN replace (precondition skipped, apply ran and failed) is not a rotate attempt.
check_verdict "R7b failed plain replace" skip \
  "$(fx "$JOB" failure "$(steps "$PRE|skipped" "$APPLY|failure" "$MARK|skipped")")"
# R8 — cancelled before the apply began.
check_verdict "R8 cancelled during the plan step" skip \
  "$(fx "$JOB" cancelled "$(steps "$PRE|success" "$APPLY|skipped" "$MARK|skipped")")"
# R9 — still running: a null or empty conclusion.
check_verdict "R9 in progress (null conclusion)" in_flight "$(fx "$JOB" null "$(steps "$PRE|success" "$APPLY|null")")"
check_verdict "R9b waiting (empty conclusion)" in_flight "$(fx "$JOB" "" "$(steps)")"
# R10 — the job was skipped (a different apply_target).
check_verdict "R10 job skipped" skip "$(fx "$JOB" skipped "$(steps "$MARK|success")")"
# R11 — a decoy job, a case variant and a missing job are not the job.
check_verdict "R11 decoy job name" skip "$(fx "${JOB}_decoy" success "$(steps "$MARK|success")")"
check_verdict "R11b case variant of the job name" skip "$(fx "$(tr '[:lower:]' '[:upper:]' <<<"$JOB")" success "$(steps "$MARK|success")")"
check_verdict "R11c no jobs at all" skip '{"jobs":[]}'
# R12 — near-miss marker names must not stamp.
check_verdict "R12 lowercase marker name" skip \
  "$(fx "$JOB" success "$(steps "$PRE|success" "$APPLY|success" "$(tr '[:upper:]' '[:lower:]' <<<"$MARK")|success")")"
check_verdict "R12b trailing-space marker name" skip \
  "$(fx "$JOB" success "$(steps "$PRE|success" "$APPLY|success" "$MARK |success")")"
# R13 — malformed bodies print the token `unreadable`.
for bad in '' 'null' '[]' '{"jobs":null}' '{"jobs":{}}' '{"jobs":[' 'not json'; do
  check_verdict "R13 malformed body '${bad}'" unreadable "$bad"
done
# R14 — a successful job with steps absent or null reads skip, not stamped.
check_verdict "R14 steps absent on a successful job" skip '{"jobs":[{"name":"'"$JOB"'","conclusion":"success"}]}'
check_verdict "R14b steps null on a successful job" skip '{"jobs":[{"name":"'"$JOB"'","conclusion":"success","steps":null}]}'
# R15 — a green marker inside a failed job (a failed post-job step) is closed, and surprising on purpose.
check_verdict "R15 marker success but job failure" rotate_failed \
  "$(fx "$JOB" failure "$(steps "$PRE|success" "$APPLY|success" "$MARK|success")")"

# ---------------------------------------------------------------------------------------------------
# Scan rows. gh models exactly `gh run view <id> --json jobs`; anything else is refused loudly.
# ---------------------------------------------------------------------------------------------------
echo "== scan"
gh() {
  if [[ "${1-}" == run && "${2-}" == view && "${4-}" == --json && "${5-}" == jobs && $# -eq 5 ]]; then
    printf '%s\n' "$3" >> "$GH_CALLS"
    cat >/dev/null
    [[ -f "$FX/$3.json" ]] || return 1
    cat "$FX/$3.json"
    return 0
  fi
  printf '%s\n' "$*" >> "$GH_REFUSED"
  return 64
}
put() { printf '%s\n' "$2" > "$FX/$1.json"; }
stamped_body="$R4"
plain_body="$(fx "$JOB" success "$(steps "$CONFIRM|success" "$PRE|skipped" "$APPLY|success" "$MARK|skipped")")"
failed_body="$(fx "$JOB" failure "$(steps "$PRE|success" "$APPLY|failure" "$MARK|skipped")")"
refused_body="$(fx "$JOB" failure "$(steps "$PRE|failure" "$APPLY|skipped" "$MARK|skipped")")"
inflight_body="$(fx "$JOB" null "$(steps "$PRE|success" "$APPLY|null")")"

run_scan() { # IDS-TEXT -> prints "<out>|rc"
  local out rc=0
  : > "$GH_CALLS"
  out="$(git_data_d6_scan <<<"$1")" || rc=$?
  printf '%s|%s' "$out" "$rc"
}
check_scan() { # LABEL EXPECTED-OUT EXPECTED-RC IDS
  local got; got="$(run_scan "$4")"
  if [[ "$got" == "$2|$3" ]]; then pass "$1 -> $2 (rc $3)"
  else fail "$1: got '$got', expected '$2|$3'"; fi
}

put 101 "$plain_body"; put 100 "$stamped_body"
check_scan "S1 newest plain replace, older stamped" "d6_stamped 100" 0 $'101\tcompleted\n100\tcompleted'

put 201 "$failed_body"; put 200 "$stamped_body"
check_scan "S2 newest failed rotate, older stamped" "d6_last_rotate_failed 201" 1 $'201\tcompleted\n200\tcompleted'

put 300 "$stamped_body"   # 301 has no fixture file: `gh` exits 1 for it
S3="$(run_scan $'301\tcompleted\n300\tcompleted')"
[[ "$S3" == "d6_run_unreadable 301|1" ]] && pass "S3 newest unreadable -> d6_run_unreadable 301 (rc 1)" || fail "S3: got '$S3'"
grep -qxF '300' "$GH_CALLS" && fail "S3: the older stamped run 300 was consulted after an unreadable newest run" || pass "S3 the older run is NOT consulted after an unreadable newest run"
put 302 ''   # an empty body is also unreadable
check_scan "S3b empty body from gh" "d6_run_unreadable 302" 1 $'302\tcompleted\n300\tcompleted'
put 303 'null'   # a body gh returned fine but the classifier cannot read: the `unreadable` token path
check_scan "S3c malformed body reaches the classifier and stops the scan" "d6_run_unreadable 303" 1 $'303\tcompleted\n300\tcompleted'

put 400 "$inflight_body"; put 399 "$stamped_body"
check_scan "S4 newest in flight" "d6_rotate_in_flight 400" 1 $'400\tin_progress\n399\tcompleted'

put 500 '{"jobs":[]}'; put 499 "$stamped_body"
check_scan "S5 queued run with no jobs" "d6_rotate_in_flight 500" 1 $'500\tqueued\n499\tcompleted'
check_scan "S5b COMPLETED run with no jobs (startup failure) is skipped" "d6_stamped 499" 0 $'500\tcompleted\n499\tcompleted'
put 510 "$(fx "${JOB}_other" null "$(steps)")"; put 509 "$stamped_body"
check_scan "S5c in-progress run that lists other jobs but not ours" "d6_rotate_in_flight 510" 1 $'510\tin_progress\n509\tcompleted'
put 520 "$plain_body"
check_scan "S5d in-progress run whose job is present and settled does not block" "d6_stamped 509" 0 $'520\tin_progress\n509\tcompleted'

put 600 "$plain_body"; put 599 "$plain_body"
check_scan "S6 only plain replaces" "d6_replace_stale" 1 $'600\tcompleted\n599\tcompleted'
check_scan "S6b empty input" "d6_replace_stale" 1 ''

put 700 "$refused_body"; put 699 "$stamped_body"
check_scan "S7 a rotate refused at the precondition does not block" "d6_stamped 699" 0 $'700\tcompleted\n699\tcompleted'

# Cardinality: the scan reads every id it is given, in order, and stops at the first stamp.
put 800 "$plain_body"; put 799 "$plain_body"; put 798 "$stamped_body"; put 797 "$stamped_body"
got="$(run_scan $'800\tcompleted\n799\tcompleted\n798\tcompleted\n797\tcompleted')"
[[ "$got" == "d6_stamped 798|0" ]] && pass "S8 the newest stamp wins and the scan stops there" || fail "S8: got '$got'"
[[ "$(tr '\n' ' ' < "$GH_CALLS")" == "800 799 798 " ]] && pass "S8 three runs consulted, in order, none after the stamp" || fail "S8: calls were '$(tr '\n' ' ' < "$GH_CALLS")'"

# A non-numeric id is not a run id: it stops the scan and never reaches gh.
got="$(run_scan $'abc\tcompleted\n300\tcompleted')"
[[ "$got" == "d6_run_unreadable|1" && ! -s "$GH_CALLS" ]] && pass "S9 a non-numeric id stops the scan before gh is called" || fail "S9: got '$got', gh calls: $(tr '\n' ' ' < "$GH_CALLS")"

[[ ! -s "$GH_REFUSED" ]] && pass "the gh function never refused an argv (the library only calls gh run view <id> --json jobs)" \
  || fail "the gh function refused: $(tr '\n' ';' < "$GH_REFUSED")"

# ---------------------------------------------------------------------------------------------------
# Mutation battery: each row edits a COPY of the library; the mutation must change the copy, the copy
# must still parse, the unmutated control must give the expected output, and the mutant must differ.
# ---------------------------------------------------------------------------------------------------
echo "== mutation battery"
# shellcheck disable=SC1090  # the probes source a COPY of the library chosen at run time
probe_s1() { # LIBPATH -> verdict of the plain-replace fixture
  ( source "$1" && git_data_rotate_run_verdict "$plain_body" ) 2>/dev/null
}
# shellcheck disable=SC1090
probe_scan() { # LIBPATH IDS -> scan output
  ( source "$1" && git_data_d6_scan <<<"$2" ) 2>/dev/null
}
# shellcheck disable=SC1090
probe_unrecognised() { # LIBPATH -> scan output with the classifier overridden to an unknown token
  ( source "$1" && git_data_rotate_run_verdict() { echo bogus; } && git_data_d6_scan <<<$'300\tcompleted' ) 2>/dev/null
}
mutate_and_expect_red() { # LABEL SED-EXPR PROBE EXPECTED-CONTROL [PROBE-ARG]
  local label="$1" expr="$2" probe="$3" want="$4" arg="${5-}" copy="$MUT/lib.$RANDOM.sh" c m
  cp "$LIB" "$copy" || { fail "$label: could not copy the library"; return; }
  sed -i "$expr" "$copy"
  if cmp -s "$LIB" "$copy"; then fail "$label: the mutation did NOT land (the copy is byte-identical)"; return; fi
  bash -n "$copy" 2>/dev/null || { fail "$label: the mutant does not parse (a syntax error is neither a pass nor a fail)"; return; }
  c="$("$probe" "$LIB" "$arg")"
  [[ "$c" == "$want" ]] || { fail "$label: the unmutated control gave '$c', expected '$want'"; return; }
  m="$("$probe" "$copy" "$arg")"
  [[ "$m" != "$c" ]] && pass "$label: mutant is visible (control '$c' vs mutant '$m')" || fail "$label: the mutant is INVISIBLE to the fixture (both gave '$c')"
}
# shellcheck disable=SC2016  # the sed expressions below are single-quoted on purpose: $ is literal
mutate_and_expect_red "M1 the marker must be success -> any conclusion" \
  's/sc(\$marker) == "success"/sc($marker) != ""/' probe_s1 skip
mutate_and_expect_red "M2 the rotate_failed arm -> continue" \
  's/^\( *\)rotate_failed) .*$/\1rotate_failed) continue ;;/' probe_scan "d6_last_rotate_failed 201" $'201\tcompleted\n200\tcompleted'
# shellcheck disable=SC2016
mutate_and_expect_red "M3 a gh failure -> continue" \
  's/then echo "d6_run_unreadable \$rid"; return 1; fi/then continue; fi/' probe_scan "d6_run_unreadable 301" $'301\tcompleted\n300\tcompleted'
# shellcheck disable=SC2016
mutate_and_expect_red "M4 the unrecognised-token arm -> continue" \
  's/^\( *\)unreadable|\*) echo "d6_run_unreadable \$rid"; return 1 ;;/\1unreadable|*) continue ;;/' probe_unrecognised "d6_run_unreadable 300"
# shellcheck disable=SC2016
mutate_and_expect_red "M5 the </dev/null on the gh call (what actually protects the id stream)" \
  's/--json jobs <\/dev\/null 2>\/dev\/null/--json jobs 2>\/dev\/null/' probe_scan "d6_stamped 798" $'800\tcompleted\n799\tcompleted\n798\tcompleted\n797\tcompleted'

# ---------------------------------------------------------------------------------------------------
# Verdicts, with the floor in the form guard-vacuity-floor.test.sh can mutate.
# ---------------------------------------------------------------------------------------------------
printf '\ngit-data-rotate-stamp.test.sh: %d passed, %d failed\n' "$PASS" "$FAIL"
# SELFTEST_PASSES is a literal ADJACENT to its use: the meta-guard slices the floor block into a mutant
# with every counter zeroed, and a subtrahend bound far away is unbound there. The self-test above
# asserts PASS==1 at that point, which proves the literal.
SELFTEST_PASSES=1
REAL=$(( PASS - SELFTEST_PASSES ))
MIN_ASSERTIONS=53
if [[ "$REAL" -lt "$MIN_ASSERTIONS" ]]; then
  printf '[FATAL] anti-vacuity assertion floor: only %d real assertion(s) ran (PASS=%d minus %d self-test), expected >= %d.\n' \
    "$REAL" "$PASS" "$SELFTEST_PASSES" "$MIN_ASSERTIONS" >&2
  exit 1
fi
[[ "$FAIL" -eq 0 ]] || exit 1
