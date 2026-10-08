#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 2 for #9727 (S1 of the hosted-runner demand plan, ADR-276): the census
# self-check in scripts/ci-demand-census.sh.
#
# PROPERTY. TOTAL_JOB_MINUTES is printed only when every completed run in the
# listing was fetched, every run's jobs were fetched in full, and at least one
# job was examined. Any shortfall exits 3 with no total line.
#
# WHAT THIS PROVES, AND HOW.
#   Row 5  goldens: the committed fixture carries one job per classification
#          clause (runner-less with runner_id 0 and null, two untimed, a
#          synthetic skipped job that HAS a runner and both timestamps), each
#          with a different power-of-two duration, so dropping any one clause
#          moves the total by a unique amount. Every figure below is computed
#          here from integer seconds; nothing is copied from the script.
#   Rows 1-4  mutation matrix. Each mutant is a COPY of the fixture under
#          mktemp, a landing check proves the mutation changed bytes, and a
#          mutant counts as caught ONLY on rc == 3 exactly plus a reason
#          keyword on stderr and no TOTAL_JOB_MINUTES line (an rc 2 crash or
#          an rc 127 missing script never counts).
#   Row 6  classification, stem kinds on mixed sets, superseded runs, name
#          sanitising, rounding ties and re-runs, each from a jq-edited tmp
#          copy with hand-computed expectations (the committed durations stay).
#   Row 7  --workflow.  Row 8  the windows.tsv manifest and created_at checks.
#   H1     the same row function is run against a stub that prints the golden
#          total; rows 1-8 must go RED against it.
#   H2     the assertion floor at the bottom, written in the guard-vacuity-floor
#          shape (literal bound, direct printf + exit 1).
#   Live layer  a `gh` shim serving the committed fixture per exact endpoint
#          (whitelisted flags, every call logged) drives live mode: the fetched
#          directory round-trips to the same golden, a failure on run k exits 2
#          naming k after two retries, C1 fires before any jobs call, and every
#          validation refusal exits 2 without a single gh call. A `jq` shim that
#          fails only one filter proves every jq failure is fail-closed.
#
# This suite writes only under mktemp -d rooted at ${TMPDIR:-/var/tmp}; it never
# writes into the repository (lesson: fixtures that clobber committed files).
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENSUS="$REPO_ROOT/scripts/ci-demand-census.sh"
FIXTURE="$REPO_ROOT/scripts/fixtures/ci-demand-census/basic"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this array, which can only be
# silenced by deleting evidence, never by moving a counter.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

# Verdicts go through verdict(): SINK=main feeds pass()/fail(); SINK=stub feeds the
# per-row counters H1 reads, so running the row function against a stub never moves
# the real suite counters.
SINK=main
declare -A STUB_FAILS=()
declare -A STUB_PASSES=()
verdict() { # <row> <label> <rc: 0 = ok>
  if [ "$SINK" = main ]; then
    if [ "$3" -eq 0 ]; then pass; else fail "row $1: $2"; fi
  elif [ "$3" -eq 0 ]; then
    STUB_PASSES[$1]=$(( ${STUB_PASSES[$1]:-0} + 1 ))
  else
    STUB_FAILS[$1]=$(( ${STUB_FAILS[$1]:-0} + 1 ))
  fi
}
# chk / chk_not run a command and hand verdict() its REAL exit status (no echo-0-or-1 idiom, so an
# error in the test expression is a failure, never silently a pass).
chk() { # <row> <label> <command...>: passes when the command succeeds
  local row="$1" label="$2"
  shift 2
  if [ $# -eq 0 ]; then fail "chk without a command: row $row: $label"; return 0; fi
  "$@"; verdict "$row" "$label" "$?"
}
chk_not() { # <row> <label> <command...>: passes when the command FAILS
  local row="$1" label="$2" rc=0
  shift 2
  if "$@"; then rc=1; fi
  verdict "$row" "$label" "$rc"
}

# Instrument self-test: BEFORE any real row, drive both helpers, the dispatcher and chk/chk_not once
# (each with an input that MUST fail as well as one that must pass) and require each counter to move.
# Reported by a direct printf + exit 1, never through the helpers it checks (a neutered
# pass()/fail() must not be able to silence it).
_self=$( ( passes=0; fails=0; FAILURES=(); SINK=main
  pass; fail "self-test" 2>/dev/null; verdict selftest ok 0; verdict selftest bad 1 2>/dev/null
  chk selftest ok true; chk selftest bad false 2>/dev/null; chk selftest nocmd 2>/dev/null
  chk_not selftest ok false; chk_not selftest bad true 2>/dev/null; chk_not selftest nocmd 2>/dev/null
  chk selftest rc7 bash -c 'exit 7' 2>/dev/null
  printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}" ) )
if [ "$_self" != "4 7 7" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail()/verdict()/chk()/chk_not() self-test read "%s", expected "4 7 7"\n' "$_self" >&2
  exit 1
fi

for _tool in jq awk diff cmp cksum timeout; do
  command -v "$_tool" >/dev/null 2>&1 || { printf 'FAIL: required tool missing: %s\n' "$_tool" >&2; exit 2; }
done
REAL_SLEEP=$(command -v sleep)
REAL_JQ=$(command -v jq)

T=$(mktemp -d "${TMPDIR}/ci-demand-census-test.XXXXXXXX") || {
  printf 'FAIL: mktemp -d failed\n' >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/mut" "$T/bin" "$T/sbin" "$T/jqbin" "$T/live"

OUT="$T/out.txt"
ERR="$T/err.txt"
RC=0

# run_census <script> <args...>: fixture-mode style invocation (no env tricks)
run_census() {
  local s="$1"; shift
  bash "$s" "$@" >"$OUT" 2>"$ERR"; RC=$?
}

# predicates for chk (none of them owns a verdict)
rc_is() { [ "$RC" -eq "$1" ]; }                    # rc_is <n>: the last run_census/run_live exit status
has()   { grep -qF -- "$1" "$2"; }                 # has <fixed text> <file>
hasi()  { grep -qiF -- "$1" "$2"; }                # case-insensitive
hasx()  { grep -Fxq -- "$1" "$2"; }                # a whole line
same()  { cmp -s "$1" "$2"; }

# ── independent arithmetic: integer seconds per fixture job, written out by hand ──
# (see scripts/fixtures/ci-demand-census/basic; the clause jobs are NOT summed here)
S_CI_PR=$((600 + 300 + 1200 + 150 + 90))
S_CI_MG=$((480 + 840))
S_CI_PUSH=$((360 + 720))
S_SS_PR=$(( (10 + 20 + 24 + 18 + 100) + (12 + 110) + 90 ))
S_DYN=$((300 + 200 + 330))
S_NIGHT=$((150 + 50))
S_TOTAL=$((S_CI_PR + S_CI_MG + S_CI_PUSH + S_SS_PR + S_DYN + S_NIGHT))
# minutes (or minutes per run) from integer seconds, rounded half up by INTEGER arithmetic only:
#   fmt <secs> 1          -> floor((20*secs + 60) / 120) tenths
#   fmt <secs> 2 <runs>   -> floor((200*secs + 60*runs) / (120*runs)) hundredths
fmt() {
  local s="$1" d="$2" n="${3:-1}" h
  if [ "$d" -eq 1 ]; then
    h=$(( (s * 20 + 60) / 120 )); printf '%d.%d' $((h / 10)) $((h % 10))
  else
    h=$(( (s * 200 + 60 * n) / (120 * n) )); printf '%d.%02d' $((h / 100)) $((h % 100))
  fi
}

TAB=$(printf '\t')
ESC=$(printf '\033')
KEYS_RE='REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT|WORKFLOW_FILTER|TOTAL_JOB_MINUTES|TOTAL_JOB_SECONDS|RUNS_COMPLETED|RUNS_NOT_COMPLETED|RUNS_RERUN|JOBS_COUNTED|JOBS_SKIPPED|JOBS_RUNNERLESS|JOBS_UNTIMED'
stray_lines() { grep -cvE "^($KEYS_RE)=|^(BY_WORKFLOW|STEM)${TAB}" "$1" || true; }
tables_equal() { # <wanted tables file>: the BY_WORKFLOW/STEM lines of $OUT equal it
  grep -E "^(BY_WORKFLOW|STEM)${TAB}" "$OUT" >"$T/got-tables.txt" || true
  cmp -s "$1" "$T/got-tables.txt"
}
stem_line() { # wf ev stem ran skipped runnerless jobs minutes per_run
  printf 'STEM\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$@"
}
bw_line() { printf 'BY_WORKFLOW\t%s\t%s\t%s\t%s\t%s' "$@"; }   # wf ev runs jobs minutes

want_by_workflow() {
  local rows=(
    "ci.yml|merge_group|1|2|$S_CI_MG"
    "ci.yml|pull_request|1|5|$S_CI_PR"
    "ci.yml|push|1|2|$S_CI_PUSH"
    "dynamic/github-code-scanning/codeql|dynamic|2|3|$S_DYN"
    "lint.yml|push|1|0|0"
    "nightly.yml|schedule|1|2|$S_NIGHT"
    "secret-scan.yml|pull_request|3|8|$S_SS_PR"
  ) r wf ev runs jobs secs
  for r in "${rows[@]}"; do
    IFS='|' read -r wf ev runs jobs secs <<<"$r"
    printf 'BY_WORKFLOW\t%s\t%s\t%s\t%s\t%s\n' "$wf" "$ev" "$runs" "$jobs" "$(fmt "$secs" 1)"
  done
}
want_stem() {
  # workflow|event|stem|runs_ran|runs_skipped|runs_runnerless|jobs|seconds|completed_runs_of_workflow_event
  # Run 102 (ci.yml merge_group) holds cancelled jobs: it is a superseded run, so its all-skipped stems
  # (lint, synthetic-skipped-with-runner) are runner-less, not gate-skips.
  local rows=(
    "ci.yml|merge_group|e2e|0|0|1|0|0|1"
    "ci.yml|merge_group|lint|0|0|1|0|0|1"
    "ci.yml|merge_group|synthetic-skipped-with-runner|0|0|1|0|0|1"
    "ci.yml|merge_group|test-scripts|1|0|0|1|480|1"
    "ci.yml|merge_group|test-scripts-heavy|0|0|1|0|0|1"
    "ci.yml|merge_group|test-webplat|1|0|0|1|840|1"
    "ci.yml|merge_group|untimed-a|0|0|1|0|0|1"
    "ci.yml|merge_group|untimed-b|0|0|1|0|0|1"
    "ci.yml|pull_request|e2e|1|0|0|1|150|1"
    "ci.yml|pull_request|test-scripts|1|0|0|2|$((600 + 300))|1"
    "ci.yml|pull_request|test-webplat|1|0|0|1|1200|1"
    "ci.yml|pull_request|unit|1|0|0|1|90|1"
    "ci.yml|push|test-scripts|1|0|0|1|360|1"
    "ci.yml|push|test-webplat|1|0|0|1|720|1"
    "dynamic/github-code-scanning/codeql|dynamic|Analyze|2|0|0|3|$S_DYN|2"
    "nightly.yml|schedule|report|1|0|0|1|50|1"
    "nightly.yml|schedule|test-scripts|1|0|0|1|150|1"
    "secret-scan.yml|pull_request|gitleaks scan|3|0|0|3|$((100 + 110 + 90))|3"
    "secret-scan.yml|pull_request|smoke|1|1|1|3|$((20 + 24 + 18))|3"
    "secret-scan.yml|pull_request|smoke-relevance|2|0|0|2|$((10 + 12))|3"
  ) r wf ev stem ran sk rl jobs secs runs
  for r in "${rows[@]}"; do
    IFS='|' read -r wf ev stem ran sk rl jobs secs runs <<<"$r"
    printf 'STEM\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$wf" "$ev" "$stem" "$ran" "$sk" "$rl" "$jobs" \
      "$(fmt "$secs" 1)" "$(fmt "$secs" 2 "$runs")"
  done
}
WANT_TOTAL="TOTAL_JOB_MINUTES=$(fmt "$S_TOTAL" 1)"
WANT_SECS="TOTAL_JOB_SECONDS=$S_TOTAL"
{ want_by_workflow; want_stem; } >"$T/want-tables.txt"
grep -E "^(BY_WORKFLOW|STEM)${TAB}secret-scan.yml${TAB}" "$T/want-tables.txt" >"$T/want-tables-ss.txt"
grep -E "^(BY_WORKFLOW|STEM)${TAB}ci.yml${TAB}" "$T/want-tables.txt" >"$T/want-tables-ci.txt"

# the oracle itself, against figures worked out by hand (decimal ties round half up)
chk 0 "oracle: 501 s is 8.35 min, which rounds to 8.4" [ "$(fmt 501 1)" = "8.4" ]
chk 0 "oracle: 507 s over 2 runs is 4.225 min, which rounds to 4.23" [ "$(fmt 507 2 2)" = "4.23" ]
chk 0 "oracle: 5787 s is 96.45 min, which rounds to 96.5" [ "$(fmt 5787 1)" = "96.5" ]
chk 0 "oracle: 6154 s is 102.57 min, which rounds to 102.6" [ "$(fmt 6154 1)" = "102.6" ]

# jobs in the fixture's completed runs, counted independently of the script under test
FIX_JOBS_TOTAL=0
for _id in 101 102 103 104 105 106 107 108 110 111; do
  _n=$(jq -s '[.[].jobs[]] | length' "$FIXTURE/jobs-$_id.json" 2>/dev/null || echo 0)
  FIX_JOBS_TOTAL=$((FIX_JOBS_TOTAL + _n))
done

# ── mutant helpers: copies under mktemp, landing checks ──
MUT_N=0
# new_mutant sets $d (the caller's variable, by dynamic scope) to a fresh copy of the fixture.
# It must NOT run in a command substitution: the counter would not survive the subshell.
new_mutant() {
  MUT_N=$((MUT_N + 1))
  d="$T/mut/m$MUT_N"
  rm -rf "$d"; cp -R "$FIXTURE" "$d"
}
landed() { ! diff -rq "$FIXTURE" "$1" >/dev/null 2>&1; }   # 0 when the copy differs from the original
# jq_edit <file> <filter> [jq args...]: apply the filter to every document of the file, in place
jq_edit() {
  local f="$1" flt="$2"; shift 2
  assert_fixture_dir "$f"
  jq -c "$@" "$flt" "$f" >"$f.new" && mv "$f.new" "$f"
}
# jq_edit_doc <file> <index> <filter> [jq args...]: apply the filter to ONE document of a multi-document file
jq_edit_doc() {
  local f="$1" i="$2" flt="$3"; shift 3
  assert_fixture_dir "$f"
  jq -c -s --argjson i "$i" "$@" ".[\$i] |= ($flt) | .[]" "$f" >"$f.new" && mv "$f.new" "$f"
}
# mkjob <id> <name> <conclusion> <runner_id json> <started_at json> <completed_at json> [run_id=108]
mkjob() {
  jq -c -n --argjson id "$1" --arg name "$2" --arg c "$3" --argjson r "$4" --argjson s "$5" --argjson e "$6" --argjson run "${7:-108}" \
    '{id: $id, run_id: $run, name: $name, conclusion: $c, runner_id: $r, started_at: $s, completed_at: $e}'
}
# put_jobs <file> <job json...>: replace a jobs file by these jobs (total_count = their number)
put_jobs() {
  local f="$1"; shift
  assert_fixture_dir "$f"
  local IFS=,
  jq -c -n --argjson j "[$*]" '{total_count: ($j | length), jobs: $j}' >"$f"
}
TS0='"2026-10-07T14:10:00Z"'; TS60='"2026-10-07T14:11:00Z"'; TS120='"2026-10-07T14:12:00Z"'

# Canonical fixture-dir guard (copied byte-for-byte from plugins/soleur/test/test-helpers.sh; fixture-dir-operand-assert.test.sh pins every copy).
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

CUR_S="$CENSUS"   # the script rows() is currently exercising (the real one, or the H1 stub)
# caught <row> <label> <dir> <keyword> [rc=3]: the mutant must exit <rc> exactly, name its reason, print no total
caught() {
  local row="$1" label="$2" dir="$3" kw="$4" want="${5:-3}"
  run_census "$CUR_S" --fixture "$dir" --summary
  chk "$row" "$label: exit $want exactly (got $RC)" rc_is "$want"
  chk "$row" "$label: stderr names the reason '$kw'" hasi "$kw" "$ERR"
  chk_not "$row" "$label: no TOTAL_JOB_MINUTES line" has TOTAL_JOB_MINUTES "$OUT"
}
landing() { chk "$1" "$2: mutation landed (bytes differ from the committed fixture)" landed "$3"; }

# ─────────────────────────────────────────────────────────────────────────────
# rows <script>: rows 1-8, parameterised on the script under test so H1 can reuse them
# ─────────────────────────────────────────────────────────────────────────────
rows() {
  local S="$1" d id rc k c s r u sum nline stray
  CUR_S="$1"

  # ---- Row 5: goldens over the committed fixture (the classification predicate) ----
  run_census "$S" --fixture "$FIXTURE" --summary
  chk 5 "fixture run exits 0 (got $RC)" rc_is 0
  chk 5 "TOTAL_JOB_MINUTES equals the hand-computed golden ($WANT_TOTAL)" hasx "$WANT_TOTAL" "$OUT"
  chk 5 "TOTAL_JOB_SECONDS equals the integer golden ($WANT_SECS)" hasx "$WANT_SECS" "$OUT"
  nline=$(grep -c '^TOTAL_JOB_MINUTES=' "$OUT")
  chk 5 "exactly one TOTAL_JOB_MINUTES line (got $nline)" [ "$nline" -eq 1 ]
  for k in RUNS_COMPLETED=10 RUNS_NOT_COMPLETED=1 RUNS_RERUN=0 JOBS_COUNTED=22 JOBS_SKIPPED=4 JOBS_RUNNERLESS=4 JOBS_UNTIMED=2; do
    chk 5 "key line $k" hasx "$k" "$OUT"
  done
  c=$(sed -n 's/^JOBS_COUNTED=//p' "$OUT"); s=$(sed -n 's/^JOBS_SKIPPED=//p' "$OUT")
  r=$(sed -n 's/^JOBS_RUNNERLESS=//p' "$OUT"); u=$(sed -n 's/^JOBS_UNTIMED=//p' "$OUT")
  sum=$(( ${c:-0} + ${s:-0} + ${r:-0} + ${u:-0} ))
  chk 5 "partition: counted+skipped+runnerless+untimed ($sum) = jobs of completed runs ($FIX_JOBS_TOTAL)" [ "$sum" -eq "$FIX_JOBS_TOTAL" ]
  chk 5 "BY_WORKFLOW and STEM tables equal the hand-computed tables (two-document jobs file, @ref path, dynamic runs on one path, nested parenthesis, stem in two workflows, unexpanded matrix name, superseded run 102)" \
    tables_equal "$T/want-tables.txt"
  stray=$(stray_lines "$OUT")
  chk 5 "output carries only KEY= lines and the two tables (stray lines: $stray)" [ "$stray" -eq 0 ]
  chk 5 "in-flight run produces a lower-bound WARN on stderr" grep -q 'WARN' "$ERR"
  cp "$OUT" "$T/first-$SINK.txt"
  run_census "$S" --fixture "$FIXTURE"
  chk 5 "--summary is the explicit selector: same output without it, and the run is deterministic" same "$T/first-$SINK.txt" "$OUT"
  run_census "$S" --help
  chk 5 "--help exits 0" rc_is 0
  chk 5 "--help prints the output schema on STDOUT" has TOTAL_JOB_SECONDS "$OUT"
  chk 5 "--help prints the STEM schema on stdout" has "runs_runnerless" "$OUT"
  chk 5 "--help writes nothing to stderr" [ ! -s "$ERR" ]
  run_census "$S" --bogus-flag
  chk 5 "an unknown flag exits 2 exactly (got $RC)" rc_is 2
  chk_not 5 "an unknown flag prints no total" has TOTAL_JOB_MINUTES "$OUT"

  # ---- Row 1: C2 existence ----
  for id in 101 104 111; do          # first, middle, last completed run
    new_mutant; rm -f "$d/jobs-$id.json"
    landing 1 "delete jobs-$id" "$d"
    caught 1 "missing jobs file of run $id" "$d" "C2"
    chk 1 "missing jobs file of run $id: message names $id" has "$id" "$ERR"
  done
  new_mutant; rm -f "$d/jobs-102.json" "$d/jobs-111.json"   # two runs after a compliant first
  landing 1 "delete jobs-102 and jobs-111" "$d"
  caught 1 "two missing jobs files after a compliant first" "$d" "C2"
  chk 1 "two missing jobs files: the message names the second missing run too (102)" has 102 "$ERR"
  chk 1 "two missing jobs files: the message names every missing run, not only the first (111)" has 111 "$ERR"
  new_mutant; rm -f "$d/jobs-108.json"                        # the run whose jobs total_count is 0 still needs its file
  landing 1 "delete jobs-108" "$d"
  caught 1 "completed run with total_count 0 and no jobs file" "$d" "C2"
  new_mutant; rm -f "$d/jobs-109.json"                        # in-flight run: its (decoy) file is not needed
  run_census "$S" --fixture "$d" --summary
  chk 1 "removing the in-progress run's decoy jobs file is harmless: exit 0" rc_is 0
  chk 1 "removing the in-progress run's decoy jobs file keeps the golden total" hasx "$WANT_TOTAL" "$OUT"

  # ---- Row 2: C2 count and consistency of a jobs file ----
  new_mutant; jq_edit "$d/jobs-102.json" '.jobs |= .[1:]'
  landing 2 "drop a job from jobs-102" "$d"
  caught 2 "jobs-102 truncated" "$d" "truncat"
  chk 2 "fewer jobs than total_count says 'fewer'" hasi "fewer jobs" "$ERR"
  new_mutant   # the two-document file: drop one job on page two only
  jq_edit "$d/jobs-101.json" 'if (.jobs | length) == 2 then .jobs |= .[1:] else . end'
  landing 2 "drop a job from page two of jobs-101" "$d"
  caught 2 "page two of the two-document jobs-101 truncated" "$d" "truncat"
  new_mutant; jq_edit "$d/jobs-102.json" '.jobs += [(.jobs[0] | .id = 99999)]'
  landing 2 "add one distinct job to jobs-102 (count above total_count)" "$d"
  caught 2 "one job more than total_count" "$d" "more jobs"
  chk_not 2 "more jobs than total_count does not say 'fewer'" hasi "fewer jobs" "$ERR"
  new_mutant; jq_edit_doc "$d/jobs-101.json" 1 '.jobs += [(.jobs[0] | .id = 99998)]'
  landing 2 "add one distinct job on page two of jobs-101" "$d"
  caught 2 "page two of jobs-101 holds one job too many" "$d" "more jobs"
  new_mutant; jq_edit "$d/jobs-102.json" '.jobs[1] = .jobs[0]'
  landing 2 "jobs-102: job 2 replaced by a copy of job 1 (a duplicate offsetting a lost job)" "$d"
  caught 2 "a duplicate offsetting a lost job" "$d" "truncat"
  new_mutant; jq_edit "$d/jobs-102.json" '.jobs += [.jobs[0]]'
  landing 2 "jobs-102: job 1 listed twice (unique count equals total_count)" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 2 "a pure duplicate job is de-duplicated: exit 0 (got $RC)" rc_is 0
  chk 2 "a pure duplicate job leaves the golden total unchanged" hasx "$WANT_TOTAL" "$OUT"
  new_mutant; jq_edit "$d/jobs-103.json" '.jobs |= map(.run_id = 999)'
  landing 2 "jobs-103: every job carries run_id 999" "$d"
  caught 2 "a jobs file replaying another run's jobs" "$d" "run_id"
  new_mutant; jq_edit_doc "$d/jobs-101.json" 1 '.total_count = 4'
  landing 2 "jobs-101: total_count lowered in the LAST document only" "$d"
  caught 2 "jobs documents disagree (last document differs)" "$d" "disagree"
  chk_not 2 "a disagreement is reported as a disagreement only (no count message on top)" hasi "more jobs" "$ERR"
  new_mutant; jq_edit_doc "$d/jobs-101.json" 0 '.total_count = 7'; jq_edit_doc "$d/jobs-101.json" 1 '.total_count = 6'
  landing 2 "jobs-101: total_count 7 and 6 in the two documents (both above the 5 jobs)" "$d"
  caught 2 "jobs documents disagree (both totals above the job count)" "$d" "disagree"
  chk_not 2 "a disagreement above the job count is not also reported as fewer jobs" hasi "fewer jobs" "$ERR"
  new_mutant; jq_edit_doc "$d/jobs-101.json" 0 '.total_count = 4'
  landing 2 "jobs-101: total_count lowered in the FIRST document only" "$d"
  caught 2 "jobs documents disagree (first document differs)" "$d" "disagree"
  new_mutant; jq_edit "$d/jobs-103.json" '.jobs[0].runner_id = "1001"'
  landing 2 "jobs-103: runner_id is the string \"1001\"" "$d"
  caught 2 "a string runner_id" "$d" "runner_id"
  new_mutant; jq_edit "$d/jobs-103.json" '.jobs[0].runner_id = false'
  landing 2 "jobs-103: runner_id is false" "$d"
  caught 2 "a boolean runner_id" "$d" "runner_id"

  # ---- Row 3: C1 against the listing's own total_count ----
  new_mutant; jq_edit "$d/runs-1.json" '.total_count = 1000'
  landing 3 "runs-1 total_count raised to the 1000-result cap" "$d"
  caught 3 "listing at the 1000-result cap" "$d" "C1"
  chk 3 "cap failure tells the operator to narrow the window" hasi 'narrow' "$ERR"
  new_mutant; jq_edit "$d/runs-2.json" '.total_count = 5'
  landing 3 "runs-2 total_count raised by one" "$d"
  caught 3 "one displaced run (count BELOW total_count)" "$d" "C1"
  new_mutant; jq_edit "$d/runs-2.json" '.total_count = 3'
  landing 3 "runs-2 total_count lowered by one" "$d"
  caught 3 "one run too many (count ABOVE total_count)" "$d" "C1"
  new_mutant                                                       # exactly 1000 unique runs: consistent, but AT the cap
  jq -c -n '{total_count: 1000, workflow_runs: [range(2001; 3001) | {id: ., status: "queued", event: "push", path: ".github/workflows/x.yml"}]}' >"$d/runs-2.json"
  landing 3 "runs-2 replaced by a consistent listing of exactly 1000 queued runs" "$d"
  caught 3 "a sub-window at the 1000-result cap, even when consistent" "$d" "1000"
  chk 3 "the at-cap message is actionable: it names the CENSUS_SUBWINDOW_S knob" has 'CENSUS_SUBWINDOW_S' "$ERR"
  chk 3 "the at-cap message says the sub-window is at or over the cap" hasi 'at or over the 1000-result cap' "$ERR"
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs[3] = .workflow_runs[2]'
  landing 3 "run 111 replaced by a copy of run 110" "$d"
  caught 3 "duplicate run leaves the unique count one short" "$d" "C1"
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs += [.workflow_runs[0]]'
  landing 3 "run 108 listed twice" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 3 "a pure duplicate (unique count equals total_count) is de-duplicated: exit 0 (got $RC)" rc_is 0
  chk 3 "a pure duplicate leaves the golden total unchanged" hasx "$WANT_TOTAL" "$OUT"
  chk 3 "a pure duplicate leaves the tables unchanged" tables_equal "$T/want-tables.txt"
  new_mutant; jq_edit_doc "$d/runs-1.json" 1 '.total_count = 6'
  landing 3 "runs-1 (two documents): total_count lowered in the LAST document only" "$d"
  caught 3 "listing documents disagree (last document differs)" "$d" "disagree"
  new_mutant; jq_edit_doc "$d/runs-1.json" 0 '.total_count = 6'
  landing 3 "runs-1 (two documents): total_count lowered in the FIRST document only" "$d"
  caught 3 "listing documents disagree (first document differs)" "$d" "disagree"

  # ---- Row 4: non-vacuity, and unreadable input is exit 2 ----
  new_mutant; printf '%s\n' '3' >>"$d/runs-1.json"
  landing 4 "a non-object document appended to runs-1.json" "$d"
  caught 4 "a runs file holding a document that is not an object" "$d" "not an object" 2
  new_mutant; jq_edit_doc "$d/runs-1.json" 1 'del(.total_count)'
  landing 4 "runs-1.json: the second document has no total_count" "$d"
  caught 4 "a runs document without total_count" "$d" "numeric total_count" 2
  new_mutant; jq_edit_doc "$d/jobs-101.json" 1 'del(.total_count)'
  landing 4 "jobs-101.json: the second document has no total_count" "$d"
  caught 4 "a jobs document without total_count" "$d" "unreadable jobs" 2
  new_mutant
  printf '%s\n' '{"total_count":0,"workflow_runs":[]}' >"$d/runs-1.json"
  printf '%s\n' '{"total_count":0,"workflow_runs":[]}' >"$d/runs-2.json"
  landing 4 "both listings emptied" "$d"
  caught 4 "listing with total_count 0" "$d" "non-vacuity"
  chk_not 4 "empty listing never prints TOTAL_JOB_MINUTES=0" has 'TOTAL_JOB_MINUTES=0' "$OUT"
  new_mutant
  for id in 101 102 103 104 105 106 107 108 109 110 111; do jq_edit "$d/jobs-$id.json" '.jobs |= map(.conclusion = "skipped")'; done
  landing 4 "every job concluded skipped" "$d"
  caught 4 "a window whose every job is skipped" "$d" "non-vacuity"
  new_mutant
  for id in 101 102 103 104 105 106 107 108 109 110 111; do jq_edit "$d/jobs-$id.json" '.jobs |= map(.conclusion = "success" | .runner_id = null)'; done
  landing 4 "every job is runner-less" "$d"
  caught 4 "a window whose every job is runner-less" "$d" "non-vacuity"
  new_mutant
  for id in 101 102 103 104 105 106 107 108 109 110 111; do jq_edit "$d/jobs-$id.json" '.jobs |= map(.conclusion = "success" | .runner_id = 1001 | .started_at = null)'; done
  landing 4 "every job is untimed" "$d"
  caught 4 "a window whose every job is untimed" "$d" "non-vacuity"
  new_mutant; : >"$d/runs-1.json"
  landing 4 "zero-byte runs-1.json" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 4 "a zero-byte runs file is unreadable: exit 2 exactly (got $RC)" rc_is 2
  chk_not 4 "a zero-byte runs file prints no total" has TOTAL_JOB_MINUTES "$OUT"
  new_mutant; printf '%s' '{not json' >"$d/runs-2.json"
  landing 4 "garbage runs-2.json" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 4 "invalid JSON in a runs file: exit 2 exactly (got $RC)" rc_is 2
  new_mutant; : >"$d/jobs-103.json"
  landing 4 "zero-byte jobs-103.json" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 4 "a zero-byte jobs file is unreadable: exit 2 exactly (got $RC)" rc_is 2
  d="$T/mut/empty-dir"; rm -rf "$d"; mkdir -p "$d"
  run_census "$S" --fixture "$d" --summary
  chk 4 "a fixture directory with no runs file: exit 2 exactly (got $RC)" rc_is 2
  run_census "$S" --fixture "$T/mut/does-not-exist" --summary
  chk 4 "a missing fixture directory: exit 2 exactly (got $RC)" rc_is 2

  # ---- Row 6: classification, stem kinds, superseded runs, names, rounding, re-runs ----
  # (a) class precedence and STEM kinds on MIXED sets, run 108 (lint.yml push):
  #     m: 2 counted (60 s + 120 s) + a runner-less success with null timestamps + runner_id 0  -> ran
  #     g: skipped with runner_id null and null timestamps, skipped with a runner and a null started_at -> skipped
  #     h: 1 skipped + 1 runner-less (success, runner_id null, both timestamps null)             -> runner-less
  new_mutant
  put_jobs "$d/jobs-108.json" \
    "$(mkjob 1081 'm (1/4)' success 1001 "$TS0" "$TS60")" "$(mkjob 1082 'm (2/4)' success 1001 "$TS0" "$TS120")" \
    "$(mkjob 1083 'm (3/4)' success null null null)" "$(mkjob 1084 'm (4/4)' success 0 "$TS0" "$TS60")" \
    "$(mkjob 1085 'g (a)' skipped null null null)" "$(mkjob 1086 'g (b)' skipped 1001 null "$TS60")" \
    "$(mkjob 1087 'h (1/2)' skipped null null null)" "$(mkjob 1088 'h (2/2)' success null null null)"
  landing 6 "jobs-108 rewritten with mixed stems" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "mixed stems: exit 0 (got $RC)" rc_is 0
  chk 6 "mixed stems: JOBS_COUNTED=24 (22 + the two counted m shards)" hasx "JOBS_COUNTED=24" "$OUT"
  chk 6 "mixed stems: JOBS_SKIPPED=7 (4 + g a, g b, h 1)" hasx "JOBS_SKIPPED=7" "$OUT"
  chk 6 "mixed stems: JOBS_RUNNERLESS=7 (4 + m 3, m 4, h 2: null runner beats null timestamps)" hasx "JOBS_RUNNERLESS=7" "$OUT"
  chk 6 "mixed stems: JOBS_UNTIMED=2 (a skipped job with a null started_at is skipped, not untimed)" hasx "JOBS_UNTIMED=2" "$OUT"
  chk 6 "mixed stems: TOTAL_JOB_SECONDS=$((S_TOTAL + 180))" hasx "TOTAL_JOB_SECONDS=$((S_TOTAL + 180))" "$OUT"
  chk 6 "mixed stems: TOTAL_JOB_MINUTES=105.6" hasx "TOTAL_JOB_MINUTES=105.6" "$OUT"
  chk 6 "mixed stems: 2 counted + 2 runner-less shards of one stem is 'ran'" \
    hasx "$(stem_line lint.yml push m 1 0 0 2 3.0 3.00)" "$OUT"
  chk 6 "mixed stems: all-skipped stem (with null and null-start timestamps) is 'skipped'" \
    hasx "$(stem_line lint.yml push g 0 1 0 0 0.0 0.00)" "$OUT"
  chk 6 "mixed stems: 1 skipped + 1 runner-less is 'runner-less', not 'skipped'" \
    hasx "$(stem_line lint.yml push h 0 0 1 0 0.0 0.00)" "$OUT"
  chk 6 "mixed stems: BY_WORKFLOW lint.yml push now has 2 counted jobs and 3.0 minutes" \
    hasx "$(bw_line lint.yml push 1 2 3.0)" "$OUT"

  # (b) a superseded run: its parent was queue-cancelled, so the dependents concluded skipped.
  #     Run 108 holds a cancelled job -> its all-skipped stem is runner-less; run 110 has no cancelled job
  #     (although run 108 does) -> its all-skipped stem stays skipped.
  new_mutant
  put_jobs "$d/jobs-108.json" \
    "$(mkjob 1081 prep cancelled null null null)" "$(mkjob 1082 'gate (a)' skipped null null null)" "$(mkjob 1083 'gate (b)' skipped null null null)"
  jq_edit "$d/jobs-110.json" '.jobs += [{id: 11003, run_id: 110, name: "gate2", conclusion: "skipped", runner_id: null, started_at: null, completed_at: null}] | .total_count += 1'
  landing 6 "jobs-108 superseded (cancelled parent), jobs-110 gains a skipped gate2" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "superseded run: exit 0 (got $RC)" rc_is 0
  chk 6 "superseded run: a stem with no counted job in a run holding a cancelled job is runner-less, not skipped" \
    hasx "$(stem_line lint.yml push gate 0 0 1 0 0.0 0.00)" "$OUT"
  chk 6 "superseded run: the cancelled job's own stem is runner-less" \
    hasx "$(stem_line lint.yml push prep 0 0 1 0 0.0 0.00)" "$OUT"
  chk 6 "superseded run: a skipped stem in a run WITHOUT a cancelled job stays skipped (the flag is per run)" \
    hasx "$(stem_line nightly.yml schedule gate2 0 1 0 0 0.0 0.00)" "$OUT"
  chk 6 "superseded run: JOBS_SKIPPED=7 (4 + gate a, gate b, gate2)" hasx "JOBS_SKIPPED=7" "$OUT"
  chk 6 "superseded run: JOBS_RUNNERLESS=5 (4 + the cancelled prep)" hasx "JOBS_RUNNERLESS=5" "$OUT"
  chk 6 "superseded run: the total is unchanged" hasx "$WANT_TOTAL" "$OUT"

  # (c) names: a job named only "(1/2)" keeps itself, an empty name becomes "unknown", a long stem is capped at 120
  local longname; longname=$(printf 'a%.0s' $(seq 1 200))
  new_mutant
  put_jobs "$d/jobs-108.json" \
    "$(mkjob 1081 '(1/2)' success 1001 "$TS0" "$TS60")" "$(mkjob 1082 '' success 1001 "$TS0" "$TS60")" \
    "$(mkjob 1083 "$longname (x)" success 1001 "$TS0" "$TS60")"
  landing 6 "jobs-108 rewritten with a suffix-only name, an empty name and a 200-character name" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "names: exit 0 (got $RC)" rc_is 0
  chk 6 "names: a job named '(1/2)' falls back to its own name as the stem" hasx "$(stem_line lint.yml push '(1/2)' 1 0 0 1 1.0 1.00)" "$OUT"
  chk 6 "names: an empty job name becomes the stem 'unknown'" hasx "$(stem_line lint.yml push unknown 1 0 0 1 1.0 1.00)" "$OUT"
  chk 6 "names: a 200-character stem is capped at 120 characters" \
    hasx "$(stem_line lint.yml push "$(printf 'a%.0s' $(seq 1 120))" 1 0 0 1 1.0 1.00)" "$OUT"

  # (d) every hostile character class is replaced by ?: U+0085, U+2028, U+2029, DEL, bidi controls,
  #     zero-width/format characters, backtick, < and >
  local -a hclass=($'\xc2\x85' $'\xe2\x80\xa8' $'\xe2\x80\xa9' $'\x7f' $'\xe2\x80\xaa' $'\xe2\x80\xae' $'\xe2\x81\xa6' $'\xe2\x81\xa9' $'\xe2\x80\x8b' $'\xe2\x80\x8f' $'\xd8\x9c' $'\xef\xbb\xbf' '`' '<' '>')
  local hname="k" hwant="k" hc leaks=0
  for hc in "${hclass[@]}"; do hname="$hname${hc}k"; hwant="${hwant}?k"; done
  new_mutant
  put_jobs "$d/jobs-108.json" "$(mkjob 1081 "$hname" success 1001 "$TS0" "$TS60")"
  landing 6 "jobs-108 rewritten with a job whose name carries every hostile class" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "hostile classes: exit 0 (got $RC)" rc_is 0
  chk 6 "hostile classes: every class became exactly one ? (U+0085, U+2028/9, DEL, bidi, zero-width, BOM, backtick, <, >)" \
    hasx "$(stem_line lint.yml push "$hwant" 1 0 0 1 1.0 1.00)" "$OUT"
  for hc in "${hclass[@]}"; do if has "$hc" "$OUT"; then leaks=$((leaks + 1)); fi; done
  chk 6 "hostile classes: none of the $((${#hclass[@]})) raw characters reaches stdout (leaks: $leaks)" [ "$leaks" -eq 0 ]

  # (e) a reversed job (completed before started) is untimed; fractional seconds are normalised
  new_mutant; jq_edit "$d/jobs-103.json" '.jobs |= map(if .name == "test-scripts (1/8)" then .completed_at = "2026-10-07T13:10:00Z" else . end)'
  landing 6 "jobs-103: test-scripts (1/8) completes 5 s before it starts" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "reversed job: exit 0 (got $RC)" rc_is 0
  chk 6 "reversed job: JOBS_UNTIMED=3" hasx "JOBS_UNTIMED=3" "$OUT"
  chk 6 "reversed job: JOBS_COUNTED=21" hasx "JOBS_COUNTED=21" "$OUT"
  chk 6 "reversed job: no negative minutes, TOTAL_JOB_SECONDS=$((S_TOTAL - 360))" hasx "TOTAL_JOB_SECONDS=$((S_TOTAL - 360))" "$OUT"
  chk_not 6 "reversed job: no '-' in any figure" grep -qE "(MINUTES|SECONDS)=-|${TAB}-[0-9]" "$OUT"
  new_mutant; jq_edit "$d/jobs-103.json" '.jobs |= map(if .name == "test-scripts (1/8)" then .started_at = "2026-10-07T13:10:05.123Z" | .completed_at = "2026-10-07T13:16:05.987Z" else . end)'
  landing 6 "jobs-103: fractional-second timestamps on test-scripts (1/8)" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "fractional seconds: exit 0 instead of aborting (got $RC)" rc_is 0
  chk 6 "fractional seconds: truncated to the second, the golden total is unchanged" hasx "$WANT_SECS" "$OUT"

  # (f) rounding ties, integer-exact. 107's Analyze job is cut to 7 s and nightly's report to 6 s:
  #     total 6154 - 330 + 7 - 50 + 6 = 5787 s = 96.45 min -> 96.5
  #     dynamic 300 + 200 + 7 = 507 s = 8.45 min -> 8.5; per run (2 runs) 4.225 -> 4.23
  #     nightly report 6 s = 0.1 min, 0.10 per run; nightly 156 s = 2.6 min
  new_mutant
  jq_edit "$d/jobs-107.json" '.jobs |= map(if .name == "Analyze (javascript-typescript)" then .completed_at = "2026-10-07T13:10:12Z" else . end)'
  jq_edit "$d/jobs-110.json" '.jobs |= map(if .name == "report" then .started_at = "2026-10-07T13:10:00Z" | .completed_at = "2026-10-07T13:10:06Z" else . end)'
  landing 6 "durations cut to 7 s (run 107) and 6 s (run 110 report)" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "ties: exit 0 (got $RC)" rc_is 0
  chk 6 "ties: TOTAL_JOB_SECONDS=5787" hasx "TOTAL_JOB_SECONDS=5787" "$OUT"
  chk 6 "ties: 96.45 minutes rounds half up to 96.5" hasx "TOTAL_JOB_MINUTES=96.5" "$OUT"
  chk 6 "ties: BY_WORKFLOW dynamic 8.45 minutes rounds half up to 8.5" \
    hasx "$(bw_line dynamic/github-code-scanning/codeql dynamic 2 3 8.5)" "$OUT"
  chk 6 "ties: per-run 4.225 rounds half up to 4.23 (a float round gives 4.22)" \
    hasx "$(stem_line dynamic/github-code-scanning/codeql dynamic Analyze 2 0 0 3 8.5 4.23)" "$OUT"
  chk 6 "ties: a 6 s job is 0.1 minutes and 0.10 per run" hasx "$(stem_line nightly.yml schedule report 1 0 0 1 0.1 0.10)" "$OUT"
  chk 6 "ties: the independent integer oracle agrees on the total (96.5)" [ "$(fmt 5787 1)" = "96.5" ]
  chk 6 "ties: the independent integer oracle agrees on the dynamic row (8.5, 4.23)" [ "$(fmt 507 1) $(fmt 507 2 2)" = "8.5 4.23" ]

  # (g) re-runs: RUNS_RERUN counts COMPLETED runs with run_attempt > 1
  new_mutant; jq_edit "$d/runs-1.json" '.workflow_runs |= map(if .id == 104 then .run_attempt = 2 else . end)'
  landing 6 "run 104 is attempt 2" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "re-run: RUNS_RERUN=1 for one completed run at attempt 2" hasx "RUNS_RERUN=1" "$OUT"
  chk 6 "re-run: the total is unchanged" hasx "$WANT_TOTAL" "$OUT"
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs |= map(if .id == 109 then .run_attempt = 3 else . end)'
  landing 6 "in-flight run 109 is attempt 3" "$d"
  run_census "$S" --fixture "$d" --summary
  chk 6 "re-run: an in-flight run at attempt 3 is not counted (RUNS_RERUN=0)" hasx "RUNS_RERUN=0" "$OUT"

  # ---- Row 7: --workflow ----
  run_census "$S" --fixture "$FIXTURE" --workflow secret-scan.yml
  chk 7 "--workflow secret-scan.yml exits 0 (got $RC)" rc_is 0
  chk 7 "--workflow: the output says which filter was applied" hasx "WORKFLOW_FILTER=secret-scan.yml" "$OUT"
  chk 7 "--workflow: TOTAL_JOB_SECONDS is that workflow's $S_SS_PR s" hasx "TOTAL_JOB_SECONDS=$S_SS_PR" "$OUT"
  chk 7 "--workflow: TOTAL_JOB_MINUTES is that workflow's total" hasx "TOTAL_JOB_MINUTES=$(fmt "$S_SS_PR" 1)" "$OUT"
  for k in RUNS_COMPLETED=3 RUNS_NOT_COMPLETED=0 JOBS_COUNTED=8 JOBS_SKIPPED=2 JOBS_RUNNERLESS=2 JOBS_UNTIMED=0; do
    chk 7 "--workflow secret-scan.yml: key line $k" hasx "$k" "$OUT"
  done
  chk 7 "--workflow: the tables hold exactly the secret-scan.yml rows of the full tables" tables_equal "$T/want-tables-ss.txt"
  run_census "$S" --fixture "$FIXTURE" --workflow ci.yml
  chk 7 "--workflow ci.yml (a run whose path carries @ref): exit 0 (got $RC)" rc_is 0
  chk 7 "--workflow ci.yml: the @ref-suffixed run 103 is included (3 completed runs)" hasx "RUNS_COMPLETED=3" "$OUT"
  chk 7 "--workflow ci.yml: the in-flight ci.yml run is excluded and counted" hasx "RUNS_NOT_COMPLETED=1" "$OUT"
  chk 7 "--workflow ci.yml: the tables hold exactly the ci.yml rows" tables_equal "$T/want-tables-ci.txt"
  run_census "$S" --fixture "$FIXTURE" --workflow nightly.yml
  chk 7 "--workflow filters the totals (nightly.yml alone is $S_NIGHT s)" hasx "TOTAL_JOB_SECONDS=$S_NIGHT" "$OUT"
  new_mutant; rm -f "$d/jobs-101.json"
  landing 7 "delete jobs-101 (a ci.yml run)" "$d"
  run_census "$S" --fixture "$d" --workflow secret-scan.yml
  chk 7 "--workflow secret-scan.yml ignores a missing jobs file of another workflow: exit 0 (got $RC)" rc_is 0
  chk 7 "--workflow secret-scan.yml ignores another workflow's missing jobs file: same total" hasx "TOTAL_JOB_SECONDS=$S_SS_PR" "$OUT"
  new_mutant; rm -f "$d/jobs-104.json"
  landing 7 "delete jobs-104 (a secret-scan.yml run)" "$d"
  run_census "$S" --fixture "$d" --workflow secret-scan.yml
  chk 7 "--workflow secret-scan.yml: C2 still applies to the fetched set (exit 3, got $RC)" rc_is 3
  chk 7 "--workflow secret-scan.yml: C2 names the missing run" has 104 "$ERR"
  run_census "$S" --fixture "$FIXTURE" --workflow does-not-exist.yml
  chk 7 "--workflow of an unknown file exits 3 exactly (got $RC)" rc_is 3
  chk 7 "--workflow of an unknown file names the workflow" has does-not-exist.yml "$ERR"
  chk_not 7 "--workflow of an unknown file prints no total" has TOTAL_JOB_MINUTES "$OUT"
  run_census "$S" --fixture "$FIXTURE" --workflow 'bad name;x'
  chk 7 "--workflow with a malformed name exits 2 exactly (got $RC)" rc_is 2

  # ---- Row 8: the windows.tsv manifest and created_at checks ----
  new_mutant; rm -f "$d/runs-2.json"
  landing 8 "delete runs-2.json (the last listing)" "$d"
  caught 8 "a deleted last listing is a gap (the manifest lists two windows)" "$d" "runs-2.json"
  new_mutant; rm -f "$d/windows.tsv"; cp "$d/runs-2.json" "$d/runs-3.json"; rm -f "$d/runs-2.json"
  landing 8 "no manifest; runs-2.json deleted, runs-3.json present" "$d"
  caught 8 "a numbering gap without a manifest (runs-1, runs-3)" "$d" "runs-2.json"
  new_mutant; mv "$d/runs-2.json" "$d/runs-3.json"
  landing 8 "runs-2.json renamed runs-3.json (as many files as windows, but the wrong numbers)" "$d"
  caught 8 "right file count, wrong numbers: runs-2.json missing" "$d" "runs-2.json"
  new_mutant; cp "$d/runs-2.json" "$d/runs-3.json"
  landing 8 "runs-3.json added beyond the manifest" "$d"
  caught 8 "a listing beyond the manifest" "$d" "runs-3.json"
  new_mutant; printf '1\t2026-10-07T13:00:00Z\n' >"$d/windows.tsv"
  landing 8 "windows.tsv with a short line" "$d"
  caught 8 "a malformed manifest line" "$d" "windows.tsv" 2
  new_mutant; : >"$d/windows.tsv"
  landing 8 "empty windows.tsv" "$d"
  caught 8 "an empty manifest" "$d" "windows.tsv" 2
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs |= map(if .id == 108 then .created_at = "2026-10-07T13:30:00Z" else . end)'
  landing 8 "run 108 created inside window 1 but listed in runs-2.json" "$d"
  caught 8 "a run listed in the wrong sub-window" "$d" "outside"
  chk 8 "the outside-window failure names the run" has 108 "$ERR"
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs |= map(if .id == 110 then del(.created_at) else . end)'
  landing 8 "run 110 has no created_at" "$d"
  caught 8 "a run without created_at" "$d" "outside"
  for k in "2026-10-07T13:00:00Z" "2026-10-07T13:59:59Z" "2026-10-07T13:20:00.500Z"; do
    new_mutant; jq_edit "$d/runs-1.json" '.workflow_runs |= map(if .id == 104 then .created_at = $t else . end)' --arg t "$k"
    landing 8 "run 104 created at $k (inside window 1)" "$d"
    run_census "$S" --fixture "$d" --summary
    chk 8 "created_at $k is inside window 1: exit 0 (got $RC)" rc_is 0
  done
  for k in "2026-10-07T12:59:59Z" "2026-10-07T14:00:00Z"; do
    new_mutant; jq_edit "$d/runs-1.json" '.workflow_runs |= map(if .id == 104 then .created_at = $t else . end)' --arg t "$k"
    landing 8 "run 104 created at $k (just outside window 1)" "$d"
    caught 8 "created_at $k is one second outside window 1" "$d" "outside"
  done
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN RUN: rows 1-8 against the real script
# ─────────────────────────────────────────────────────────────────────────────
FIX_SUM_BEFORE=$(find "$FIXTURE" -type f -exec cksum {} + 2>/dev/null | sort)
rows "$CENSUS"
FIX_SUM_AFTER=$(find "$FIXTURE" -type f -exec cksum {} + 2>/dev/null | sort)
chk 0 "the committed fixture directory was listed (non-empty checksum)" [ -n "$FIX_SUM_BEFORE" ]
chk 0 "the committed fixture directory is byte-identical after every run (read-only, nothing written into the repo)" \
  [ "$FIX_SUM_BEFORE" = "$FIX_SUM_AFTER" ]

# the discoverability command from the plan, literally, from the repo root
DISC_OUT=$(cd "$REPO_ROOT" && bash scripts/ci-demand-census.sh --fixture scripts/fixtures/ci-demand-census/basic --summary 2>/dev/null)
chk 0 "discoverability_test command prints a line starting TOTAL_JOB_MINUTES=" grep -q '^TOTAL_JOB_MINUTES=' <<<"$DISC_OUT"

# ── header documents the definitions the parent plan deferred to this PR ──
HDR=$(sed -n '1,/^set -/p' "$CENSUS" 2>/dev/null || true)
for kw in "lower bound" "closed window"; do
  chk 0 "script header documents '$kw'" grep -qiF -- "$kw" <<<"$HDR"
done

# ── TMPDIR must be absolute: refused before anything runs, never after the total was printed ──
mkdir -p "$T/reltmp/sub"
( cd "$T/reltmp" && env TMPDIR=sub bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR" ); RC=$?
chk 0 "a relative TMPDIR is refused with exit 2 exactly (got $RC)" rc_is 2
chk 0 "a relative TMPDIR refusal says it is about TMPDIR" has TMPDIR "$ERR"
chk_not 0 "a relative TMPDIR prints no total (the refusal comes before any output)" has TOTAL_JOB_MINUTES "$OUT"
chk 0 "a relative TMPDIR is refused with no output at all" [ ! -s "$OUT" ]
chk 0 "a relative TMPDIR leaves no scratch directory behind" [ -z "$(ls -A "$T/reltmp/sub")" ]
env TMPDIR=/tmp/../tmp bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR"; RC=$?
chk 0 "a TMPDIR containing .. is refused with exit 2 exactly (got $RC)" rc_is 2
chk 0 "a TMPDIR containing .. is refused BEFORE any output (not from the EXIT trap after a total was printed)" [ ! -s "$OUT" ]

# ── the sanitiser for stderr (tame): ESC bytes and over-long values ──
env -u GITHUB_ACTIONS bash "$CENSUS" --start "$(printf '2026-10-07T13:00:00Z\033[31mX')" --end 2026-10-07T14:00:00Z >"$OUT" 2>"$ERR"; RC=$?
chk 0 "an ESC byte in --start is refused with exit 2 (got $RC)" rc_is 2
chk_not 0 "an ESC byte in --start never reaches stderr" has "$ESC" "$ERR"
LONGV=$(printf 'Q%.0s' $(seq 1 500))
env -u GITHUB_ACTIONS bash "$CENSUS" --start "$LONGV" --end 2026-10-07T14:00:00Z >"$OUT" 2>"$ERR"; RC=$?
chk 0 "an over-long --start is refused with exit 2 (got $RC)" rc_is 2
chk 0 "an over-long --start is echoed capped at 200 characters (got $(tr -cd Q <"$ERR" | wc -c))" [ "$(tr -cd Q <"$ERR" | wc -c)" -eq 200 ]
env bash "$CENSUS" --bad-flag-"$(printf 'x\033[31m<b>`c`')" >"$OUT" 2>"$ERR"; RC=$?
chk 0 "an unknown flag with ESC, <, > and backticks is refused with exit 2 (got $RC)" rc_is 2
chk 0 "the echoed unknown flag has ESC, <, > and both backticks replaced by ?" has 'unknown argument: --bad-flag-x?[31m?b??c?' "$ERR"
chk_not 0 "the echoed unknown flag carries no ESC byte" has "$ESC" "$ERR"
chk_not 0 "the echoed unknown flag carries no backtick" has '`' "$ERR"

# ── hostile names: one clean line, no ESC byte, no line starting with :: ──
new_mutant
HOSTILE_NAME=$(printf '::error::x\t\033[31mpwn (1/2)')
jq_edit "$d/jobs-104.json" '.jobs |= map(if .name == "gitleaks scan" then .name = $n else . end)' --arg n "$HOSTILE_NAME"
jq_edit "$d/runs-1.json" '.workflow_runs |= map(if (.id == 106 or .id == 107) then .path = $p else . end)' --arg p "$(printf 'dynamic/evil\n::error::y')"
landing 0 "hostile job name and workflow path" "$d"
run_census "$CENSUS" --fixture "$d" --summary
chk 0 "hostile-name fixture still exits 0 (got $RC)" rc_is 0
chk_not 0 "hostile names: no ESC byte reaches stdout" has "$ESC" "$OUT"
chk_not 0 "hostile names: no stdout line starts with ::" grep -q '^::' "$OUT"
chk 0 "hostile names: every stdout line starts with a fixed token" [ "$(stray_lines "$OUT")" -eq 0 ]
chk 0 "hostile names: the hostile stem is exactly one STEM line" \
  [ "$(grep -c "^STEM${TAB}secret-scan.yml${TAB}pull_request${TAB}::error::x" "$OUT")" -eq 1 ]
chk 0 "hostile names: STEM lines keep 10 tab fields and BY_WORKFLOW lines 6" \
  awk -F'\t' '/^STEM\t/ && NF != 10 { bad = 1 } /^BY_WORKFLOW\t/ && NF != 6 { bad = 1 } END { exit bad }' "$OUT"
chk 0 "hostile names: exactly one extra line (the renamed stem splits out of 'gitleaks scan'), so no hostile text became extra lines" \
  [ "$(wc -l <"$OUT")" -eq $(( $(wc -l <"$T/first-main.txt") + 1 )) ]

# ── jq failures are fail-closed: a jq that fails ONLY one filter never yields a total ──
cat >"$T/jqbin/jq" <<'SHIM'
#!/usr/bin/env bash
# Test shim for jq: exits 5 for any call whose arguments contain $JQ_FAIL_MATCH, else runs the real jq.
case "$*" in *"${JQ_FAIL_MATCH:-@@never@@}"*) printf 'jq: shim-induced failure\n' >&2; exit 5 ;; esac
exec "$REAL_JQ" "$@"
SHIM
chmod +x "$T/jqbin/jq"
run_jq_fail() { # <filter fragment that selects the one call to break>
  env PATH="$T/jqbin:$PATH" REAL_JQ="$REAL_JQ" JQ_FAIL_MATCH="$1" bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR"; RC=$?
}
run_jq_fail '@@never@@'
chk 0 "jq shim in pass-through mode behaves like the real jq: exit 0 and the golden total" hasx "$WANT_TOTAL" "$OUT"
for _frag in 'FEWER' '.[] | .id | tostring' 'TOTAL_JOB_SECONDS' 'unique_by(.id)) as $j' 'unique | map(tostring)' 'map(select($wf == '; do
  run_jq_fail "$_frag"
  chk J "jq failing only on the filter containing '$_frag': exit 2 exactly (got $RC)" rc_is 2
  chk_not J "jq failing only on the filter containing '$_frag': no TOTAL_JOB_MINUTES line" has TOTAL_JOB_MINUTES "$OUT"
done

# ─────────────────────────────────────────────────────────────────────────────
# H1: the row function against a stub that prints the golden total. Rows 1-8 must go RED.
# ─────────────────────────────────────────────────────────────────────────────
STUB="$T/stub-census.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\nexit 0\n' "$WANT_TOTAL" >"$STUB"
SINK=stub
rows "$STUB"
SINK=main
for _r in 1 2 3 4 5 6 7 8; do
  chk H1 "stub printing only the golden total goes RED on row $_r (stub failures: ${STUB_FAILS[$_r]:-0})" \
    [ "${STUB_FAILS[$_r]:-0}" -gt 0 ]
done
chk H1 "the stub does pass the one assertion it can fake (the instrument distinguishes the verdicts, passes: ${STUB_PASSES[5]:-0})" \
  [ "${STUB_PASSES[5]:-0}" -gt 0 ]

# ─────────────────────────────────────────────────────────────────────────────
# LIVE LAYER: a gh shim serving the committed fixture per exact endpoint
# ─────────────────────────────────────────────────────────────────────────────
cat >"$T/bin/gh" <<'SHIM'
#!/usr/bin/env bash
# Test shim for `gh`: exact endpoints, whitelisted flags, every call logged. Unknown flags
# (-f/-F/-X/--method would turn a GET into a POST on the real CLI) exit 64.
log() { printf '%s\n' "$*" >>"$SHIM_LOG"; }
if [ "${1:-}" = repo ]; then
  if [ "$*" = "repo view --json nameWithOwner -q .nameWithOwner" ]; then log "REPOVIEW"; echo "$SHIM_REPO"; exit 0; fi
  log "BAD $*"; exit 64
fi
[ "${1:-}" = api ] || { log "BAD $*"; exit 64; }
shift
paginate=0; ep=""
for a in "$@"; do
  case "$a" in
    --paginate) paginate=1 ;;
    -*) log "BAD flag $a"; exit 64 ;;
    *) [ -z "$ep" ] || { log "BAD extra $a"; exit 64; }; ep="$a" ;;
  esac
done
[ "$paginate" = 1 ] || { log "BAD no --paginate $ep"; exit 64; }
case "$ep" in
  "repos/$SHIM_REPO/actions/runs?created="*"&per_page=100")
    n=$(grep -c '^RUNS ' "$SHIM_LOG" 2>/dev/null || true); n=$((n + 1))
    log "RUNS $ep"
    case "$ep" in *"${SHIM_FAIL_RUNS:-@@none@@}"*) echo "gh: HTTP 500" >&2; exit 1 ;; esac
    if [ -n "${SHIM_EMPTY_RUNS:-}" ]; then printf '{"total_count":0,"workflow_runs":[]}\n'; exit 0; fi
    if [ -f "$SHIM_FIXTURE/runs-$n.json" ]; then cat "$SHIM_FIXTURE/runs-$n.json"
    else printf '{"total_count":0,"workflow_runs":[]}\n'; fi ;;
  "repos/$SHIM_REPO/actions/runs/"*"/jobs?per_page=100&filter=latest")
    id=${ep#"repos/$SHIM_REPO/actions/runs/"}; id=${id%%/*}
    log "JOBS $id"
    [ "${SHIM_FAIL_RUN:-}" = "$id" ] && exit 1
    if [ "${SHIM_RATELIMIT_RUN:-}" = "$id" ]; then echo "gh: API rate limit exceeded for user ID 1. (HTTP 403)" >&2; exit 1; fi
    if [ "${SHIM_HANG_RUN:-}" = "$id" ]; then exec "$REAL_SLEEP" 5; fi
    if [ "${SHIM_PARTIAL_RUN:-}" = "$id" ]; then head -n 1 "$SHIM_FIXTURE/jobs-$id.json"; exit 1; fi
    [ -f "$SHIM_FIXTURE/jobs-$id.json" ] || exit 1
    cat "$SHIM_FIXTURE/jobs-$id.json" ;;
  *) log "BAD endpoint $ep"; exit 64 ;;
esac
SHIM
chmod +x "$T/bin/gh"
# a sleep that only logs its argument, so the retry schedule is observable without waiting
cat >"$T/sbin/sleep" <<'SHIM'
#!/usr/bin/env bash
printf 'SLEEP %s\n' "$*" >>"$SHIM_LOG"
SHIM
chmod +x "$T/sbin/sleep"

LIVE_REPO=example-org/example-repo
LIVE_START=2026-10-07T13:00:00Z
LIVE_END=2026-10-07T15:00:00Z      # exclusive: the two one-hour sub-windows end at 14:59:59
SHIM_LOG="$T/shim.log"
LIVE_EXTRA=""
# run_live <fixture-dir> <args...>: live mode through the shim. Sets RC OUT ERR; the shim log is reset per call.
# LIVE_EXTRA="NAME=value ..." adds environment variables for one call; LIVE_PATH_PRE prepends a PATH directory.
run_live() {
  local fx="$1"; shift
  : >"$SHIM_LOG"
  # shellcheck disable=SC2086
  env -u GITHUB_ACTIONS PATH="${LIVE_PATH_PRE:+$LIVE_PATH_PRE:}$T/bin:$PATH" SHIM_FIXTURE="$fx" SHIM_LOG="$SHIM_LOG" SHIM_REPO="$LIVE_REPO" \
    REAL_SLEEP="$REAL_SLEEP" GH_REPO="${LIVE_GH_REPO-$LIVE_REPO}" CENSUS_RETRY_SLEEP="${LIVE_RETRY_SLEEP-0}" TMPDIR="$T/live" \
    SHIM_FAIL_RUN="${LIVE_FAIL_RUN:-}" $LIVE_EXTRA bash "$CENSUS" "$@" >"$OUT" 2>"$ERR"; RC=$?
}
shim_count() { grep -c "^$1" "$SHIM_LOG" 2>/dev/null || true; }
runs_endpoints() { # the created= ranges of every runs call, space-separated, in call order
  sed -n 's/^RUNS //p' "$SHIM_LOG" | sed -e "s#^repos/$LIVE_REPO/actions/runs?created=##" -e 's#&per_page=100$##' | paste -sd' ' -
}
jobs_called() { sed -n 's/^JOBS //p' "$SHIM_LOG" | sort -n | uniq | paste -sd' ' -; }

# L1: round trip. The fetched directory must equal the committed fixture and give the same golden.
run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L1 "live mode through the shim exits 0 (got $RC)" rc_is 0
chk L1 "live total equals the golden" hasx "$WANT_TOTAL" "$OUT"
chk L1 "live tables equal the hand-computed tables" tables_equal "$T/want-tables.txt"
chk L1 "live header carries REPO" hasx "REPO=$LIVE_REPO" "$OUT"
chk L1 "live header carries WINDOW_START" hasx "WINDOW_START=$LIVE_START" "$OUT"
chk L1 "live header carries WINDOW_END" hasx "WINDOW_END=$LIVE_END" "$OUT"
chk L1 "live header carries FETCHED_AT" grep -q '^FETCHED_AT=' "$OUT"
chk L1 "two one-hour sub-windows partition the exclusive span exactly (second shifted by one second)" \
  [ "$(runs_endpoints)" = "2026-10-07T13:00:00Z..2026-10-07T13:59:59Z 2026-10-07T14:00:00Z..2026-10-07T14:59:59Z" ]
chk L1 "jobs fetched for exactly the 10 completed runs (not the in-flight 109)" \
  [ "$(jobs_called)" = "101 102 103 104 105 106 107 108 110 111" ]
chk L1 "every runs-listing call precedes the first jobs call (C1 before any jobs call)" \
  [ "$(grep -n '^RUNS ' "$SHIM_LOG" | tail -1 | cut -d: -f1)" -lt "$(grep -n '^JOBS ' "$SHIM_LOG" | head -1 | cut -d: -f1)" ]
chk_not L1 "the shim saw no BAD call (only GETs, whitelisted flags, exact endpoints)" grep -q '^BAD' "$SHIM_LOG"
DATA_DIR=$(sed -n 's/^census: data dir: //p' "$ERR" | head -1)
in_live_tmp() { [ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ] && case "$DATA_DIR" in "$T"/live/*) true ;; *) false ;; esac; }
chk L1 "stderr names the fetched data directory under TMPDIR" in_live_tmp
chk L1 "last stderr line is the delete command for that directory" \
  [ "$(tail -1 "$ERR")" = "census: remove fetched data with: rm -rf $DATA_DIR" ]
RT_OK=0
for f in jobs-101 jobs-102 jobs-103 jobs-104 jobs-105 jobs-106 jobs-107 jobs-108 jobs-110 jobs-111; do
  cmp -s "$FIXTURE/$f.json" "$DATA_DIR/$f.json" || RT_OK=1
done
chk L1 "the fetched jobs files are byte-identical to the committed fixture" [ "$RT_OK" -eq 0 ]
chk L1 "jobs-109 was not fetched (in-flight run)" [ ! -e "$DATA_DIR/jobs-109.json" ]
chk L1 "the fetched manifest windows.tsv is byte-identical to the committed fixture's" same "$FIXTURE/windows.tsv" "$DATA_DIR/windows.tsv"
for f in runs-1 runs-2; do
  jq -c '{total_count: .total_count, workflow_runs: [.workflow_runs[] | {id, status, event, path, created_at, run_attempt}]}' "$FIXTURE/$f.json" >"$T/want-$f.json"
  chk L1 "the fetched $f.json is the committed listing trimmed to id, status, event, path, created_at, run_attempt" same "$T/want-$f.json" "$DATA_DIR/$f.json"
done
chk_not L1 "no actor, commit or branch field survives in the fetched listings" grep -qE 'head_sha|head_branch|display_title|node_id|"url"|actor' "$DATA_DIR/runs-1.json" "$DATA_DIR/runs-2.json"
run_census "$CENSUS" --fixture "$DATA_DIR" --summary
grep -v -E '^(REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT)=' "$OUT" >"$T/fix-mode-body.txt"
run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
grep -v -E '^(REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT)=' "$OUT" >"$T/live-body.txt"
chk L1 "one code path: live output and fixture-mode output over the fetched directory agree outside the header" same "$T/fix-mode-body.txt" "$T/live-body.txt"

# L1b: fixture mode never needs gh
: >"$SHIM_LOG"
env PATH="$T/bin:$PATH" SHIM_LOG="$SHIM_LOG" bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR"; RC=$?
chk L1 "fixture mode issues no gh call (exit $RC, calls: $(wc -l <"$SHIM_LOG"))" rc_is 0
chk L1 "fixture mode leaves the gh shim log empty" [ ! -s "$SHIM_LOG" ]
env GITHUB_ACTIONS=true bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR"; RC=$?
chk L1 "fixture mode still works under GITHUB_ACTIONS=true (this suite runs in CI): exit $RC" rc_is 0

# L2: a failure on run k exits 2 naming k, after two retries
LIVE_FAIL_RUN=105 run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "jobs call failing for run 105: exit 2 exactly (got $RC)" rc_is 2
chk L2 "stderr names run 105" grep -q -- '105' "$ERR"
chk L2 "the failed call was retried twice (3 attempts, got $(shim_count 'JOBS 105'))" [ "$(shim_count 'JOBS 105')" -eq 3 ]
chk_not L2 "no total after a failed fetch" has TOTAL_JOB_MINUTES "$OUT"
# a runs call failing in the SECOND sub-window
LIVE_EXTRA="SHIM_FAIL_RUNS=created=2026-10-07T14:00:00Z" run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "a runs call failing in window 2: exit 2 exactly (got $RC)" rc_is 2
chk L2 "a runs call failing in window 2: stderr names that window" has "2026-10-07T14:00:00Z..2026-10-07T14:59:59Z" "$ERR"
chk L2 "a runs call failing in window 2 was attempted 3 times" [ "$(grep -c '^RUNS .*created=2026-10-07T14:00:00Z' "$SHIM_LOG")" -eq 3 ]
chk L2 "a runs call failing in window 2: no jobs call was made" [ "$(shim_count 'JOBS')" -eq 0 ]
chk_not L2 "a runs call failing in window 2: no total" has TOTAL_JOB_MINUTES "$OUT"
# gh writes page one of a jobs listing and then exits 1: the partial output is never accepted
LIVE_EXTRA="SHIM_PARTIAL_RUN=101" run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "partial page then exit 1: exit 2 exactly (got $RC)" rc_is 2
chk L2 "partial page then exit 1: stderr names run 101" has 101 "$ERR"
chk L2 "partial page then exit 1: retried to 3 attempts" [ "$(shim_count 'JOBS 101')" -eq 3 ]
chk_not L2 "partial page then exit 1: no total from the partial output" has TOTAL_JOB_MINUTES "$OUT"
# rate limit text is surfaced
LIVE_EXTRA="SHIM_RATELIMIT_RUN=105" run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "a rate-limited call: exit 2 exactly (got $RC)" rc_is 2
chk L2 "a rate-limited call: the abort message mentions the rate limit" hasi "rate limit" "$ERR"
# a hung call is killed by the timeout and counted as a failure
SECONDS=0
LIVE_EXTRA="SHIM_HANG_RUN=105 CENSUS_GH_TIMEOUT=1" run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "a hung call: exit 2 exactly (got $RC)" rc_is 2
chk L2 "a hung call: the abort message says it timed out" hasi "timed out" "$ERR"
chk L2 "a hung call: 3 attempts, each killed by the timeout" [ "$(shim_count 'JOBS 105')" -eq 3 ]
chk L2 "a hung call: the timeouts were not waited out (took ${SECONDS}s, each hang is 5 s)" [ "$SECONDS" -lt 14 ]
# the retry sleeps are linear by attempt, default 10 s
LIVE_PATH_PRE="$T/sbin" LIVE_RETRY_SLEEP="" LIVE_FAIL_RUN=105 run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "default retry sleeps are 10 s then 20 s" [ "$(grep '^SLEEP' "$SHIM_LOG" | paste -sd' ' -)" = "SLEEP 10 SLEEP 20" ]
LIVE_PATH_PRE="$T/sbin" LIVE_RETRY_SLEEP=7 LIVE_FAIL_RUN=105 run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L2 "CENSUS_RETRY_SLEEP=7 gives sleeps of 7 s then 14 s (linear by attempt)" [ "$(grep '^SLEEP' "$SHIM_LOG" | paste -sd' ' -)" = "SLEEP 7 SLEEP 14" ]

# L3: C1 fires before any jobs call
new_mutant; jq_edit "$d/runs-2.json" '.total_count = 5'
landing L3 "runs-2 total_count raised" "$d"
run_live "$d" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L3 "C1 failure in the second sub-window: exit 3 exactly (got $RC)" rc_is 3
chk L3 "C1 failure names the reason" has 'C1' "$ERR"
chk L3 "C1 failure made zero jobs calls (got $(shim_count 'JOBS'))" [ "$(shim_count 'JOBS')" -eq 0 ]
chk_not L3 "C1 failure prints no total" has TOTAL_JOB_MINUTES "$OUT"
new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs |= map(if .id == 108 then .created_at = "2026-10-07T13:30:00Z" else . end)'
landing L3 "run 108 created in window 1 but served for window 2" "$d"
run_live "$d" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L3 "a run created outside its sub-window: exit 3 exactly (got $RC)" rc_is 3
chk L3 "a run created outside its sub-window: stderr says so" has "outside" "$ERR"
chk L3 "a run created outside its sub-window: zero jobs calls" [ "$(shim_count 'JOBS')" -eq 0 ]

# L4: validation refusals exit 2 with not one gh call
expect_refusal() { # <label> <args...>
  local label="$1"; shift
  run_live "$FIXTURE" "$@"
  chk L4 "$label: exit 2 exactly (got $RC)" rc_is 2
  chk L4 "$label: no gh call made" [ ! -s "$SHIM_LOG" ]
  chk_not L4 "$label: no total" has TOTAL_JOB_MINUTES "$OUT"
}
# a future end that is inside the 12h span cap, so only the future check can refuse it
expect_refusal "future --end" --start "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" --end "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" --summary
expect_refusal "UTC offset instead of Z" --start 2026-10-07T13:00:00+02:00 --end "$LIVE_END" --summary
expect_refusal "malformed timestamp" --start 2026-10-07 --end "$LIVE_END" --summary
expect_refusal "impossible calendar date" --start 2026-13-45T13:00:00Z --end "$LIVE_END" --summary
expect_refusal "window longer than 12 hours" --start 2026-09-01T00:00:00Z --end 2026-10-07T00:00:00Z --summary
expect_refusal "window of 12 hours plus one second" --start 2026-10-07T03:00:00Z --end 2026-10-07T15:00:01Z --summary
chk L4 "the 12-hour refusal names the 12-hour limit" has "12 hours" "$ERR"
expect_refusal "start not before end" --start "$LIVE_END" --end "$LIVE_START" --summary
expect_refusal "start equal to end" --start "$LIVE_START" --end "$LIVE_START" --summary
expect_refusal "missing --end" --start "$LIVE_START" --summary
expect_refusal "unknown flag" --start "$LIVE_START" --end "$LIVE_END" --force
expect_refusal "no mode at all" --summary
expect_refusal "fixture mode combined with a window" --fixture "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END"
expect_refusal "malformed --workflow" --start "$LIVE_START" --end "$LIVE_END" --workflow 'a b;c'
LIVE_GH_REPO='not a/repo;rm' expect_refusal "malformed GH_REPO" --start "$LIVE_START" --end "$LIVE_END" --summary
for _bad in '../repo' 'owner/..' './.' '../..'; do
  LIVE_GH_REPO="$_bad" expect_refusal "GH_REPO made of dots ($_bad)" --start "$LIVE_START" --end "$LIVE_END" --summary
done
LIVE_EXTRA="CENSUS_SUBWINDOW_S=30" expect_refusal "CENSUS_SUBWINDOW_S below 60" --start "$LIVE_START" --end "$LIVE_END" --summary
LIVE_EXTRA="CENSUS_SUBWINDOW_S=1h" expect_refusal "CENSUS_SUBWINDOW_S not a number" --start "$LIVE_START" --end "$LIVE_END" --summary
LIVE_EXTRA="CENSUS_GH_TIMEOUT=0" expect_refusal "CENSUS_GH_TIMEOUT of 0" --start "$LIVE_START" --end "$LIVE_END" --summary
LIVE_RETRY_SLEEP="ten" expect_refusal "CENSUS_RETRY_SLEEP not a number" --start "$LIVE_START" --end "$LIVE_END" --summary

# L5: a non-numeric run id never builds a URL
new_mutant; jq_edit "$d/runs-1.json" '.workflow_runs |= map(if .id == 104 then .id = "104x" else . end)'
landing L5 "run 104 renamed to a non-numeric id" "$d"
run_live "$d" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L5 "non-numeric run id: exit 2 exactly (got $RC)" rc_is 2
chk L5 "non-numeric run id: no jobs call made" [ "$(shim_count 'JOBS')" -eq 0 ]
chk L5 "non-numeric run id: stderr says run id" hasi 'run id' "$ERR"

# L6: live mode refuses CI; GH_REPO unset falls back to gh repo view
: >"$SHIM_LOG"
env PATH="$T/bin:$PATH" SHIM_FIXTURE="$FIXTURE" SHIM_LOG="$SHIM_LOG" SHIM_REPO="$LIVE_REPO" GH_REPO="$LIVE_REPO" \
  GITHUB_ACTIONS=true CENSUS_RETRY_SLEEP=0 TMPDIR="$T/live" bash "$CENSUS" --start "$LIVE_START" --end "$LIVE_END" --summary >"$OUT" 2>"$ERR"; RC=$?
chk L6 "GITHUB_ACTIONS=true: live mode exits 2 exactly (got $RC)" rc_is 2
chk L6 "GITHUB_ACTIONS=true: no gh call made" [ ! -s "$SHIM_LOG" ]
LIVE_GH_REPO='' run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
chk L6 "GH_REPO empty: the repo comes from gh repo view (exit $RC)" rc_is 0
chk L6 "GH_REPO empty: gh repo view was called exactly once" [ "$(shim_count REPOVIEW)" -eq 1 ]
chk L6 "GH_REPO empty: the header carries the resolved repository" hasx "REPO=$LIVE_REPO" "$OUT"

# L7: the sub-window arithmetic, endpoint by endpoint (empty listings: the run ends at non-vacuity, exit 3)
LIVE_EXTRA="SHIM_EMPTY_RUNS=1" run_live "$FIXTURE" --start 2026-10-07T13:00:00Z --end 2026-10-07T14:30:00Z --summary
chk L7 "a half-hour end: exit 3 (nothing to count, got $RC)" rc_is 3
chk L7 "a half-hour end: the last sub-window ends one second before the exclusive end" \
  [ "$(runs_endpoints)" = "2026-10-07T13:00:00Z..2026-10-07T13:59:59Z 2026-10-07T14:00:00Z..2026-10-07T14:29:59Z" ]
LIVE_EXTRA="SHIM_EMPTY_RUNS=1" run_live "$FIXTURE" --start 2026-10-07T09:00:00Z --end 2026-10-07T15:00:00Z --summary
chk L7 "a 6 h span makes exactly 6 runs calls, not 7 (got $(shim_count RUNS))" [ "$(shim_count RUNS)" -eq 6 ]
chk L7 "a 6 h span: the exact endpoint list" \
  [ "$(runs_endpoints)" = "2026-10-07T09:00:00Z..2026-10-07T09:59:59Z 2026-10-07T10:00:00Z..2026-10-07T10:59:59Z 2026-10-07T11:00:00Z..2026-10-07T11:59:59Z 2026-10-07T12:00:00Z..2026-10-07T12:59:59Z 2026-10-07T13:00:00Z..2026-10-07T13:59:59Z 2026-10-07T14:00:00Z..2026-10-07T14:59:59Z" ]
LIVE_EXTRA="SHIM_EMPTY_RUNS=1" run_live "$FIXTURE" --start 2026-10-07T03:00:00Z --end 2026-10-07T15:00:00Z --summary
chk L7 "a window of exactly 12 hours (43200 s) is accepted: 12 runs calls (got $(shim_count RUNS))" [ "$(shim_count RUNS)" -eq 12 ]
chk L7 "a window of exactly 12 hours is not refused (exit 3, not 2; got $RC)" rc_is 3
LIVE_EXTRA="SHIM_EMPTY_RUNS=1" run_live "$FIXTURE" --start 2026-10-07T13:00:00Z --end 2026-10-07T13:00:01Z --summary
chk L7 "a one-second window asks for exactly that second" [ "$(runs_endpoints)" = "2026-10-07T13:00:00Z..2026-10-07T13:00:00Z" ]
LIVE_EXTRA="SHIM_EMPTY_RUNS=1 CENSUS_SUBWINDOW_S=1800" run_live "$FIXTURE" --start 2026-10-07T13:00:00Z --end 2026-10-07T14:00:00Z --summary
chk L7 "CENSUS_SUBWINDOW_S=1800 halves the sub-windows" \
  [ "$(runs_endpoints)" = "2026-10-07T13:00:00Z..2026-10-07T13:29:59Z 2026-10-07T13:30:00Z..2026-10-07T13:59:59Z" ]
LIVE_EXTRA="SHIM_EMPTY_RUNS=1" run_live "$FIXTURE" --start 2026-10-07T13:00:00Z --end 2026-10-07T14:00:00Z --summary
chk L7 "two adjacent censuses share no edge: [13:00, 14:00) ends at 13:59:59" [ "$(runs_endpoints)" = "2026-10-07T13:00:00Z..2026-10-07T13:59:59Z" ]

# L8: --workflow in live mode fetches jobs for that workflow's completed runs only
run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --workflow secret-scan.yml --summary
chk L8 "live --workflow secret-scan.yml exits 0 (got $RC)" rc_is 0
chk L8 "live --workflow: jobs fetched for the 3 completed secret-scan.yml runs only" [ "$(jobs_called)" = "104 105 111" ]
chk L8 "live --workflow: WORKFLOW_FILTER is in the header" hasx "WORKFLOW_FILTER=secret-scan.yml" "$OUT"
chk L8 "live --workflow: the total is that workflow's" hasx "TOTAL_JOB_SECONDS=$S_SS_PR" "$OUT"
chk L8 "live --workflow: both sub-window listings were still fetched (C1 over every run)" [ "$(shim_count RUNS)" -eq 2 ]
run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --workflow does-not-exist.yml --summary
chk L8 "live --workflow of an unknown file: exit 3 exactly (got $RC)" rc_is 3
chk L8 "live --workflow of an unknown file: zero jobs calls" [ "$(shim_count JOBS)" -eq 0 ]

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): the floor compares a literal and exits directly, so
# deleting assertions above reddens the run instead of shrinking both sides of an equality.
# Set to the FULL measured count, not a slack figure: headroom is deletable-assertion budget.
# KEEP THE TWO ASSIGNMENTS AND THE `if` CONTIGUOUS (no comment between them).
_total=$((passes + fails))
_FLOOR=497
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d - the suite lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'ci-demand-census: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'ci-demand-census: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
exit $(( ${#FAILURES[@]} > 0 ))
