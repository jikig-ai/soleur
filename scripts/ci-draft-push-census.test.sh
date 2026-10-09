#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Guard 3 for #9728 (S3 of the hosted-runner demand plan, ADR-276): the gate 6
# census instrument scripts/ci-draft-push-census.sh.
#
# PROPERTY. The census prints a verdict-bearing mean only if its population is
# complete and non-vacuous: every daily slice reconciles to the API total_count,
# the cohort is non-empty, unmapped runs and branch-name collisions are bounded,
# and the mean is computed over CLOSED draft windows that opened inside the
# period. Any shortfall exits 3 with no mean on stdout.
#
# WHAT THIS PROVES, AND HOW.
#   Row G   goldens: one hand-computed fixture (synthesized, no real PR data)
#           carries every window shape: draft at open then readied, opened ready
#           then converted twice, a bot PR with no CI, a still-open draft
#           (right-censored), a window opened before the period (clipped), a PR
#           closed while draft, a window closing after the period, a re-run of
#           one SHA, and a run on the ready run that must not count. Every figure
#           is written out here, not copied from the script.
#   Row V   the verdict table by integer cross-multiplication: 11 pushes over 4
#           PRs (exactly 2.75) passes, 10 over 4 (2.50) fails, a mean that passes
#           with a policy floor that does not is INDETERMINATE, never PASS.
#   Row M   mutation matrix: each mutant is a COPY of the fixture under mktemp, a
#           landing check proves the bytes changed, and a mutant counts as caught
#           ONLY on rc == 3 exactly plus a reason keyword on stderr and no mean on
#           stdout (an rc 2 crash or an rc 127 missing script never counts).
#   Row L   live layer: a `gh` shim serves the same fixture per exact endpoint
#           (whitelisted forms, every call logged), so the fetch + normalise path
#           round-trips to the same goldens; a live run refuses GITHUB_ACTIONS.
#   Self    every predicate helper is driven once with an input that MUST fail.
#   H       the golden rows are run against a stub that prints a constant mean;
#           they must go RED against it (a vacuous suite would not).
#   Floor   the assertion floor at the bottom, literal bound, direct printf + exit.
#
# This suite writes only under mktemp -d rooted at ${TMPDIR:-/var/tmp}.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

export LC_ALL=C
export TMPDIR="${TMPDIR:-/var/tmp}"

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CENSUS="$REPO_ROOT/scripts/ci-draft-push-census.sh"

passes=0
fails=0
# APPEND-ONLY FAILURE LEDGER: the exit status reads this array.
FAILURES=()
pass() { passes=$((passes + 1)); }
fail() { fails=$((fails + 1)); FAILURES+=("$1"); printf 'FAIL: %s\n' "$1" >&2; }

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

# Instrument self-test BEFORE any real row; reported by printf + exit 1, never
# through the helpers it checks.
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

for _tool in jq awk cmp timeout date; do
  command -v "$_tool" >/dev/null 2>&1 || { printf 'FAIL: required tool missing: %s\n' "$_tool" >&2; exit 2; }
done

T=$(mktemp -d "${TMPDIR}/ci-draft-push-census-test.XXXXXXXX") || {
  printf 'FAIL: mktemp -d failed\n' >&2; exit 2; }
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/mut" "$T/bin" "$T/ftmp" "$T/live"

OUT="$T/out.txt"
ERR="$T/err.txt"
RC=0

# Every census invocation goes through census_run: bounded by timeout (a looping
# mutant is a FAIL, not a hang); after the FIRST timeout every later run fails
# without running.
CENSUS_TO="${CENSUS_TEST_TIMEOUT:-60}"
DEADLINE_FILE="$T/deadline-hit"
census_run() {
  local rc
  if [ -e "$DEADLINE_FILE" ]; then return 124; fi
  timeout "$CENSUS_TO" env -u CENSUS_GH_TIMEOUT -u CENSUS_RETRY_SLEEP "$@"; rc=$?
  if [ "$rc" -eq 124 ]; then : >"$DEADLINE_FILE"; fi
  return "$rc"
}
run_census() { # <script> <args...>
  local s="$1"; shift
  census_run TMPDIR="$T/ftmp" bash "$s" "$@" >"$OUT" 2>"$ERR"; RC=$?
}

rc_is() { [ "$RC" -eq "$1" ]; }
has()   { grep -qF -- "$1" "$2"; }
hasx()  { grep -Fxq -- "$1" "$2"; }

# predicate self-controls: each must FAIL on an input that is wrong
: >"$T/empty.txt"
printf 'A=1\n' >"$T/one.txt"
RC=5
_ctl=$( (rc_is 6 && echo bad) || echo ok )
[ "$_ctl" = ok ] || { printf 'FAIL INSTRUMENT: rc_is accepted a wrong status\n' >&2; exit 1; }
_ctl=$( (has A=2 "$T/one.txt" && echo bad) || echo ok )
[ "$_ctl" = ok ] || { printf 'FAIL INSTRUMENT: has accepted an absent string\n' >&2; exit 1; }
_ctl=$( (hasx A "$T/one.txt" && echo bad) || echo ok )
[ "$_ctl" = ok ] || { printf 'FAIL INSTRUMENT: hasx accepted a partial line\n' >&2; exit 1; }
_ctl=$( (has A "$T/empty.txt" && echo bad) || echo ok )
[ "$_ctl" = ok ] || { printf 'FAIL INSTRUMENT: has accepted an empty file\n' >&2; exit 1; }

# ── fixture builders (synthesized; no real PR, branch or SHA data) ──────────
END_DAY=2026-01-04
DAYS_N=3
DAYS=(2026-01-01 2026-01-02 2026-01-03)

mk_runs() { # <dir>; stdin lines "id sha branch created conclusion" ('-' = null); writes runs-<day>.json per DAYS entry
  local d="$1" tsv day
  tsv=$(cat)
  mkdir -p "$d"
  for day in "${DAYS[@]}"; do
    printf '%s\n' "$tsv" | jq -R -s --arg day "$day" '
      [split("\n")[] | select(length > 0) | split(" ")
       | {id: (.[0] | tonumber), head_sha: .[1], head_branch: (if .[2] == "-" then null else .[2] end),
          created_at: .[3], event: "pull_request", run_attempt: 1,
          conclusion: (if .[4] == "-" then null else .[4] end), pull_requests: []}
       | select(.created_at[0:10] == $day)]
      | {total_count: length, workflow_runs: .}' >"$d/runs-$day.json"
  done
}

mk_base() { # <dir>: the golden fixture
  local d="$1"
  mkdir -p "$d"
  cat >"$d/prs.json" <<'JSON'
[
 {"number":101,"branch":"b101","createdAt":"2026-01-01T10:00:00Z","closedAt":null,"isDraft":false,"isBot":false,"timelineTotal":1,
  "events":[{"type":"ReadyForReviewEvent","at":"2026-01-02T12:00:00Z"}]},
 {"number":102,"branch":"b102","createdAt":"2026-01-01T11:00:00Z","closedAt":null,"isDraft":false,"isBot":false,"timelineTotal":4,
  "events":[{"type":"ConvertToDraftEvent","at":"2026-01-02T08:00:00Z"},{"type":"ReadyForReviewEvent","at":"2026-01-02T20:00:00Z"},
            {"type":"ConvertToDraftEvent","at":"2026-01-03T01:00:00Z"},{"type":"ReadyForReviewEvent","at":"2026-01-03T05:00:00Z"}]},
 {"number":103,"branch":"b103","createdAt":"2026-01-02T00:30:00Z","closedAt":null,"isDraft":false,"isBot":true,"timelineTotal":1,
  "events":[{"type":"ReadyForReviewEvent","at":"2026-01-02T06:00:00Z"}]},
 {"number":104,"branch":"b104","createdAt":"2026-01-02T13:00:00Z","closedAt":null,"isDraft":true,"isBot":false,"timelineTotal":0,"events":[]},
 {"number":105,"branch":"b105","createdAt":"2025-12-31T22:00:00Z","closedAt":null,"isDraft":false,"isBot":false,"timelineTotal":1,
  "events":[{"type":"ReadyForReviewEvent","at":"2026-01-01T09:00:00Z"}]},
 {"number":106,"branch":"b106","createdAt":"2026-01-01T05:00:00Z","closedAt":"2026-01-01T20:00:00Z","isDraft":true,"isBot":false,"timelineTotal":0,"events":[]},
 {"number":107,"branch":"b107","createdAt":"2026-01-03T20:00:00Z","closedAt":null,"isDraft":false,"isBot":false,"timelineTotal":1,
  "events":[{"type":"ReadyForReviewEvent","at":"2026-01-04T02:00:00Z"}]}
]
JSON
  mk_runs "$d" "${DAYS[@]}" <<'RUNS'
1 shaA b101 2026-01-01T10:00:05Z success
2 shaB b101 2026-01-01T15:00:00Z failure
3 shaB b101 2026-01-01T15:30:00Z success
4 shaC b101 2026-01-02T12:00:30Z success
5 shaD b102 2026-01-01T11:00:05Z success
6 shaE b102 2026-01-02T09:00:00Z success
7 shaF b102 2026-01-02T10:00:00Z success
8 shaG b102 2026-01-02T11:00:00Z success
9 shaH b102 2026-01-03T02:00:00Z success
10 shaI b104 2026-01-02T14:00:00Z success
11 shaJ b105 2026-01-01T08:00:00Z success
12 shaK b103 2026-01-02T07:00:00Z success
13 shaL b106 2026-01-01T06:00:00Z success
14 shaM b107 2026-01-03T21:00:00Z success
RUNS
}

mk_synth() { # <dir> "pushes:failed ..." : one draft-at-open PR per spec word, readied after the pushes
  local d="$1" spec="$2" i=0 w p f j rows=""
  mkdir -p "$d"
  : >"$d/prs.tmp"
  for w in $spec; do
    i=$((i + 1)); p=${w%%:*}; f=${w##*:}
    printf '{"number":%d,"branch":"s%d","createdAt":"2026-01-01T01:%02d:00Z","closedAt":null,"isDraft":false,"isBot":false,"timelineTotal":1,"events":[{"type":"ReadyForReviewEvent","at":"2026-01-02T12:00:00Z"}]}\n' \
      "$((200 + i))" "$i" "$i" >>"$d/prs.tmp"
    for ((j = 1; j <= p; j++)); do
      rows+="$((i * 100 + j)) s${i}x${j} s$i 2026-01-01T$(printf '%02d' $((i + 1))):$(printf '%02d' "$j"):00Z $([ "$j" -le "$f" ] && echo failure || echo success)"$'\n'
    done
  done
  jq -s '.' "$d/prs.tmp" >"$d/prs.json"; rm -f "$d/prs.tmp"
  printf '%s' "$rows" | mk_runs "$d" "${DAYS[@]}"
}

val() { grep -m1 "^$1=" "$OUT" | sed "s/^$1=//"; }   # value of a KEY=value line in the last stdout
nomean() { ! grep -q '^MEAN_PUSHES_DISTINCT_SHA=' "$OUT"; }

# ── Row G: goldens ───────────────────────────────────────────────────────────
BASE="$T/base"
mk_base "$BASE"
# hand-computed (see the header): cohort = 101 (2 pushes), 102 (4), 103 (0), 106 (1); 104 is a still-open draft,
# 105 opened its window before the period, 107 closes its window after the period.
rows_golden() { # <script>
  run_census "$1" --fixture "$BASE" --end "$END_DAY" --days "$DAYS_N"
  verdict G "base fixture exits 0 (got $RC)" "$([ "$RC" -eq 0 ]; echo $?)"
  verdict G "COHORT_PRS=4" "$(hasx COHORT_PRS=4 "$OUT"; echo $?)"
  verdict G "DRAFT_PUSHES=7 (distinct head SHAs: A,B,E,F,G,H,L)" "$(hasx DRAFT_PUSHES=7 "$OUT"; echo $?)"
  verdict G "DRAFT_RUNS=8 (the second run of one SHA counts as a run, not a push)" "$(hasx DRAFT_RUNS=8 "$OUT"; echo $?)"
  verdict G "MEAN_PUSHES_DISTINCT_SHA=1.75" "$(hasx MEAN_PUSHES_DISTINCT_SHA=1.75 "$OUT"; echo $?)"
  verdict G "MEAN_RUNS=2.00" "$(hasx MEAN_RUNS=2.00 "$OUT"; echo $?)"
  verdict G "MEDIAN=1.50" "$(hasx MEDIAN=1.50 "$OUT"; echo $?)"
  verdict G "FAILED_PUSHES=1" "$(hasx FAILED_PUSHES=1 "$OUT"; echo $?)"
  verdict G "FAILED_PUSH_SHARE=0.14" "$(hasx FAILED_PUSH_SHARE=0.14 "$OUT"; echo $?)"
  verdict G "POLICY_FLOOR_MEAN=1.50" "$(hasx POLICY_FLOOR_MEAN=1.50 "$OUT"; echo $?)"
  verdict G "READY_TRANSITIONS=5" "$(hasx READY_TRANSITIONS=5 "$OUT"; echo $?)"
  verdict G "BOT_READY_TRANSITIONS=1" "$(hasx BOT_READY_TRANSITIONS=1 "$OUT"; echo $?)"
  verdict G "UNMAPPED_RUNS=0" "$(hasx UNMAPPED_RUNS=0 "$OUT"; echo $?)"
  verdict G "EXCLUDED_BRANCH_COLLISIONS=0" "$(hasx EXCLUDED_BRANCH_COLLISIONS=0 "$OUT"; echo $?)"
  verdict G "SLICES_RECONCILED=3" "$(hasx SLICES_RECONCILED=3 "$OUT"; echo $?)"
  verdict G "VERDICT=FAIL (1.75 is below 2.75)" "$(hasx VERDICT=FAIL "$OUT"; echo $?)"
  verdict G "the policy-floor assumption is stated on the output" "$(grep -q '^POLICY_FLOOR_ASSUMPTION=' "$OUT"; echo $?)"
}
rows_golden "$CENSUS"

# split by PR creation date (thirds of the period): bucket 1 = 101,102,106 (7 pushes), bucket 2 = 103 (0), bucket 3 = none
run_census "$CENSUS" --fixture "$BASE" --end "$END_DAY" --days "$DAYS_N"
chk G "SPLIT bucket 1: 3 PRs, 7 pushes, mean 2.33" has "SPLIT	1	3	7	2.33" "$OUT"
chk G "SPLIT bucket 2: 1 PR, 0 pushes, mean 0.00" has "SPLIT	2	1	0	0.00" "$OUT"
chk G "SPLIT bucket 3: 0 PRs, 0 pushes" has "SPLIT	3	0	0	n/a" "$OUT"

# --rows writes one line per cohort PR: number, windows, pushes, runs, failed
run_census "$CENSUS" --fixture "$BASE" --end "$END_DAY" --days "$DAYS_N" --rows "$T/rows.tsv"
chk G "rows file has the 4 cohort PRs" bash -c '[ "$(wc -l <"$1")" -eq 4 ]' _ "$T/rows.tsv"
chk G "rows: PR 102 has 2 windows, 4 pushes, 4 runs, 0 failed" has "102	2	4	4	0" "$T/rows.tsv"
chk G "rows: PR 101 has 1 window, 2 pushes, 3 runs, 1 failed" has "101	1	2	3	1" "$T/rows.tsv"
chk_not G "rows: the still-open draft 104 is not in the cohort" grep -q '^104	' "$T/rows.tsv"

# ── Row V: the verdict table (integer cross-multiplication) ─────────────────
vcase() { # <name> <spec> <mean> <verdict>
  mk_synth "$T/v-$1" "$2"
  run_census "$CENSUS" --fixture "$T/v-$1" --end "$END_DAY" --days "$DAYS_N"
  verdict V "$1: exit 0 (got $RC)" "$([ "$RC" -eq 0 ]; echo $?)"
  verdict V "$1: MEAN_PUSHES_DISTINCT_SHA=$3" "$(hasx "MEAN_PUSHES_DISTINCT_SHA=$3" "$OUT"; echo $?)"
  verdict V "$1: VERDICT=$4" "$(hasx "VERDICT=$4" "$OUT"; echo $?)"
}
vcase boundary-2.75 "3:0 3:0 3:0 2:0" 2.75 PASS
vcase below-2.50 "3:0 3:0 2:0 2:0" 2.50 FAIL
vcase just-below "3:0 3:0 3:0 1:0 3:0 3:0 3:0 3:0 3:0 3:0 3:0 1:0" 2.67 FAIL
vcase floor-boundary "3:1 3:0 3:0 3:0" 3.00 PASS
vcase indeterminate "3:2 3:2 3:2 3:2" 3.00 INDETERMINATE
vcase floor-just-fails "3:2 3:0 3:0 3:0" 3.00 INDETERMINATE
# a cohort PR with zero pushes still counts in the denominator: 11 pushes over 5 PRs is 2.20
vcase zero-push-pr "3:0 3:0 3:0 2:0 0:0" 2.20 FAIL

# the LOWER of the two bases decides: 10 distinct SHAs plus one re-run of an existing SHA is 11 runs (2.75 on the run basis) and must still FAIL
mk_synth "$T/v-rerun" "3:0 3:0 2:0 2:0"
jq '.workflow_runs += [{"id":9100,"head_sha":"s1x1","head_branch":"s1","created_at":"2026-01-01T23:00:00Z","event":"pull_request","run_attempt":1,"conclusion":"success","pull_requests":[]}] | .total_count = (.workflow_runs | length)' \
  "$T/v-rerun/runs-2026-01-01.json" >"$T/v-rerun/runs.tmp" && mv "$T/v-rerun/runs.tmp" "$T/v-rerun/runs-2026-01-01.json"
run_census "$CENSUS" --fixture "$T/v-rerun" --end "$END_DAY" --days "$DAYS_N"
chk V "rerun: DRAFT_PUSHES=10 and DRAFT_RUNS=11" bash -c 'grep -qx DRAFT_PUSHES=10 "$1" && grep -qx DRAFT_RUNS=11 "$1"' _ "$OUT"
chk V "rerun: MEAN_RUNS=2.75 yet VERDICT=FAIL (the lower basis decides)" bash -c 'grep -qx MEAN_RUNS=2.75 "$1" && grep -qx VERDICT=FAIL "$1"' _ "$OUT"

# ── Row M: mutation matrix ──────────────────────────────────────────────────
landed() { ! cmp -s "$1" "$2"; }   # landed <pristine> <mutated>: the mutation changed bytes
refused() { # <row> <name> <stderr keyword>; the last run must be a refusal
  verdict "$1" "$2: rc 3 exactly (got $RC)" "$([ "$RC" -eq 3 ]; echo $?)"
  verdict "$1" "$2: stderr names the reason ($3)" "$(grep -qiF -- "$3" "$ERR"; echo $?)"
  verdict "$1" "$2: no mean on stdout" "$(nomean; echo $?)"
}

# M1 a truncated slice: total_count says more rows than the file holds
cp -r "$BASE" "$T/mut/m1"
jq '.total_count = 150' "$BASE/runs-2026-01-02.json" >"$T/mut/m1/runs-2026-01-02.json"
chk M1 "mutation landed" landed "$BASE/runs-2026-01-02.json" "$T/mut/m1/runs-2026-01-02.json"
run_census "$CENSUS" --fixture "$T/mut/m1" --end "$END_DAY" --days "$DAYS_N"
refused M1 "truncated slice" reconcile

# M1b a missing slice file
cp -r "$BASE" "$T/mut/m1b"; rm -f "$T/mut/m1b/runs-2026-01-03.json"
chk M1b "mutation landed" [ ! -e "$T/mut/m1b/runs-2026-01-03.json" ]
run_census "$CENSUS" --fixture "$T/mut/m1b" --end "$END_DAY" --days "$DAYS_N"
refused M1b "missing slice" slice

# M1c a slice holding a run from another day (a mis-sliced fetch)
cp -r "$BASE" "$T/mut/m1c"
jq '.workflow_runs[0].created_at = "2026-01-02T01:00:00Z"' "$BASE/runs-2026-01-01.json" >"$T/mut/m1c/runs-2026-01-01.json"
chk M1c "mutation landed" landed "$BASE/runs-2026-01-01.json" "$T/mut/m1c/runs-2026-01-01.json"
run_census "$CENSUS" --fixture "$T/mut/m1c" --end "$END_DAY" --days "$DAYS_N"
refused M1c "run outside its slice" slice

# M2 joining on pull_requests[] instead of head_branch: head_branch absent everywhere, pull_requests populated
cp -r "$BASE" "$T/mut/m2"
for _d in "${DAYS[@]}"; do
  jq '.workflow_runs |= map(.pull_requests = [{"number": 101}] | .head_branch = null)' "$BASE/runs-$_d.json" >"$T/mut/m2/runs-$_d.json"
done
chk M2 "mutation landed" landed "$BASE/runs-2026-01-01.json" "$T/mut/m2/runs-2026-01-01.json"
run_census "$CENSUS" --fixture "$T/mut/m2" --end "$END_DAY" --days "$DAYS_N"
refused M2 "unmapped runs" unmapped

# M2b one unmapped run in twenty is exactly 5 percent and allowed; two in twenty-one is refused
mk_synth "$T/mut/m2b" "5:0 5:0 5:0 4:0"
jq '.workflow_runs += [{"id":9001,"head_sha":"orph1","head_branch":"nobody","created_at":"2026-01-01T23:00:00Z","event":"pull_request","run_attempt":1,"conclusion":"success","pull_requests":[]}] | .total_count = (.workflow_runs | length)' \
  "$T/mut/m2b/runs-2026-01-01.json" >"$T/mut/m2b/runs.tmp" && mv "$T/mut/m2b/runs.tmp" "$T/mut/m2b/runs-2026-01-01.json"
run_census "$CENSUS" --fixture "$T/mut/m2b" --end "$END_DAY" --days "$DAYS_N"
chk M2b "1 unmapped in 20 runs (exactly 5%) is allowed (rc $RC)" rc_is 0
chk M2b "UNMAPPED_RUNS=1" hasx UNMAPPED_RUNS=1 "$OUT"
jq '.workflow_runs += [{"id":9002,"head_sha":"orph2","head_branch":"nobody2","created_at":"2026-01-01T23:30:00Z","event":"pull_request","run_attempt":1,"conclusion":"success","pull_requests":[]}] | .total_count = (.workflow_runs | length)' \
  "$T/mut/m2b/runs-2026-01-01.json" >"$T/mut/m2b/runs.tmp" && mv "$T/mut/m2b/runs.tmp" "$T/mut/m2b/runs-2026-01-01.json"
run_census "$CENSUS" --fixture "$T/mut/m2b" --end "$END_DAY" --days "$DAYS_N"
refused M2b "2 unmapped in 21 runs" unmapped

# M3 closed-cohort rule: the still-open draft 104, the window clipped at the start (105) and the window closing after the period (107) stay out
run_census "$CENSUS" --fixture "$BASE" --end "$END_DAY" --days "$DAYS_N" --rows "$T/rows.tsv"
chk_not M3 "open draft 104 is not in the cohort" grep -q '^104	' "$T/rows.tsv"
chk_not M3 "clipped window 105 is not in the cohort" grep -q '^105	' "$T/rows.tsv"
chk_not M3 "window 107 closing after the period is not in the cohort" grep -q '^107	' "$T/rows.tsv"
chk M3 "PR 106 closed while draft IS in the cohort" has "106	1	1	1	0" "$T/rows.tsv"

# M4 a draft PR's ready run is not a draft push: PR 101's SHA C (created after the ready event) stays out
chk M4 "PR 101 has 2 pushes, not 3" has "101	1	2	3	1" "$T/rows.tsv"

# M4b the window edges: a run created in the SAME SECOND as the ready event is the ready run (not a draft push);
# a run created in the same second as the window opens (the PR-open run) is a draft push
cp -r "$BASE" "$T/mut/m4b"
jq '.workflow_runs += [{"id":9200,"head_sha":"shaEdgeClose","head_branch":"b101","created_at":"2026-01-02T12:00:00Z","event":"pull_request","run_attempt":1,"conclusion":"success","pull_requests":[]}] | .total_count = (.workflow_runs | length)' \
  "$BASE/runs-2026-01-02.json" >"$T/mut/m4b/runs-2026-01-02.json"
jq '.workflow_runs += [{"id":9201,"head_sha":"shaEdgeOpen","head_branch":"b106","created_at":"2026-01-01T05:00:00Z","event":"pull_request","run_attempt":1,"conclusion":"success","pull_requests":[]}] | .total_count = (.workflow_runs | length)' \
  "$BASE/runs-2026-01-01.json" >"$T/mut/m4b/runs-2026-01-01.json"
chk M4b "mutation landed" landed "$BASE/runs-2026-01-02.json" "$T/mut/m4b/runs-2026-01-02.json"
run_census "$CENSUS" --fixture "$T/mut/m4b" --end "$END_DAY" --days "$DAYS_N" --rows "$T/rows4b.tsv"
chk M4b "PR 101 still has 2 pushes and 3 runs (the same-second ready run is not a draft push)" has "101	1	2	3	1" "$T/rows4b.tsv"
chk M4b "PR 106 gains the same-second window-open run: 2 pushes, 2 runs" has "106	1	2	2	0" "$T/rows4b.tsv"

# M5 an empty cohort is refused, never printed as MEAN 0
cp -r "$BASE" "$T/mut/m5"
jq 'map(.events = [] | .isDraft = false | .timelineTotal = 0)' "$BASE/prs.json" >"$T/mut/m5/prs.json"
chk M5 "mutation landed" landed "$BASE/prs.json" "$T/mut/m5/prs.json"
run_census "$CENSUS" --fixture "$T/mut/m5" --end "$END_DAY" --days "$DAYS_N"
refused M5 "empty cohort (no PR was ever a draft)" cohort
# an empty PR listing leaves every run unmapped: refused as well (the join is broken or the listing incomplete)
cp -r "$BASE" "$T/mut/m5b"; printf '[]\n' >"$T/mut/m5b/prs.json"
run_census "$CENSUS" --fixture "$T/mut/m5b" --end "$END_DAY" --days "$DAYS_N"
refused M5b "empty PR listing" unmapped

# M6 two PRs reusing one branch name: counted, excluded from the cohort
cp -r "$BASE" "$T/mut/m6"
jq 'map(if .number == 103 then .branch = "b102" else . end)' "$BASE/prs.json" >"$T/mut/m6/prs.json"
jq '.workflow_runs |= map(if .head_branch == "b103" then .head_branch = "b102" else . end)' "$BASE/runs-2026-01-02.json" >"$T/mut/m6/runs-2026-01-02.json"
chk M6 "mutation landed" landed "$BASE/prs.json" "$T/mut/m6/prs.json"
run_census "$CENSUS" --fixture "$T/mut/m6" --end "$END_DAY" --days "$DAYS_N" --rows "$T/rows6.tsv"
chk M6 "EXCLUDED_BRANCH_COLLISIONS=1" hasx EXCLUDED_BRANCH_COLLISIONS=1 "$OUT"
chk M6 "COHORT_PRS=2 (101 and 106; 102 and 103 share a branch)" hasx COHORT_PRS=2 "$OUT"
chk_not M6 "102 is not in the rows" grep -q '^102	' "$T/rows6.tsv"

# M7 a truncated timeline (more events than were fetched) is refused, not read short
cp -r "$BASE" "$T/mut/m7"
jq 'map(if .number == 102 then .timelineTotal = 130 else . end)' "$BASE/prs.json" >"$T/mut/m7/prs.json"
chk M7 "mutation landed" landed "$BASE/prs.json" "$T/mut/m7/prs.json"
run_census "$CENSUS" --fixture "$T/mut/m7" --end "$END_DAY" --days "$DAYS_N"
refused M7 "truncated timeline" timeline

# M8 a non-conforming timestamp is refused rather than compared as text
cp -r "$BASE" "$T/mut/m8"
jq 'map(if .number == 101 then .createdAt = "2026-01-01 10:00" else . end)' "$BASE/prs.json" >"$T/mut/m8/prs.json"
chk M8 "mutation landed" landed "$BASE/prs.json" "$T/mut/m8/prs.json"
run_census "$CENSUS" --fixture "$T/mut/m8" --end "$END_DAY" --days "$DAYS_N"
refused M8 "bad timestamp" timestamp

# M9 pagination: a slice stored as two pages reconciles against total_count and gives the same goldens
cp -r "$BASE" "$T/mut/m9"
jq -c '. as $s | {total_count: $s.total_count, workflow_runs: $s.workflow_runs[0:1]}, {total_count: $s.total_count, workflow_runs: $s.workflow_runs[1:]}' \
  "$BASE/runs-2026-01-01.json" >"$T/mut/m9/runs-2026-01-01.json"
chk M9 "mutation landed (two pages)" bash -c '[ "$(wc -l <"$1")" -eq 2 ]' _ "$T/mut/m9/runs-2026-01-01.json"
run_census "$CENSUS" --fixture "$T/mut/m9" --end "$END_DAY" --days "$DAYS_N"
chk M9 "paged slice: same mean as the single-page base" hasx MEAN_PUSHES_DISTINCT_SHA=1.75 "$OUT"
chk M9 "paged slice: SLICES_RECONCILED=3" hasx SLICES_RECONCILED=3 "$OUT"

# ── argument validation: every refusal exits 2 without touching the network ──
run_census "$CENSUS" --fixture "$BASE" --end "$END_DAY" --days 0
chk A "--days 0: rc 2" rc_is 2
run_census "$CENSUS" --fixture "$BASE" --end "not-a-date" --days "$DAYS_N"
chk A "bad --end: rc 2" rc_is 2
run_census "$CENSUS" --fixture "$BASE" --days "$DAYS_N"
chk A "missing --end: rc 2" rc_is 2
run_census "$CENSUS" --fixture "$T/does-not-exist" --end "$END_DAY" --days "$DAYS_N"
chk A "missing fixture dir: rc 2" rc_is 2
run_census "$CENSUS" --end "$(date -u -d '+2 days' +%F)" --days 3
chk A "an end day in the future is refused before any fetch (rc 2)" rc_is 2
run_census "$CENSUS" --help
chk A "--help: rc 0 and the usage names the output keys" rc_is 0
chk A "--help names VERDICT" has VERDICT "$OUT"

# ── Row L: live layer through a gh shim ─────────────────────────────────────
cat >"$T/bin/gh" <<'SHIM'
#!/usr/bin/env bash
# gh shim: serves $FIX per exact endpoint; every call is logged; anything else exits 64.
echo "gh $*" >>"$GH_LOG"
[ "${1:-}" = api ] || exit 64
shift
[ "${1:-}" != --paginate ] || shift
case "${1:-}" in
  graphql)
    shift
    q=""; cursor=""
    while [ $# -gt 0 ]; do
      case "$1" in
        -f) case "$2" in searchQuery=*) q="${2#searchQuery=}" ;; cursor=*) cursor="${2#cursor=}" ;; query=*) : ;; *) exit 64 ;; esac; shift 2 ;;
        *) exit 64 ;;
      esac
    done
    [ -z "$cursor" ] || exit 64   # one page per day in this fixture
    day=$(printf '%s' "$q" | sed -n 's/.*created:\([0-9-]*\)\.\..*/\1/p')
    [ -n "$day" ] || exit 64
    jq -c --arg day "$day" '
      {data: {search: {pageInfo: {hasNextPage: false, endCursor: null},
        nodes: [.[] | select(.createdAt[0:10] == $day)
          | {number, headRefName: .branch, createdAt, closedAt, isDraft,
             author: {__typename: (if .isBot then "Bot" else "User" end)},
             timelineItems: {pageInfo: {hasNextPage: (.timelineTotal > (.events | length))}, nodes: [.events[] | {__typename: .type, createdAt: .at}]}}]}}}' "$FIX/prs.json"
    ;;
  repos/*/actions/workflows/ci.yml/runs*)
    ep="$1"
    case "$ep" in *"event=pull_request"*"per_page=100"*) : ;; *) exit 64 ;; esac
    day=$(printf '%s' "$ep" | sed -n 's/.*created=\([0-9-]*\)T00:00:00Z\.\.[0-9-]*T23:59:59Z.*/\1/p')
    [ -n "$day" ] || exit 64
    [ "${GH_FAIL_DAY:-}" != "$day" ] || { echo "HTTP 500" >&2; exit 1; }
    cat "$FIX/runs-$day.json"
    ;;
  *) exit 64 ;;
esac
SHIM
chmod +x "$T/bin/gh"
GH_LOG="$T/gh.log"; : >"$GH_LOG"
live() { # <fixture dir> <args...>
  local fix="$1"; shift
  census_run PATH="$T/bin:$PATH" TMPDIR="$T/live" FIX="$fix" GH_LOG="$GH_LOG" CENSUS_RETRY_SLEEP=0 \
    bash "$CENSUS" --repo example/synthetic --end "$END_DAY" --days "$DAYS_N" "$@" >"$OUT" 2>"$ERR"; RC=$?
}
live "$BASE"
chk L "live mode on the shim: rc 0 (got $RC)" rc_is 0
chk L "live round trip gives the same mean" hasx MEAN_PUSHES_DISTINCT_SHA=1.75 "$OUT"
chk L "live round trip gives the same cohort" hasx COHORT_PRS=4 "$OUT"
chk L "live round trip gives the same verdict" hasx VERDICT=FAIL "$OUT"
chk L "live: 3 runs calls were made (one per day)" bash -c '[ "$(grep -c "actions/workflows/ci.yml/runs" "$1")" -eq 3 ]' _ "$GH_LOG"
chk L "live: runs are fetched with --paginate (every runs call carries it)" bash -c '[ "$(grep -c -- "--paginate repos/.*actions/workflows/ci.yml/runs" "$1")" -eq 3 ]' _ "$GH_LOG"
chk_not L "live: no pull_requests[] join, no POST/PATCH flag was ever sent" grep -qE -- ' (-X|--method) ' "$GH_LOG"
chk L "live: PRs are listed for the 14 days before the period too (17 graphql day calls)" bash -c '[ "$(grep -c "graphql" "$1")" -eq 17 ]' _ "$GH_LOG"
chk L "live: the fetched directory is kept and named on stderr" has "data dir:" "$ERR"

GH_LOG="$T/gh1b.log"; : >"$GH_LOG"
live "$T/mut/m7"
chk L "live: a timeline the API says has more pages is refused (rc 3, got $RC)" rc_is 3
chk L "live: the refusal names the truncated timeline" has timeline "$ERR"
chk_not L "live: no mean after the truncated-timeline refusal" has MEAN_PUSHES_DISTINCT_SHA "$OUT"

GH_LOG="$T/gh2.log"; : >"$GH_LOG"
census_run PATH="$T/bin:$PATH" TMPDIR="$T/live" FIX="$BASE" GH_LOG="$GH_LOG" GH_FAIL_DAY=2026-01-02 CENSUS_RETRY_SLEEP=0 \
  bash "$CENSUS" --repo example/synthetic --end "$END_DAY" --days "$DAYS_N" >"$OUT" 2>"$ERR"; RC=$?
chk L "a failing runs call exits 2 (got $RC)" rc_is 2
chk L "the abort names the day" has 2026-01-02 "$ERR"
chk_not L "no mean after a failed fetch" has MEAN_PUSHES_DISTINCT_SHA "$OUT"
chk L "the failed call was retried twice (3 attempts)" bash -c '[ "$(grep -c "created=2026-01-02" "$1")" -eq 3 ]' _ "$GH_LOG"

GH_LOG="$T/gh3.log"; : >"$GH_LOG"
census_run PATH="$T/bin:$PATH" TMPDIR="$T/live" FIX="$BASE" GH_LOG="$GH_LOG" GITHUB_ACTIONS=true \
  bash "$CENSUS" --repo example/synthetic --end "$END_DAY" --days "$DAYS_N" >"$OUT" 2>"$ERR"; RC=$?
chk L "live mode refuses GITHUB_ACTIONS=true (rc 2)" rc_is 2
chk L "the refusal makes no gh call" bash -c '[ ! -s "$1" ]' _ "$GH_LOG"
GH_LOG="$T/gh4.log"; : >"$GH_LOG"
census_run PATH="$T/bin:$PATH" TMPDIR="$T/live" FIX="$BASE" GH_LOG="$GH_LOG" GITHUB_ACTIONS=true \
  bash "$CENSUS" --fixture "$BASE" --end "$END_DAY" --days "$DAYS_N" >"$OUT" 2>"$ERR"; RC=$?
chk L "fixture mode is allowed under GITHUB_ACTIONS=true (rc 0)" rc_is 0

# ── Row H: the golden rows against a stub that prints a constant mean ───────
cat >"$T/stub.sh" <<'STUB'
#!/usr/bin/env bash
printf 'COHORT_PRS=4\nMEAN_PUSHES_DISTINCT_SHA=9.99\nVERDICT=PASS\n'
STUB
SINK=stub
rows_golden "$T/stub.sh"
SINK=main
_stub_fail=0; _stub_pass=0
for _r in "${!STUB_FAILS[@]}"; do _stub_fail=$((_stub_fail + STUB_FAILS[$_r])); done
for _r in "${!STUB_PASSES[@]}"; do _stub_pass=$((_stub_pass + STUB_PASSES[$_r])); done
chk H "the golden rows go RED against a constant-mean stub (${_stub_fail} red)" [ "$_stub_fail" -ge 12 ]
# the stub may pass only the lines it prints (COHORT_PRS=4, the exit status, SLICES none); a neutered predicate would pass more
chk H "the stub passes at most the 3 assertions it can satisfy (passed $_stub_pass)" [ "$_stub_pass" -le 3 ]

# no run of this suite leaves a scratch directory behind in the fixture TMPDIR
chk Z "fixture runs leave no scratch directory" [ -z "$(find "$T/ftmp" -mindepth 1 -maxdepth 1)" ]
chk Z "no census run hit the ${CENSUS_TO} s timeout" [ ! -e "$DEADLINE_FILE" ]

# ── Assertion floor ──────────────────────────────────────────────────────────
# DELIBERATELY NOT ROUTED THROUGH fail(): literal comparison and a direct exit.
# KEEP THE TWO ASSIGNMENTS AND THE `if` CONTIGUOUS (no comment between them).
_total=$((passes + fails))
_FLOOR=128
if [ "$_total" -lt "$_FLOOR" ]; then
  printf 'FAIL: assertion floor: %d assertion(s) ran, floor is %d - the suite lost coverage rather than passing it\n' \
    "$_total" "$_FLOOR" >&2
  printf 'ci-draft-push-census: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
  exit 1
fi

printf 'ci-draft-push-census: %d passed, %d failed (%d assertions)\n' "$passes" "$fails" "$_total"
exit $(( ${#FAILURES[@]} > 0 ))
