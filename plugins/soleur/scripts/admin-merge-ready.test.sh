#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row/mutation functions are dispatched indirectly; A && B || why is the assertion idiom; jq programs are single-quoted on purpose
# Suite for plugins/soleur/scripts/admin-merge-ready.sh (#8500) -- Guard 1 of the plan's Guard
# Contract (knowledge-base/project/plans/2026-09-22-feat-admin-merge-ready-script-plan.md).
#
# ── THE SEAM ─────────────────────────────────────────────────────────────────────────────────
# `gh` is a PATH stub that answers ONLY the four requests the SUT is expected to make, keyed on
# the FULL argv (including --paginate/--slurp and the query string), and refuses anything else
# with exit 64 after logging `STUB-MISS <argv>`. Every row asserts the log holds no STUB-MISS, so
# a SUT querying the wrong endpoint cannot turn a stub refusal into the exit 3 an error row wants.
# `sleep` is a PATH stub too: it logs its argument, so the --wait cadence is observable.
#
# ── THE FIXTURES ─────────────────────────────────────────────────────────────────────────────
# Every row is a jq edit of ONE real-shape base captured read-only from GitHub
# (test/fixtures/admin-merge-ready/, provenance in its README): 26 required contexts across two
# rulesets, 77 check runs, all required contexts green. No hand-written required set exists.
#
# ── MUTATION ROWS ────────────────────────────────────────────────────────────────────────────
# M-rows copy the SUT, apply one edit (asserted to have landed), and require BOTH that the named
# row FAILS against the mutant AND that the mutant exhibits the specific defect the row exists to
# catch (e.g. R2: the #8458 fixture now reads ready). A mutant that merely crashes is not a kill.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SUT="$SCRIPT_DIR/admin-merge-ready.sh"
BASE_FX="$SCRIPT_DIR/../test/fixtures/admin-merge-ready"

passes=0; fails=0; CASES_RUN=0; FAILED=()
pass() { passes=$((passes + 1)); echo "  PASS: $1"; }
fail() { fails=$((fails + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }

_iv_p="$passes"; _iv_f="$fails"; _iv_n="${#FAILED[@]}"
{ pass "self-test"; fail "self-test"; } >/dev/null 2>&1
if [[ "$passes" -ne $((_iv_p + 1)) || "$fails" -ne $((_iv_f + 1)) || "${#FAILED[@]}" -ne $((_iv_n + 1)) ]]; then
  printf '[FATAL] instrument self-test: the verdict helpers did not both record\n' >&2; exit 1
fi
passes=0; fails=0; FAILED=(); CASES_RUN=0

[[ -f "$REAL_SUT" ]] || { echo "[FATAL] SUT not found at $REAL_SUT" >&2; exit 1; }
[[ -f "$BASE_FX/rules-branches-main.json" && -f "$BASE_FX/check-runs.json" ]] \
  || { echo "[FATAL] base fixtures missing under $BASE_FX" >&2; exit 1; }
command -v jq >/dev/null || { echo "[FATAL] jq required" >&2; exit 1; }
command -v python3 >/dev/null || { echo "[FATAL] python3 required (mutation rows)" >&2; exit 1; }

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

SANDBOX="$(mktemp -d)"; assert_fixture_dir "$SANDBOX"
trap 'rm -rf "$SANDBOX"' EXIT

SHA=319c22bffa4c1785da52dd9af9471a9d8eef1310
PR=8534
SUT="$REAL_SUT"
TIMEOUT_BIN="$(command -v timeout)" || { echo "[FATAL] timeout(1) required" >&2; exit 1; }

# ── H6: fixture preconditions every row depends on ──────────────────────────────────────────
pre() { jq -e "$1" "$2" >/dev/null || { echo "[FATAL] H6 fixture precondition failed: $3 -- recapture the base (see README)" >&2; exit 1; }; }
pre '[.[0][] | select(.type=="required_status_checks") | .parameters.required_status_checks[]] | length >= 26' \
  "$BASE_FX/rules-branches-main.json" ">=26 required entries"
pre '[.[0][] | select(.ruleset_id==13304872) | .parameters.required_status_checks[]?.context] | index("cla-evidence") != null' \
  "$BASE_FX/rules-branches-main.json" "cla-evidence in ruleset 13304872"
pre '[.[0][] | select(.ruleset_id!=13304872) | .parameters.required_status_checks[]?.context] | index("cla-evidence") == null' \
  "$BASE_FX/rules-branches-main.json" "cla-evidence ONLY in ruleset 13304872"
pre '[.[0][] | .type] | index("deletion") != null' "$BASE_FX/rules-branches-main.json" "a non-check rule type is present"
pre '[.[0].check_runs[] | select(.name=="test" and .app.id==15368 and .status=="completed" and .conclusion=="success")] | length == 1' \
  "$BASE_FX/check-runs.json" "test present and green"
pre '[.[0].check_runs[] | select(.name=="CodeQL")] | all(.app.id == 57789) and length >= 1' \
  "$BASE_FX/check-runs.json" "CodeQL run carries app 57789"
pre "[.[0].check_runs[].head_sha] | unique == [\"$SHA\"]" "$BASE_FX/check-runs.json" "every run carries the fixture head_sha"
[[ "$(grep -c -e 'https://' -e '@' "$BASE_FX"/*.json | awk -F: '{s+=$2} END {print s}')" == 0 ]] \
  || { echo "[FATAL] H6: base fixtures carry URLs or emails" >&2; exit 1; }

# ── the stubs ───────────────────────────────────────────────────────────────────────────────
BIN="$SANDBOX/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
# Per-poll files: <name>.<poll>.json wins over <name>.json; the poll counter advances on `pr view`.
args="$*"
printf '%s\n' "$args" >> "$STUB_LOG"
poll=$(cat "$FX/.polls" 2>/dev/null || echo 0)
pick() { if [[ -f "$FX/$1.$poll.json" ]]; then cat "$FX/$1.$poll.json"; else cat "$FX/$1.json"; fi; }
failing() { [[ -f "$FX/$1.fail" || -f "$FX/$1.fail.$poll" ]]; }
enc=$(cat "$FX/expect_base_enc" 2>/dev/null || echo main)
runs_url="repos/{owner}/{repo}/commits/$STUB_SHA/check-runs?per_page=100&filter=all"
case "$args" in
  "pr view $STUB_PR --json state,headRefOid,baseRefName,changedFiles")
    poll=$((poll + 1)); echo "$poll" > "$FX/.polls"
    failing pr && exit 1
    pick pr ;;
  "api --paginate --slurp repos/{owner}/{repo}/pulls/$STUB_PR/files?per_page=100")
    failing files && exit 1
    pick files ;;
  "api --paginate --slurp repos/{owner}/{repo}/rules/branches/$enc")
    failing rules && exit 1
    pick rules ;;
  "api --paginate --slurp $runs_url")
    if failing runs; then pick runs | jq -c '[.[0]]'; exit 1; fi   # page 1 printed, page 2 failed
    pick runs ;;
  "api --slurp $runs_url")   # the no---paginate mutant: only the first page is ever read
    pick runs | jq -c '[.[0]]' ;;
  *) printf 'STUB-MISS %s\n' "$args" >> "$STUB_LOG"; echo "stub: unexpected gh argv: $args" >&2; exit 64 ;;
esac
GH
cat > "$BIN/sleep" <<'SLP'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FX/sleeps"
SLP
chmod +x "$BIN/gh" "$BIN/sleep"
# A PATH with jq but no gh, for the missing-tool row.
NOGH="$SANDBOX/nogh"; mkdir -p "$NOGH"; ln -s "$(command -v jq)" "$NOGH/jq"

# ── row plumbing ────────────────────────────────────────────────────────────────────────────
mkrow() { # <name> -> prints dir; fresh copy of the base
  local d="$SANDBOX/rows/$1"; assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d"
  cp "$BASE_FX/rules-branches-main.json" "$d/rules.json"
  cp "$BASE_FX/check-runs.json" "$d/runs.json"
  printf '{"state":"OPEN","headRefOid":"%s","baseRefName":"main","changedFiles":1}\n' "$SHA" > "$d/pr.json"
  echo '[[{"filename":"plugins/soleur/x.md"}]]' > "$d/files.json"
  printf '%s' "$d"
}
# jqf <dir> <file> <filter> : edit a fixture file in place
jqf() {
  assert_fixture_dir "$1"
  local t; t=$(mktemp "$SANDBOX/jqf.XXXXXX")
  jq "$3" "$1/$2" > "$t" && mv "$t" "$1/$2" || { echo "[FATAL] jq edit failed: $3" >&2; exit 1; }
}
# setfiles <dir> <json-pages> : set the PR file list and keep changedFiles consistent with it
setfiles() {
  assert_fixture_dir "$1"
  printf '%s\n' "$2" > "$1/files.json"
  jqf "$1" pr.json ".changedFiles = $(jq '[.[][]] | length' <<<"$2")"
}
# runs <dir> <filter-over-check_runs-array> [outfile]
runs() {
  assert_fixture_dir "$1"
  local out="${3:-runs.json}"; [[ "$out" == runs.json ]] || cp "$1/runs.json" "$1/$out"
  jqf "$1" "$out" "map(.check_runs |= ($2))"
}
drop() { runs "$1" "map(select(.name != \"$2\"))" "${3:-runs.json}"; }
setrun() { runs "$1" "map(if .name == \"$2\" then $3 else . end)" "${4:-runs.json}"; }

run() { # <dir> <sut-args...> ; RUN_PATH / RUN_UNSET_POLL / RUN_POLL override the environment
  local d="$1"; shift
  assert_fixture_dir "$d"
  : > "$d/log"; rm -f "$d/.polls" "$d/sleeps"
  local -a envv=(FX="$d" STUB_LOG="$d/log" STUB_PR="$PR" STUB_SHA="$SHA" PATH="${RUN_PATH:-$BIN:$PATH}")
  if [[ -z "${RUN_UNSET_POLL:-}" ]]; then envv+=(ADMIN_MERGE_READY_POLL_SECONDS="${RUN_POLL:-0}"); fi
  env -u ADMIN_MERGE_READY_POLL_SECONDS "${envv[@]}" "$TIMEOUT_BIN" 30 "$BASH" "$SUT" "$@" > "$d/out" 2> "$d/err"
  echo $? > "$d/rc"
}
why() { echo "      why: $*" >&2; return 1; }
rc_is()   { [[ "$(cat "$1/rc")" == "$2" ]] || why "rc=$(cat "$1/rc"), want $2; out: $(tail -3 "$1/out" | tr '\n' '|') err: $(tail -2 "$1/err" | tr '\n' '|')"; }
line()    { grep -Fxq -- "$2" "$1/out" || why "missing stdout line: $2"; }
noline()  { ! grep -Fq -- "$2" "$1/out" || why "unexpected stdout text: $2"; }
tailis()  { local l; l=$(tail -1 "$1/out"); [[ "$l" == *" $2" ]] || why "marker tail is '$l', want '* $2'"; }
verdict() { tail -1 "$1/out" | grep -q "^SOLEUR_ADMIN_MERGE_READY verdict=$2 " || why "last line is not verdict=$2: $(tail -1 "$1/out")"; }
reason()  { tail -1 "$1/out" | grep -q " reason=$2 " || why "last line lacks reason=$2: $(tail -1 "$1/out")"; }
nomiss()  { ! grep -q '^STUB-MISS' "$1/log" || why "stub refused: $(grep '^STUB-MISS' "$1/log" | head -1)"; }
polls()   { [[ "$(cat "$1/.polls" 2>/dev/null || echo 0)" == "$2" ]] || why "polls=$(cat "$1/.polls" 2>/dev/null), want $2"; }
sleeps()  { [[ "$(cat "$1/sleeps" 2>/dev/null | wc -l)" == "$2" ]] || why "sleeps=$(cat "$1/sleeps" 2>/dev/null | wc -l), want $2"; }
count()   { [[ "$(grep -c -- "$2" "$1/out")" == "$3" ]] || why "count of '$2' = $(grep -c -- "$2" "$1/out"), want $3"; }
logs()    { grep -Fq -- "$2" "$1/log" || why "stub log lacks request: $2"; }
nocall()  { [[ ! -s "$1/log" ]] || why "gh was called: $(head -1 "$1/log")"; }

case_ok() { CASES_RUN=$((CASES_RUN + 1)); if "$2"; then pass "$1"; else fail "$1"; fi; }
# case_mutant <id> <row-fn> <defect-fn> <python-old> <python-new>
#   The row must FAIL against the mutant AND <defect-fn> must confirm the mutant shows the defect.
case_mutant() {
  CASES_RUN=$((CASES_RUN + 1))
  local id="$1" fn="$2" defect="$3" m="$SANDBOX/mut-$1.sh"
  cp "$REAL_SUT" "$m"
  OLD="$4" NEW="$5" python3 - "$m" <<'PY' || { fail "$id (mutation did not land)"; return; }
import os, sys
p = sys.argv[1]; s = open(p).read(); o = os.environ["OLD"]
if s.count(o) != 1: sys.exit(1)
open(p, "w").write(s.replace(o, os.environ["NEW"]))
PY
  cmp -s "$m" "$REAL_SUT" && { fail "$id (mutant identical to SUT)"; return; }
  if ( SUT="$m"; "$fn" ) 2>/dev/null; then fail "$id (row $fn still passes against the mutant)"; return; fi
  if "$defect"; then pass "$id (row $fn reds, mutant shows the defect)"
  else fail "$id (row $fn reds, but the mutant did not show the defect -- a crash is not a kill)"; fi
}
rowdir() { printf '%s' "$SANDBOX/rows/$1"; }
rc_of() { cat "$(rowdir "$1")/rc"; }

READY_TAIL="required=26 absent=[] pending=[] failed=[]"

# ── rows ────────────────────────────────────────────────────────────────────────────────────
row_H1() { local d; d=$(mkrow H1); assert_fixture_dir "$d"; run "$d" "$PR" "$SHA"
  rc_is "$d" 0 && nomiss "$d" && [[ "$(cat "$d/out")" == "SOLEUR_ADMIN_MERGE_READY verdict=ready pr=$PR sha=$SHA base=main reason=all-green $READY_TAIL" ]] \
    || why "H1 stdout is not exactly the ready marker: $(cat "$d/out")"; }
row_H2() { local d; d=$(mkrow H2); assert_fixture_dir "$d"
  setrun "$d" "e2e" '.conclusion = "skipped"'
  setrun "$d" "markdown-lint" '.conclusion = "neutral"'
  runs "$d" '. + [(.[] | select(.name == "lockfile-sync") | .id = (.id - 5) | .conclusion = "failure")]'
  runs "$d" ". + [range(0;50) as \$i | {id: (9000000000 + \$i), name: \"extra-\\(\$i)\", head_sha: \"$SHA\", status: \"completed\", conclusion: \"failure\", started_at: null, app: {id: 15368}, check_suite: {id: 1}}]"
  run "$d" "$PR" "$SHA"; rc_is "$d" 0 && nomiss "$d" && tailis "$d" "$READY_TAIL"; }
row_R1() { local d; d=$(mkrow R1); assert_fixture_dir "$d"; drop "$d" test; run "$d" "$PR" "$SHA"
  rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  test" && verdict "$d" not-ready && reason "$d" not-green \
    && tailis "$d" 'required=26 absent=["test"] pending=[] failed=[]'; }
row_R3() { local d; d=$(mkrow R3); assert_fixture_dir "$d"; drop "$d" tenant-integration-required; drop "$d" cla-evidence; run "$d" "$PR" "$SHA"
  rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  tenant-integration-required" && line "$d" "ABSENT  cla-evidence" \
    && noline "$d" " enforce" && tailis "$d" 'required=26 absent=["tenant-integration-required","cla-evidence"] pending=[] failed=[]'; }
row_R4() { local d; d=$(mkrow R4); assert_fixture_dir "$d"
  setrun "$d" enforce '.id = 99999999999'
  runs "$d" '. + [(.[] | select(.name == "enforce") | .id = 100000000000 | .status = "queued" | .conclusion = null | .started_at = null)]'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "PENDING enforce (queued)" \
    && tailis "$d" 'required=26 absent=[] pending=["enforce"] failed=[]'; }
row_R5() { local d; d=$(mkrow R5); assert_fixture_dir "$d"; setrun "$d" test '.conclusion = "failure"'; run "$d" "$PR" "$SHA"
  rc_is "$d" 1 && nomiss "$d" && line "$d" "FAILED  test (failure)" && tailis "$d" 'required=26 absent=[] pending=[] failed=["test"]'; }
row_R6() { local c d; for c in stale cancelled bogus-conclusion; do d=$(mkrow "R6-$c"); assert_fixture_dir "$d"
    setrun "$d" test ".conclusion = \"$c\""; run "$d" "$PR" "$SHA"
    rc_is "$d" 1 && nomiss "$d" && line "$d" "FAILED  test ($c)" || return 1; done; }
row_R7() { local d; d=$(mkrow R7); assert_fixture_dir "$d"; drop "$d" cla-evidence; run "$d" "$PR" "$SHA"
  rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  cla-evidence"; }
row_R8() { local d; d=$(mkrow R8); assert_fixture_dir "$d"; setrun "$d" CodeQL '.app.id = 15368'; run "$d" "$PR" "$SHA"
  rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  CodeQL"; }
row_R9() { local d
  d=$(mkrow R9a); assert_fixture_dir "$d"; touch "$d/rules.fail"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && logs "$d" "rules/branches/main" || return 1
  d=$(mkrow R9b); assert_fixture_dir "$d"; echo '[[]]' > "$d/rules.json"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && reason "$d" empty-required || return 1
  d=$(mkrow R9c); assert_fixture_dir "$d"; jqf "$d" runs.json '[.[0] | .check_runs |= map(select(.name != "test"))] + [{total_count: 1, check_runs: [(.[0].check_runs[] | select(.name == "test"))]}]'
  touch "$d/runs.fail"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && logs "$d" "check-runs" || return 1
  d=$(mkrow R9d); assert_fixture_dir "$d"; setfiles "$d" '[[{"filename":".github/workflows/x.yml"}]]'; touch "$d/files.fail"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && logs "$d" "pulls/$PR/files" || return 1
  d=$(mkrow R9e); assert_fixture_dir "$d"; touch "$d/pr.fail"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error || return 1
  d=$(mkrow R9f); assert_fixture_dir "$d"; echo '<html>502 Bad Gateway</html>' > "$d/runs.json"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error || return 1
  d=$(mkrow R9g); assert_fixture_dir "$d"; : > "$d/runs.json"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error || return 1
  d=$(mkrow R9h); assert_fixture_dir "$d"; : > "$d/files.json"; run "$d" "$PR" "$SHA"
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error; }
row_R10() { local d; d=$(mkrow R10); assert_fixture_dir "$d"; jqf "$d" pr.json '.headRefOid = "0000000000000000000000000000000000000000"'; run "$d" "$PR" "$SHA"
  rc_is "$d" 4 && nomiss "$d" && verdict "$d" stale && reason "$d" head-moved; }
row_R11() { local d; d=$(mkrow R11); assert_fixture_dir "$d"
  jqf "$d" runs.json '[.[0] | .check_runs |= map(select(.name != "test"))] + [{total_count: 1, check_runs: [(.[0].check_runs[] | select(.name == "test"))]}]'
  run "$d" "$PR" "$SHA"; rc_is "$d" 0 && nomiss "$d" && tailis "$d" "$READY_TAIL"; }
row_R12() { local d; d=$(mkrow R12); assert_fixture_dir "$d"; jqf "$d" rules.json '.[0][0].parameters.required_status_checks[0].integration_id = null'
  run "$d" "$PR" "$SHA"; rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && reason "$d" unpinned && grep -q 'unpinned required context(s) \["enforce"\]' "$d/err" \
    || why "R12 does not name the unpinned context: $(cat "$d/err")"; }
row_R13() { local d; d=$(mkrow R13); assert_fixture_dir "$d"; jqf "$d" pr.json '.state = "MERGED"'; run "$d" "$PR" "$SHA"
  rc_is "$d" 4 && nomiss "$d" && verdict "$d" stale && line "$d" "NOT-OPEN: PR is not open"; }
row_R14() { local d a; d=$(mkrow R14); assert_fixture_dir "$d"
  for a in "" "abc $SHA" "$PR ${SHA:0:7}" "$PR $SHA --timeout 0" "$PR $SHA --bogus" "$PR $SHA --base bad;name"; do
    # shellcheck disable=SC2086
    run "$d" $a; rc_is "$d" 2 && verdict "$d" error && nocall "$d" || return 1
  done
  RUN_POLL=abc run "$d" "$PR" "$SHA" --wait; rc_is "$d" 2 && verdict "$d" error && nocall "$d"; }
row_R15() { local d; d=$(mkrow R15); assert_fixture_dir "$d"; jqf "$d" pr.json '.baseRefName = "feat/x"'; echo 'feat%2Fx' > "$d/expect_base_enc"
  run "$d" "$PR" "$SHA" --base feat/x; rc_is "$d" 0 && nomiss "$d" && logs "$d" "rules/branches/feat%2Fx"; }
row_R16() { local d; d=$(mkrow R16); assert_fixture_dir "$d"
  drop "$d" test runs.1.json; setrun "$d" test '.status = "in_progress" | .conclusion = null' runs.2.json
  run "$d" "$PR" "$SHA" --wait; rc_is "$d" 0 && nomiss "$d" && polls "$d" 3 && count "$d" '^WAIT ' 2 && verdict "$d" ready \
    && line "$d" 'WAIT poll=1/60 absent=["test"] pending=[]' && line "$d" 'WAIT poll=2/60 absent=[] pending=["test"]' && sleeps "$d" 2; }
row_R17() { local d; d=$(mkrow R17); assert_fixture_dir "$d"
  drop "$d" test runs.1.json; setrun "$d" test '.conclusion = "failure"' runs.2.json; setrun "$d" test '.conclusion = "success"' runs.3.json
  run "$d" "$PR" "$SHA" --wait; rc_is "$d" 1 && nomiss "$d" && polls "$d" 2 && verdict "$d" not-ready && line "$d" "FAILED  test (failure)"; }
row_R18() { local d; d=$(mkrow R18); assert_fixture_dir "$d"; drop "$d" test runs.1.json
  jq '.headRefOid = "1111111111111111111111111111111111111111"' "$d/pr.json" > "$d/pr.2.json"
  run "$d" "$PR" "$SHA" --wait; rc_is "$d" 4 && nomiss "$d" && polls "$d" 2 && verdict "$d" stale; }
row_R19() { local d; d=$(mkrow R19); assert_fixture_dir "$d"; drop "$d" test
  run "$d" "$PR" "$SHA" --wait --timeout 180; rc_is "$d" 1 && nomiss "$d" && polls "$d" 3 && sleeps "$d" 2 && verdict "$d" timeout \
    && tailis "$d" 'required=26 absent=["test"] pending=[] failed=[]' || return 1
  # A timeout that is not a multiple of 60 rounds UP: 90 s is two polls, never one or zero.
  run "$d" "$PR" "$SHA" --wait --timeout 90; rc_is "$d" 1 && polls "$d" 2 && verdict "$d" timeout; }
row_R20() { local d; d=$(mkrow R20); assert_fixture_dir "$d"; drop "$d" test runs.1.json; touch "$d/rules.fail.2"
  run "$d" "$PR" "$SHA" --wait; rc_is "$d" 3 && nomiss "$d" && polls "$d" 2 && verdict "$d" error; }
row_R21() { local d; d=$(mkrow R21); assert_fixture_dir "$d"
  runs "$d" '. + [(.[] | select(.name == "CodeQL") | .id = (.id + 1000) | .app.id = 15368 | .conclusion = "failure")]'
  run "$d" "$PR" "$SHA"; rc_is "$d" 0 && nomiss "$d"; }
row_R22() { local d; d=$(mkrow R22); assert_fixture_dir "$d"; setrun "$d" CodeQL '.conclusion = "failure"'
  runs "$d" '. + [(.[] | select(.name == "CodeQL") | .id = (.id + 1000) | .app.id = 15368 | .conclusion = "success")]'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "FAILED  CodeQL (failure)"; }
row_R23() { local d; d=$(mkrow R23); assert_fixture_dir "$d"; drop "$d" test
  jqf "$d" rules.json '.[0] |= map(if .ruleset_id == 13304872 and .type == "required_status_checks" then .parameters.required_status_checks += [{context: "test", integration_id: 15368}] else . end)'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && count "$d" '^ABSENT  test$' 1 && tailis "$d" 'required=26 absent=["test"] pending=[] failed=[]'; }
row_R24() { local d; d=$(mkrow R24); assert_fixture_dir "$d"; setrun "$d" test '.status = "mystery" | .conclusion = null'; run "$d" "$PR" "$SHA"
  rc_is "$d" 1 && nomiss "$d" && line "$d" "FAILED  test (unknown status mystery)"; }
row_R25() { local d i; d=$(mkrow R25); assert_fixture_dir "$d"
  for i in 1 2 3 4 5 6 7; do setrun "$d" test '.status = "in_progress" | .conclusion = null' "runs.$i.json"; done
  run "$d" "$PR" "$SHA" --wait; rc_is "$d" 0 && nomiss "$d" && polls "$d" 8 && count "$d" '^HEARTBEAT ' 1 \
    && count "$d" '^HEARTBEAT poll=5/' 1 && count "$d" '^WAIT ' 1; }
row_R26() { local d p
  for p in '[[{"filename":"README.md"}],[{"filename":".github/workflows/new.yml"}]]' \
           '[[{"filename":".github/actions/setup/action.yml"}],[{"filename":"README.md"}]]' \
           '[[{"filename":"ci/renamed.yml","previous_filename":".github/workflows/ci.yml"}]]'; do
    d=$(mkrow R26); assert_fixture_dir "$d"; setfiles "$d" "$p"; run "$d" "$PR" "$SHA"
    rc_is "$d" 1 && nomiss "$d" && verdict "$d" not-ready && reason "$d" untrusted-ci && grep -q '^UNTRUSTED-CI' "$d/out" \
      && noline "$d" ".yml" || return 1
  done
  # Terminal under --wait: one poll, no waiting out the budget.
  run "$d" "$PR" "$SHA" --wait; rc_is "$d" 1 && polls "$d" 1 && verdict "$d" not-ready && reason "$d" untrusted-ci; }
row_R27() { local c d suite
  for c in skipped neutral; do
    d=$(mkrow "R27-$c"); assert_fixture_dir "$d"
    suite=$(jq '.[0].check_runs[] | select(.name == "tenant-integration-required") | .check_suite.id' "$d/runs.json")
    setrun "$d" tenant-integration-required ".conclusion = \"$c\""
    runs "$d" ". + [{id: 8000000000, name: \"some-shard\", head_sha: \"$SHA\", status: \"completed\", conclusion: \"failure\", started_at: null, app: {id: 15368}, check_suite: {id: $suite}}]"
    run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "FAILED  tenant-integration-required ($c-after-failure)" || return 1
    # The dependency is being RE-RUN: its latest run is in progress, the skip is not yet recreated.
    d=$(mkrow "R27-$c-rerun"); assert_fixture_dir "$d"
    setrun "$d" tenant-integration-required ".conclusion = \"$c\""
    runs "$d" ". + [{id: 8000000000, name: \"some-shard\", head_sha: \"$SHA\", status: \"completed\", conclusion: \"failure\", started_at: null, app: {id: 15368}, check_suite: {id: $suite}}, {id: 999999999999, name: \"some-shard\", head_sha: \"$SHA\", status: \"in_progress\", conclusion: null, started_at: null, app: {id: 15368}, check_suite: {id: $suite}}]"
    run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "PENDING tenant-integration-required ($c-while-suite-running)" || return 1
    d=$(mkrow "R27-$c-clean"); assert_fixture_dir "$d"; setrun "$d" tenant-integration-required ".conclusion = \"$c\""
    run "$d" "$PR" "$SHA"; rc_is "$d" 0 && nomiss "$d" || return 1
  done; }
row_R28() { local d; d=$(mkrow R28); assert_fixture_dir "$d"; drop "$d" cla-evidence
  # Rules split over two pages, the CLA ruleset on page 2 only.
  jqf "$d" rules.json '[[.[0][] | select(.ruleset_id != 13304872)], [.[0][] | select(.ruleset_id == 13304872)]]'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  cla-evidence"; }
row_R29() { local d; d=$(mkrow R29); assert_fixture_dir "$d"; jqf "$d" rules.json '.[0] += [{type: "workflows", ruleset_id: 1}]'
  run "$d" "$PR" "$SHA"; rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && reason "$d" unsupported-rule; }
row_R30() { local d; d=$(mkrow R30); assert_fixture_dir "$d"; jqf "$d" pr.json '.changedFiles = 2'
  run "$d" "$PR" "$SHA"; rc_is "$d" 3 && nomiss "$d" && reason "$d" incomplete-files || return 1
  d=$(mkrow R30b); assert_fixture_dir "$d"; setfiles "$d" "[[$(jq -nc '[range(0;3000) | {filename: "f\(.)"}] | .[]' | paste -sd,)]]"
  run "$d" "$PR" "$SHA"; rc_is "$d" 3 && nomiss "$d" && reason "$d" incomplete-files; }
row_R31() { local d; d=$(mkrow R31); assert_fixture_dir "$d"; jqf "$d" pr.json '.baseRefName = "develop"'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && verdict "$d" not-ready && reason "$d" base-mismatch; }
row_R32() { local d; d=$(mkrow R32); assert_fixture_dir "$d"; setrun "$d" test '.head_sha = "2222222222222222222222222222222222222222"'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  test"; }
row_R33() { local d; d=$(mkrow R33); assert_fixture_dir "$d"
  RUN_PATH="$NOGH" run "$d" "$PR" "$SHA"; rc_is "$d" 3 && verdict "$d" error && reason "$d" missing-tool; }
row_R34() { local d; d=$(mkrow R34); assert_fixture_dir "$d"; drop "$d" test runs.1.json
  RUN_UNSET_POLL=1 run "$d" "$PR" "$SHA" --wait; rc_is "$d" 0 && [[ "$(cat "$d/sleeps")" == "60" ]] || why "default poll interval is not 60: $(cat "$d/sleeps" 2>/dev/null)"; }
row_R35() { local d; d=$(mkrow R35); assert_fixture_dir "$d"
  # The same context required from two different apps: both entries must be satisfied.
  jqf "$d" rules.json '.[0] |= map(if .ruleset_id == 13304872 and .type == "required_status_checks" then .parameters.required_status_checks += [{context: "CodeQL", integration_id: 15368}] else . end)'
  run "$d" "$PR" "$SHA"; rc_is "$d" 1 && nomiss "$d" && line "$d" "ABSENT  CodeQL" && tailis "$d" 'required=27 absent=["CodeQL"] pending=[] failed=[]'; }
row_help() { local d; d=$(mkrow help); assert_fixture_dir "$d"; run "$d" --help
  rc_is "$d" 0 && grep -q SOLEUR_ADMIN_MERGE_READY "$d/out" && nocall "$d"; }

# defect probes for the mutation rows: the mutant must show the defect, not merely crash.
# R2's mutant iterates present checks, so the absent `test` is never named (the positive
# readiness count then refuses it as an error rather than a ready -- defence in depth).
dfx_R1_unnamed() { ! grep -Fxq 'ABSENT  test' "$(rowdir R1)/out"; }
dfx_R11_absent() { [[ "$(rc_of R11)" == 1 ]] && grep -Fxq 'ABSENT  test' "$(rowdir R11)/out"; }
dfx_H1_miss()    { grep -q '^STUB-MISS' "$(rowdir H1)/log"; }
dfx_R4_green()   { [[ "$(rc_of R4)" == 0 ]]; }
dfx_R27_green()  { grep -q 'verdict=ready' "$SANDBOX/rows/R27-skipped/out"; }
dfx_R8_green()   { [[ "$(rc_of R8)" == 0 ]]; }
dfx_R26_ready()  { grep -q 'verdict=ready' "$(rowdir R26)/out"; }
dfx_R32_green()  { [[ "$(rc_of R32)" == 0 ]]; }
dfx_R28_green()  { [[ "$(rc_of R28)" == 0 ]]; }

echo "== admin-merge-ready.sh (Guard 1)"
for r in H1 H2 R1 R3 R4 R5 R6 R7 R8 R9 R10 R11 R12 R13 R14 R15 R16 R17 R18 R19 R20 R21 R22 R23 R24 R25 R26 R27 R28 R29 R30 R31 R32 R33 R34 R35 help; do
  case_ok "$r" "row_$r"
done

echo "== mutation rows"
# R2 -- the dispatch row: iterate the PRESENT checks instead of the REQUIRED set (#8458).
case_mutant R2 row_R1 dfx_R1_unnamed '| [ $req[] as $q' '| [ ($runs | map({context: .name, integration_id: .app.id}) | unique)[] as $q'
# R11 -- drop --paginate from the check-runs call only: page 2 (which holds `test`) is never read.
case_mutant R11-paginate row_R11 dfx_R11_absent 'gh api --paginate --slurp "repos/{owner}/{repo}/commits/' 'gh api --slurp "repos/{owner}/{repo}/commits/'
# H3 -- query a different endpoint: the strict stub must refuse it, not answer from the fixture.
case_mutant H3-endpoint row_H1 dfx_H1_miss 'repos/{owner}/{repo}/rules/branches/$enc' 'repos/{owner}/{repo}/rulesets'
# R4 by timestamp: pick the latest run by started_at instead of id.
case_mutant R4-started_at row_R4 dfx_R4_green '($c | max_by(.id | tonumber)) as $l' '($c | max_by(.started_at // "")) as $l'
# R27: drop the skipped-after-failure rule.
case_mutant R27-rule row_R27 dfx_R27_green 'elif any($sib[]; .status == "completed"' 'elif false and any($sib[]; .status == "completed"'
# R8/R22: match by name only.
case_mutant R8-app row_R8 dfx_R8_green 'select(.name == $q.context and .app.id == $q.integration_id)' 'select(.name == $q.context)'
# R26: the untrusted-CI refusal narrowed to workflows only (.github/actions/ edits pass).
case_mutant R26-actions row_R26 dfx_R26_ready 'select(test("^\\.github/(workflows|actions)/"))' 'select(test("^\\.github/workflows/"))'
# R32: drop the head_sha restriction.
case_mutant R32-headsha row_R32 dfx_R32_green '| [.[] | .check_runs[] | select(.head_sha == $sha)] as $runs' '| [.[] | .check_runs[]] as $runs'
# R28: read only the first page of the rules.
case_mutant R28-rulespage row_R28 dfx_R28_green '($rules[0] | add // []) as $all' '($rules[0][0] // []) as $all'

# ── H4: anti-vacuity ─────────────────────────────────────────────────────────────────────────
echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"
_min_cases=46
if [[ "$CASES_RUN" -lt "$_min_cases" ]]; then
  printf '[FATAL] assertion floor: only %s case(s) ran, floor is %s\n' "$CASES_RUN" "$_min_cases" >&2; exit 1
fi
if [[ $((passes + fails)) -ne "$CASES_RUN" ]]; then
  printf '[FATAL] %s verdicts for %s cases\n' "$((passes + fails))" "$CASES_RUN" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne "$fails" ]]; then
  printf '[FATAL] ledger/counter disagree: %s vs %s\n' "${#FAILED[@]}" "$fails" >&2; exit 1
fi
if [[ "${#FAILED[@]}" -ne 0 ]]; then
  printf '[FATAL] %s failing assertion(s):\n' "${#FAILED[@]}" >&2
  printf '  - %s\n' "${FAILED[@]}" >&2; exit 1
fi
echo "admin-merge-ready: all $passes cases passed"
