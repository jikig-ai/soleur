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
#   H1     the same row function is run against a stub that prints the golden
#          total; rows 1-4 must go RED against it.
#   H2     the assertion floor at the bottom, written in the guard-vacuity-floor
#          shape (literal bound, direct printf + exit 1).
#   Live layer  a `gh` shim serving the committed fixture per exact endpoint
#          (whitelisted flags, every call logged) drives live mode: the fetched
#          directory round-trips to the same golden, a failure on run k exits 2
#          naming k after two retries, C1 fires before any jobs call, and every
#          validation refusal exits 2 without a single gh call.
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

# Instrument self-test: BEFORE any real row, drive both helpers and the dispatcher once
# and require each counter to move. Reported by a direct printf + exit 1, never through
# the helpers it checks (a neutered pass()/fail() must not be able to silence it).
_self=$( ( passes=0; fails=0; FAILURES=(); SINK=main
  pass; fail "self-test" 2>/dev/null; verdict selftest ok 0; verdict selftest bad 1 2>/dev/null
  printf '%s %s %s' "$passes" "$fails" "${#FAILURES[@]}" ) )
if [ "$_self" != "2 2 2" ]; then
  printf 'FAIL INSTRUMENT: pass()/fail()/verdict() self-test read "%s", expected "2 2 2"\n' "$_self" >&2
  exit 1
fi

for _tool in jq awk diff cmp cksum; do
  command -v "$_tool" >/dev/null 2>&1 || { printf 'FAIL: required tool missing: %s\n' "$_tool" >&2; exit 2; }
done

T=$(mktemp -d "${TMPDIR}/ci-demand-census-test.XXXXXXXX") || {
  printf 'FAIL: mktemp -d failed\n' >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/mut" "$T/bin" "$T/live"

OUT="$T/out.txt"
ERR="$T/err.txt"
RC=0

# run_census <script> <args...>: fixture-mode style invocation (no env tricks)
run_census() {
  local s="$1"; shift
  bash "$s" "$@" >"$OUT" 2>"$ERR"; RC=$?
}

# ── independent arithmetic: integer seconds per fixture job, written out by hand ──
# (see scripts/fixtures/ci-demand-census/basic; the clause jobs are NOT summed here)
S_CI_PR=$((600 + 300 + 1200 + 150 + 90))
S_CI_MG=$((480 + 840))
S_CI_PUSH=$((360 + 720))
S_SS_PR=$(( (10 + 20 + 24 + 18 + 100) + (12 + 110) + 90 ))
S_DYN=$((300 + 200 + 330))
S_NIGHT=$((150 + 50))
S_TOTAL=$((S_CI_PR + S_CI_MG + S_CI_PUSH + S_SS_PR + S_DYN + S_NIGHT))
# minutes (or minutes per run) from integer seconds: <secs> <decimals> [runs]
fmt() { awk -v s="$1" -v d="$2" -v n="${3:-1}" 'BEGIN { printf "%.*f", d, s / 60 / n }'; }

TAB=$(printf '\t')
ESC=$(printf '\033')

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
  local rows=(
    "ci.yml|merge_group|e2e|0|0|1|0|0|1"
    "ci.yml|merge_group|lint|0|1|0|0|0|1"
    "ci.yml|merge_group|synthetic-skipped-with-runner|0|1|0|0|0|1"
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
{ want_by_workflow; want_stem; } >"$T/want-tables.txt"

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
# caught <row> <label> <dir> <keyword>: the mutant must exit 3 exactly, name its reason, print no total
caught() {
  local row="$1" label="$2" dir="$3" kw="$4" rc_ok=1 kw_ok=1 tot_ok=1
  run_census "$CUR_S" --fixture "$dir" --summary
  [ "$RC" -eq 3 ] && rc_ok=0
  grep -qiF -- "$kw" "$ERR" && kw_ok=0
  grep -q 'TOTAL_JOB_MINUTES' "$OUT" || tot_ok=0
  verdict "$row" "$label: exit 3 exactly (got $RC)" "$rc_ok"
  verdict "$row" "$label: stderr names the reason '$kw'" "$kw_ok"
  verdict "$row" "$label: no TOTAL_JOB_MINUTES line" "$tot_ok"
}
landing() { # <row> <label> <dir>
  local rc=1; landed "$3" && rc=0
  verdict "$1" "$2: mutation landed (bytes differ from the committed fixture)" "$rc"
}

# ─────────────────────────────────────────────────────────────────────────────
# rows <script>: rows 1-5, parameterised on the script under test so H1 can reuse them
# ─────────────────────────────────────────────────────────────────────────────
rows() {
  local S="$1" d id rc
  CUR_S="$1"

  # ---- Row 5: goldens over the committed fixture (the classification predicate) ----
  run_census "$S" --fixture "$FIXTURE" --summary
  verdict 5 "fixture run exits 0 (got $RC)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
  verdict 5 "TOTAL_JOB_MINUTES equals the hand-computed golden ($WANT_TOTAL)" \
    "$(grep -Fxq -- "$WANT_TOTAL" "$OUT" && echo 0 || echo 1)"
  local nline; nline=$(grep -c '^TOTAL_JOB_MINUTES=' "$OUT")
  verdict 5 "exactly one TOTAL_JOB_MINUTES line (got $nline)" "$([ "$nline" -eq 1 ] && echo 0 || echo 1)"
  local k
  for k in RUNS_COMPLETED=10 RUNS_NOT_COMPLETED=1 JOBS_COUNTED=22 JOBS_SKIPPED=4 JOBS_RUNNERLESS=4 JOBS_UNTIMED=2; do
    verdict 5 "key line $k" "$(grep -Fxq -- "$k" "$OUT" && echo 0 || echo 1)"
  done
  local c s r u sum
  c=$(sed -n 's/^JOBS_COUNTED=//p' "$OUT"); s=$(sed -n 's/^JOBS_SKIPPED=//p' "$OUT")
  r=$(sed -n 's/^JOBS_RUNNERLESS=//p' "$OUT"); u=$(sed -n 's/^JOBS_UNTIMED=//p' "$OUT")
  sum=$(( ${c:-0} + ${s:-0} + ${r:-0} + ${u:-0} ))
  verdict 5 "partition: counted+skipped+runnerless+untimed ($sum) = jobs of completed runs ($FIX_JOBS_TOTAL)" \
    "$([ "$sum" -eq "$FIX_JOBS_TOTAL" ] && echo 0 || echo 1)"
  grep -E "^(BY_WORKFLOW|STEM)${TAB}" "$OUT" >"$T/got-tables.txt" || true
  verdict 5 "BY_WORKFLOW and STEM tables equal the hand-computed tables (two-document jobs file, @ref path, dynamic runs on one path, nested parenthesis, stem in two workflows)" \
    "$(diff -q "$T/want-tables.txt" "$T/got-tables.txt" >/dev/null 2>&1 && echo 0 || echo 1)"
  local stray; stray=$(grep -cvE "^(REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT|TOTAL_JOB_MINUTES|RUNS_COMPLETED|RUNS_NOT_COMPLETED|JOBS_COUNTED|JOBS_SKIPPED|JOBS_RUNNERLESS|JOBS_UNTIMED)=|^(BY_WORKFLOW|STEM)${TAB}" "$OUT")
  verdict 5 "output carries only KEY= lines and the two tables (stray lines: $stray)" "$([ "$stray" -eq 0 ] && echo 0 || echo 1)"
  verdict 5 "in-flight run produces a lower-bound WARN on stderr" "$(grep -q 'WARN' "$ERR" && echo 0 || echo 1)"
  cp "$OUT" "$T/first-$SINK.txt"
  run_census "$S" --fixture "$FIXTURE"
  verdict 5 "--summary is the explicit selector: same output without it, and the run is deterministic" \
    "$(cmp -s "$T/first-$SINK.txt" "$OUT" && echo 0 || echo 1)"

  # ---- Row 1: C2 existence ----
  for id in 101 104 111; do          # first, middle, last completed run
    new_mutant; rm -f "$d/jobs-$id.json"
    landing 1 "delete jobs-$id" "$d"
    caught 1 "missing jobs file of run $id" "$d" "C2"
    verdict 1 "missing jobs file of run $id: message names $id" "$(grep -q -- "$id" "$ERR" && echo 0 || echo 1)"
  done
  new_mutant; rm -f "$d/jobs-102.json" "$d/jobs-111.json"   # two runs after a compliant first
  landing 1 "delete jobs-102 and jobs-111" "$d"
  caught 1 "two missing jobs files after a compliant first" "$d" "C2"
  rc=0; { grep -q -- 102 "$ERR" && grep -q -- 111 "$ERR"; } || rc=1
  verdict 1 "two missing jobs files: the message names every missing run, not only the first" "$rc"
  new_mutant; rm -f "$d/jobs-108.json"                        # the run whose jobs total_count is 0 still needs its file
  landing 1 "delete jobs-108" "$d"
  caught 1 "completed run with total_count 0 and no jobs file" "$d" "C2"
  new_mutant; rm -f "$d/jobs-109.json"                        # in-flight run: its (decoy) file is not needed
  run_census "$S" --fixture "$d" --summary
  verdict 1 "removing the in-progress run's decoy jobs file is harmless: exit 0 and the golden total" \
    "$([ "$RC" -eq 0 ] && grep -Fxq -- "$WANT_TOTAL" "$OUT" && echo 0 || echo 1)"

  # ---- Row 2: C2 truncation (a job removed, total_count kept) ----
  new_mutant; jq_edit "$d/jobs-102.json" '.jobs |= .[1:]'
  landing 2 "drop a job from jobs-102" "$d"
  caught 2 "jobs-102 truncated" "$d" "truncat"
  new_mutant   # the two-document file: drop one job on page two only
  jq_edit "$d/jobs-101.json" 'if (.jobs | length) == 2 then .jobs |= .[1:] else . end'
  landing 2 "drop a job from page two of jobs-101" "$d"
  caught 2 "page two of the two-document jobs-101 truncated" "$d" "truncat"

  # ---- Row 3: C1 against the listing's own total_count ----
  new_mutant; jq_edit "$d/runs-1.json" '.total_count = 1000'
  landing 3 "runs-1 total_count raised to the 1000-result cap" "$d"
  caught 3 "listing at the 1000-result cap" "$d" "C1"
  rc=0; grep -qiF -- 'narrow' "$ERR" || rc=1
  verdict 3 "cap failure tells the operator to narrow the window" "$rc"
  new_mutant; jq_edit "$d/runs-2.json" '.total_count = 5'
  landing 3 "runs-2 total_count raised by one" "$d"
  caught 3 "one displaced run" "$d" "C1"
  new_mutant                                                       # exactly 1000 unique runs: consistent, but AT the cap
  jq -c -n '{total_count: 1000, workflow_runs: [range(2001; 3001) | {id: ., status: "queued", event: "push", path: ".github/workflows/x.yml"}]}' >"$d/runs-2.json"
  landing 3 "runs-2 replaced by a consistent listing of exactly 1000 queued runs" "$d"
  caught 3 "a sub-window at the 1000-result cap, even when consistent" "$d" "1000"
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs[3] = .workflow_runs[2]'
  landing 3 "run 111 replaced by a copy of run 110" "$d"
  caught 3 "duplicate run leaves the unique count one short" "$d" "C1"
  new_mutant; jq_edit "$d/runs-2.json" '.workflow_runs += [.workflow_runs[0]]'
  landing 3 "run 108 listed twice" "$d"
  run_census "$S" --fixture "$d" --summary
  verdict 3 "a pure duplicate (unique count equals total_count) is de-duplicated: exit 0 (got $RC)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
  verdict 3 "a pure duplicate leaves the golden total unchanged" "$(grep -Fxq -- "$WANT_TOTAL" "$OUT" && echo 0 || echo 1)"
  grep -E "^(BY_WORKFLOW|STEM)${TAB}" "$OUT" >"$T/got-tables.txt" || true
  verdict 3 "a pure duplicate leaves the tables unchanged" "$(diff -q "$T/want-tables.txt" "$T/got-tables.txt" >/dev/null 2>&1 && echo 0 || echo 1)"

  # ---- Row 4: non-vacuity, and unreadable input is exit 2 ----
  new_mutant
  printf '%s\n' '{"total_count":0,"workflow_runs":[]}' >"$d/runs-1.json"
  printf '%s\n' '{"total_count":0,"workflow_runs":[]}' >"$d/runs-2.json"
  landing 4 "both listings emptied" "$d"
  caught 4 "listing with total_count 0" "$d" "non-vacuity"
  verdict 4 "empty listing never prints TOTAL_JOB_MINUTES=0" "$(grep -q 'TOTAL_JOB_MINUTES=0' "$OUT" && echo 1 || echo 0)"
  new_mutant
  for id in 101 102 103 104 105 106 107 108 109 110 111; do jq_edit "$d/jobs-$id.json" '.jobs |= map(.conclusion = "skipped")'; done
  landing 4 "every job concluded skipped" "$d"
  caught 4 "a window whose every job is skipped" "$d" "non-vacuity"
  new_mutant; : >"$d/runs-1.json"
  landing 4 "zero-byte runs-1.json" "$d"
  run_census "$S" --fixture "$d" --summary
  verdict 4 "a zero-byte runs file is unreadable: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
  verdict 4 "a zero-byte runs file prints no total" "$(grep -q 'TOTAL_JOB_MINUTES' "$OUT" && echo 1 || echo 0)"
  new_mutant; printf '%s' '{not json' >"$d/runs-2.json"
  landing 4 "garbage runs-2.json" "$d"
  run_census "$S" --fixture "$d" --summary
  verdict 4 "invalid JSON in a runs file: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
  new_mutant; : >"$d/jobs-103.json"
  landing 4 "zero-byte jobs-103.json" "$d"
  run_census "$S" --fixture "$d" --summary
  verdict 4 "a zero-byte jobs file is unreadable: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
  d="$T/mut/empty-dir"; rm -rf "$d"; mkdir -p "$d"
  run_census "$S" --fixture "$d" --summary
  verdict 4 "a fixture directory with no runs file: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
  run_census "$S" --fixture "$T/mut/does-not-exist" --summary
  verdict 4 "a missing fixture directory: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN RUN: rows 1-5 against the real script
# ─────────────────────────────────────────────────────────────────────────────
FIX_SUM_BEFORE=$(find "$FIXTURE" -type f -exec cksum {} + 2>/dev/null | sort)
rows "$CENSUS"
FIX_SUM_AFTER=$(find "$FIXTURE" -type f -exec cksum {} + 2>/dev/null | sort)
verdict 0 "the committed fixture directory is byte-identical after every run (read-only, nothing written into the repo)" \
  "$([ -n "$FIX_SUM_BEFORE" ] && [ "$FIX_SUM_BEFORE" = "$FIX_SUM_AFTER" ] && echo 0 || echo 1)"

# the discoverability command from the plan, literally, from the repo root
DISC_OUT=$(cd "$REPO_ROOT" && bash scripts/ci-demand-census.sh --fixture scripts/fixtures/ci-demand-census/basic --summary 2>/dev/null)
verdict 0 "discoverability_test command prints a line starting TOTAL_JOB_MINUTES=" \
  "$(grep -q '^TOTAL_JOB_MINUTES=' <<<"$DISC_OUT" && echo 0 || echo 1)"

# ── header documents the definitions the parent plan deferred to this PR ──
HDR=$(sed -n '1,/^set -/p' "$CENSUS" 2>/dev/null || true)
for kw in "denominator" "lower bound" "closed window" "date -u" "1000" "sub-window" "attacker-chosen" "exit 3" "gh auth"; do
  verdict 0 "script header documents '$kw'" "$(grep -qiF -- "$kw" <<<"$HDR" && echo 0 || echo 1)"
done

# ── hostile names: one clean line, no ESC byte, no line starting with :: ──
new_mutant
HOSTILE_NAME=$(printf '::error::x\t\033[31mpwn (1/2)')
jq_edit "$d/jobs-104.json" '.jobs |= map(if .name == "gitleaks scan" then .name = $n else . end)' --arg n "$HOSTILE_NAME"
jq_edit "$d/runs-1.json" '.workflow_runs |= map(if (.id == 106 or .id == 107) then .path = $p else . end)' --arg p "$(printf 'dynamic/evil\n::error::y')"
landing 0 "hostile job name and workflow path" "$d"
run_census "$CENSUS" --fixture "$d" --summary
verdict 0 "hostile-name fixture still exits 0 (got $RC)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
verdict 0 "hostile names: no ESC byte reaches stdout" "$(grep -q "$ESC" "$OUT" && echo 1 || echo 0)"
verdict 0 "hostile names: no stdout line starts with ::" "$(grep -q '^::' "$OUT" && echo 1 || echo 0)"
verdict 0 "hostile names: every stdout line starts with a fixed token" \
  "$([ "$(grep -cvE "^(REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT|TOTAL_JOB_MINUTES|RUNS_COMPLETED|RUNS_NOT_COMPLETED|JOBS_COUNTED|JOBS_SKIPPED|JOBS_RUNNERLESS|JOBS_UNTIMED)=|^(BY_WORKFLOW|STEM)${TAB}" "$OUT")" -eq 0 ] && echo 0 || echo 1)"
verdict 0 "hostile names: the hostile stem is exactly one STEM line" \
  "$([ "$(grep -c "^STEM${TAB}secret-scan.yml${TAB}pull_request${TAB}::error::x" "$OUT")" -eq 1 ] && echo 0 || echo 1)"
verdict 0 "hostile names: STEM lines keep 10 tab fields and BY_WORKFLOW lines 6" \
  "$(awk -F'\t' '/^STEM\t/ && NF != 10 { bad = 1 } /^BY_WORKFLOW\t/ && NF != 6 { bad = 1 } END { exit bad }' "$OUT" && echo 0 || echo 1)"
verdict 0 "hostile names: exactly one extra line (the renamed stem splits out of 'gitleaks scan'), so no hostile text became extra lines" \
  "$([ "$(wc -l <"$OUT")" -eq $(( $(wc -l <"$T/first-main.txt") + 1 )) ] && echo 0 || echo 1)"

# ─────────────────────────────────────────────────────────────────────────────
# H1: the row function against a stub that prints the golden total. Rows 1-4 must go RED.
# ─────────────────────────────────────────────────────────────────────────────
STUB="$T/stub-census.sh"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s"\nexit 0\n' "$WANT_TOTAL" >"$STUB"
SINK=stub
rows "$STUB"
SINK=main
for _r in 1 2 3 4 5; do
  verdict H1 "stub printing only the golden total goes RED on row $_r (stub failures: ${STUB_FAILS[$_r]:-0})" \
    "$([ "${STUB_FAILS[$_r]:-0}" -gt 0 ] && echo 0 || echo 1)"
done
verdict H1 "the stub does pass the one assertion it can fake (the instrument distinguishes the verdicts, passes: ${STUB_PASSES[5]:-0})" \
  "$([ "${STUB_PASSES[5]:-0}" -gt 0 ] && echo 0 || echo 1)"

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
    if [ -f "$SHIM_FIXTURE/runs-$n.json" ]; then cat "$SHIM_FIXTURE/runs-$n.json"
    else printf '{"total_count":0,"workflow_runs":[]}\n'; fi ;;
  "repos/$SHIM_REPO/actions/runs/"*"/jobs?per_page=100&filter=latest")
    id=${ep#"repos/$SHIM_REPO/actions/runs/"}; id=${id%%/*}
    log "JOBS $id"
    [ "${SHIM_FAIL_RUN:-}" = "$id" ] && exit 1
    [ -f "$SHIM_FIXTURE/jobs-$id.json" ] || exit 1
    cat "$SHIM_FIXTURE/jobs-$id.json" ;;
  *) log "BAD endpoint $ep"; exit 64 ;;
esac
SHIM
chmod +x "$T/bin/gh"

LIVE_REPO=example-org/example-repo
LIVE_START=2026-10-07T13:00:00Z
LIVE_END=2026-10-07T14:59:59Z
SHIM_LOG="$T/shim.log"
# run_live <fixture-dir> <args...>: live mode through the shim. Sets RC OUT ERR; the shim log is reset per call.
run_live() {
  local fx="$1"; shift
  : >"$SHIM_LOG"
  env -u GITHUB_ACTIONS PATH="$T/bin:$PATH" SHIM_FIXTURE="$fx" SHIM_LOG="$SHIM_LOG" SHIM_REPO="$LIVE_REPO" \
    GH_REPO="${LIVE_GH_REPO-$LIVE_REPO}" CENSUS_RETRY_SLEEP=0 TMPDIR="$T/live" \
    SHIM_FAIL_RUN="${LIVE_FAIL_RUN:-}" bash "$CENSUS" "$@" >"$OUT" 2>"$ERR"; RC=$?
}
shim_count() { grep -c "^$1" "$SHIM_LOG" 2>/dev/null || true; }

# L1: round trip. The fetched directory must equal the committed fixture and give the same golden.
run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
verdict L1 "live mode through the shim exits 0 (got $RC)" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"
verdict L1 "live total equals the golden" "$(grep -Fxq -- "$WANT_TOTAL" "$OUT" && echo 0 || echo 1)"
grep -E "^(BY_WORKFLOW|STEM)${TAB}" "$OUT" >"$T/got-tables.txt" || true
verdict L1 "live tables equal the hand-computed tables" "$(diff -q "$T/want-tables.txt" "$T/got-tables.txt" >/dev/null 2>&1 && echo 0 || echo 1)"
verdict L1 "live header carries REPO, WINDOW_START, WINDOW_END and FETCHED_AT" \
  "$(grep -Fxq "REPO=$LIVE_REPO" "$OUT" && grep -Fxq "WINDOW_START=$LIVE_START" "$OUT" && grep -Fxq "WINDOW_END=$LIVE_END" "$OUT" && grep -q '^FETCHED_AT=' "$OUT" && echo 0 || echo 1)"
verdict L1 "two one-hour sub-windows partition the span exactly (second shifted by one second)" \
  "$([ "$(sed -n 's/^RUNS //p' "$SHIM_LOG" | paste -sd' ' -)" = "repos/$LIVE_REPO/actions/runs?created=2026-10-07T13:00:00Z..2026-10-07T13:59:59Z&per_page=100 repos/$LIVE_REPO/actions/runs?created=2026-10-07T14:00:00Z..2026-10-07T14:59:59Z&per_page=100" ] && echo 0 || echo 1)"
verdict L1 "jobs fetched for exactly the 10 completed runs (not the in-flight 109)" \
  "$([ "$(sed -n 's/^JOBS //p' "$SHIM_LOG" | sort -n | paste -sd' ' -)" = "101 102 103 104 105 106 107 108 110 111" ] && echo 0 || echo 1)"
verdict L1 "every runs-listing call precedes the first jobs call (C1 before any jobs call)" \
  "$([ "$(grep -n '^RUNS ' "$SHIM_LOG" | tail -1 | cut -d: -f1)" -lt "$(grep -n '^JOBS ' "$SHIM_LOG" | head -1 | cut -d: -f1)" ] && echo 0 || echo 1)"
verdict L1 "the shim saw no BAD call (only GETs, whitelisted flags, exact endpoints)" "$(grep -q '^BAD' "$SHIM_LOG" && echo 1 || echo 0)"
DATA_DIR=$(sed -n 's/^census: data dir: //p' "$ERR" | head -1)
verdict L1 "stderr names the fetched data directory under TMPDIR" "$([ -n "$DATA_DIR" ] && [ -d "$DATA_DIR" ] && case "$DATA_DIR" in "$T"/live/*) true ;; *) false ;; esac && echo 0 || echo 1)"
verdict L1 "last stderr line is the delete command for that directory" \
  "$([ "$(tail -1 "$ERR")" = "census: remove fetched data with: rm -rf $DATA_DIR" ] && echo 0 || echo 1)"
RT_OK=0
for f in runs-1 runs-2 jobs-101 jobs-102 jobs-103 jobs-104 jobs-105 jobs-106 jobs-107 jobs-108 jobs-110 jobs-111; do
  cmp -s "$FIXTURE/$f.json" "$DATA_DIR/$f.json" || RT_OK=1
done
verdict L1 "the fetched directory is byte-identical to the committed fixture layout (jobs-109 absent: in-flight)" \
  "$([ "$RT_OK" -eq 0 ] && [ ! -e "$DATA_DIR/jobs-109.json" ] && echo 0 || echo 1)"
run_census "$CENSUS" --fixture "$DATA_DIR" --summary
grep -v -E '^(REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT)=' "$OUT" >"$T/fix-mode-body.txt"
run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
grep -v -E '^(REPO|WINDOW|WINDOW_START|WINDOW_END|FETCHED_AT)=' "$OUT" >"$T/live-body.txt"
verdict L1 "one code path: live output and fixture-mode output over the fetched directory agree outside the header" \
  "$(cmp -s "$T/fix-mode-body.txt" "$T/live-body.txt" && echo 0 || echo 1)"

# L1b: fixture mode never needs gh
: >"$SHIM_LOG"
env PATH="$T/bin:$PATH" SHIM_LOG="$SHIM_LOG" bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR"; RC=$?
verdict L1 "fixture mode issues no gh call (exit $RC, calls: $(wc -l <"$SHIM_LOG"))" "$([ "$RC" -eq 0 ] && [ ! -s "$SHIM_LOG" ] && echo 0 || echo 1)"
env GITHUB_ACTIONS=true bash "$CENSUS" --fixture "$FIXTURE" --summary >"$OUT" 2>"$ERR"; RC=$?
verdict L1 "fixture mode still works under GITHUB_ACTIONS=true (this suite runs in CI): exit $RC" "$([ "$RC" -eq 0 ] && echo 0 || echo 1)"

# L2: a failure on run k exits 2 naming k, after two retries
LIVE_FAIL_RUN=105 run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
verdict L2 "jobs call failing for run 105: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
verdict L2 "stderr names run 105" "$(grep -q -- '105' "$ERR" && echo 0 || echo 1)"
verdict L2 "the failed call was retried twice (3 attempts, got $(shim_count 'JOBS 105'))" "$([ "$(shim_count 'JOBS 105')" -eq 3 ] && echo 0 || echo 1)"
verdict L2 "no total after a failed fetch" "$(grep -q 'TOTAL_JOB_MINUTES' "$OUT" && echo 1 || echo 0)"

# L3: C1 fires before any jobs call
new_mutant; jq_edit "$d/runs-2.json" '.total_count = 5'
landing L3 "runs-2 total_count raised" "$d"
run_live "$d" --start "$LIVE_START" --end "$LIVE_END" --summary
verdict L3 "C1 failure in the second sub-window: exit 3 exactly (got $RC)" "$([ "$RC" -eq 3 ] && echo 0 || echo 1)"
verdict L3 "C1 failure names the reason" "$(grep -qF 'C1' "$ERR" && echo 0 || echo 1)"
verdict L3 "C1 failure made zero jobs calls (got $(shim_count 'JOBS'))" "$([ "$(shim_count 'JOBS')" -eq 0 ] && echo 0 || echo 1)"
verdict L3 "C1 failure prints no total" "$(grep -q 'TOTAL_JOB_MINUTES' "$OUT" && echo 1 || echo 0)"

# L4: validation refusals exit 2 with not one gh call
expect_refusal() { # <label> <args...>
  local label="$1"; shift
  run_live "$FIXTURE" "$@"
  verdict L4 "$label: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
  verdict L4 "$label: no gh call made" "$([ ! -s "$SHIM_LOG" ] && echo 0 || echo 1)"
  verdict L4 "$label: no total" "$(grep -q 'TOTAL_JOB_MINUTES' "$OUT" && echo 1 || echo 0)"
}
# a future end that is inside the 48h span cap, so only the future check can refuse it
expect_refusal "future --end" --start "$(date -u -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" --end "$(date -u -d '+1 hour' +%Y-%m-%dT%H:%M:%SZ)" --summary
expect_refusal "UTC offset instead of Z" --start 2026-10-07T13:00:00+02:00 --end "$LIVE_END" --summary
expect_refusal "malformed timestamp" --start 2026-10-07 --end "$LIVE_END" --summary
expect_refusal "impossible calendar date" --start 2026-13-45T13:00:00Z --end "$LIVE_END" --summary
expect_refusal "window longer than 48 hours" --start 2026-09-01T00:00:00Z --end 2026-10-07T00:00:00Z --summary
expect_refusal "start not before end" --start "$LIVE_END" --end "$LIVE_START" --summary
expect_refusal "missing --end" --start "$LIVE_START" --summary
expect_refusal "unknown flag" --start "$LIVE_START" --end "$LIVE_END" --force
expect_refusal "no mode at all" --summary
expect_refusal "fixture mode combined with a window" --fixture "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END"
LIVE_GH_REPO='not a/repo;rm' expect_refusal "malformed GH_REPO" --start "$LIVE_START" --end "$LIVE_END" --summary

# L5: a non-numeric run id never builds a URL
new_mutant; jq_edit "$d/runs-1.json" '.workflow_runs |= map(if .id == 104 then .id = "104x" else . end)'
landing L5 "run 104 renamed to a non-numeric id" "$d"
run_live "$d" --start "$LIVE_START" --end "$LIVE_END" --summary
verdict L5 "non-numeric run id: exit 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
verdict L5 "non-numeric run id: no jobs call made" "$([ "$(shim_count 'JOBS')" -eq 0 ] && echo 0 || echo 1)"
verdict L5 "non-numeric run id: stderr says run id" "$(grep -qi 'run id' "$ERR" && echo 0 || echo 1)"

# L6: live mode refuses CI; GH_REPO unset falls back to gh repo view
: >"$SHIM_LOG"
env PATH="$T/bin:$PATH" SHIM_FIXTURE="$FIXTURE" SHIM_LOG="$SHIM_LOG" SHIM_REPO="$LIVE_REPO" GH_REPO="$LIVE_REPO" \
  GITHUB_ACTIONS=true CENSUS_RETRY_SLEEP=0 TMPDIR="$T/live" bash "$CENSUS" --start "$LIVE_START" --end "$LIVE_END" --summary >"$OUT" 2>"$ERR"; RC=$?
verdict L6 "GITHUB_ACTIONS=true: live mode exits 2 exactly (got $RC)" "$([ "$RC" -eq 2 ] && echo 0 || echo 1)"
verdict L6 "GITHUB_ACTIONS=true: no gh call made" "$([ ! -s "$SHIM_LOG" ] && echo 0 || echo 1)"
LIVE_GH_REPO='' run_live "$FIXTURE" --start "$LIVE_START" --end "$LIVE_END" --summary
verdict L6 "GH_REPO empty: the repo comes from gh repo view (exit $RC, repo-view calls $(shim_count REPOVIEW))" \
  "$([ "$RC" -eq 0 ] && [ "$(shim_count REPOVIEW)" -eq 1 ] && grep -Fxq "REPO=$LIVE_REPO" "$OUT" && echo 0 || echo 1)"

# ── static check: the floor below keeps the guard-vacuity-floor shape (three consecutive lines) ──
_shape=$(grep -n -A2 '^_total=\$((passes + fails))$' "${BASH_SOURCE[0]}" | grep -c -E '_FLOOR=[0-9]+$|if \[ "\$_total" -lt "\$_FLOOR" \]')
verdict 0 "the assertion floor is contiguous (_total=, _FLOOR=, if) so its mutant is constructible" "$([ "$_shape" -eq 2 ] && echo 0 || echo 1)"

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): the floor compares a literal and exits directly, so
# deleting assertions above reddens the run instead of shrinking both sides of an equality.
# Set to the FULL measured count, not a slack figure: headroom is deletable-assertion budget.
# KEEP THE TWO ASSIGNMENTS AND THE `if` CONTIGUOUS (no comment between them).
_total=$((passes + fails))
_FLOOR=175
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d - the suite lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'ci-demand-census: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'ci-demand-census: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
exit $(( ${#FAILURES[@]} > 0 ))
