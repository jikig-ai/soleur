#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2015,SC2016  # row/mutation functions are dispatched indirectly; A && B || why is the assertion idiom; jq programs are single-quoted on purpose
# Suite for plugins/soleur/scripts/check-red-on-main.sh (#9402) -- Guard 1 of the plan's Guard
# Contract (knowledge-base/project/plans/2026-10-01-chore-quarantine-red-main-checks-plan.md).
#
# ── THE SEAM ─────────────────────────────────────────────────────────────────────────────────
# `gh` is a PATH stub that answers ONLY the requests the SUT is expected to make, keyed on the
# endpoint path after flags are consumed, and refuses anything else with exit 64 after logging
# `STUB-MISS <argv>`. Before dispatch it passes every flag through a per-subcommand WHITELIST of
# flags the real gh CLI accepts (gh api: --paginate/--slurp/--jq/-X/-f/-F/-H/-i/...; gh issue:
# --label/--state/--milestone/--json/--jq/-L/--repo/...; gh label create: --force/--color/...),
# so an invented flag -- `gh api --arg`, the defect the 2026-09-25 stub-fidelity learning names --
# is a stub miss, never an answer. Every row asserts the log holds no STUB-MISS, so a SUT
# querying the wrong endpoint or flag cannot turn a stub refusal into the exit 3 an error row
# wants.
#
# ── THE FIXTURES ─────────────────────────────────────────────────────────────────────────────
# Each row dir carries: run.json (the PR-side failing run -> .workflow_id), wfruns.json (the
# completed main-branch run list, newest first), jobs.<run-id>.json per main run, and
# issues.json (gh issue list body). <name>.fail files force non-zero exits per endpoint.
#
# ── MUTATION ROWS ────────────────────────────────────────────────────────────────────────────
# M-rows copy the SUT, apply one edit (asserted to have landed), and require BOTH that the named
# row FAILS against the mutant AND that the mutant exhibits the specific defect the row exists to
# catch (e.g. M-listfail: the mutant FILES on a failed issue list). A mutant that merely crashes
# is not a kill.
export TMPDIR="${TMPDIR:-/var/tmp}"
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_SUT="$SCRIPT_DIR/../scripts/check-red-on-main.sh"

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

RUN_ID=700001          # the PR-side failing run the probe is pointed at
WFID=777               # the workflow_id that run resolves to
CHECK='deploy-script-tests (1/4)'
MAIN_NEW=9101          # newest completed main run
MAIN_OLD=9002          # older completed main run
SUT="$REAL_SUT"
TIMEOUT_BIN="$(command -v timeout)" || { echo "[FATAL] timeout(1) required" >&2; exit 1; }

# ── the stubs ───────────────────────────────────────────────────────────────────────────────
BIN="$SANDBOX/bin"; mkdir -p "$BIN"
cat > "$BIN/gh" <<'GH'
#!/usr/bin/env bash
# gh PATH stub: per-subcommand flag WHITELIST first (invented flag -> miss), then endpoint
# dispatch. Canned JSON per endpoint under $FX; <name>.fail forces a non-zero exit.
args="$*"
printf '%s\n' "$args" >> "$STUB_LOG"
miss()    { printf 'STUB-MISS %s\n' "$args" >> "$STUB_LOG"; echo "stub: unexpected gh argv: $args" >&2; exit 64; }
badflag() { printf 'STUB-MISS %s\n' "$args" >> "$STUB_LOG"; echo "stub: flag the real gh CLI does not accept here: $1" >&2; exit 64; }
failing() { [[ -f "$FX/$1.fail" ]]; }
valflag() { [[ $# -ge 2 ]] || miss; }

sub="${1-}"; [[ $# -ge 1 ]] || miss; shift
case "$sub" in
  api)
    ep=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --paginate|--slurp|-i|--include|--silent|--verbose) shift ;;
        --jq|-q|-X|--method|-f|--raw-field|-F|--field|-H|--header|--input|--hostname|--cache|-t|--template|-p|--preview)
          valflag "$@"; shift 2 ;;
        --jq=*|--method=*|--raw-field=*|--field=*|--header=*|--input=*|--hostname=*|--cache=*|--template=*|--preview=*) shift ;;
        -*) badflag "$1" ;;
        *)  [[ -z "$ep" ]] || miss; ep="$1"; shift ;;
      esac
    done
    [[ -n "$ep" ]] || miss
    case "$ep" in
      repos/*/actions/runs/*/jobs?*)
        rid="${ep##*/actions/runs/}"; rid="${rid%%/jobs?*}"
        failing "jobs.$rid" && { echo "stub: forced failure on jobs of run $rid" >&2; exit 1; }
        [[ -f "$FX/jobs.$rid.json" ]] || miss
        cat "$FX/jobs.$rid.json" ;;
      repos/*/actions/workflows/"$STUB_WFID"/runs?branch=main\&status=completed\&per_page=*)
        failing wfruns && { echo "stub: forced failure on workflow runs list" >&2; exit 1; }
        cat "$FX/wfruns.json" ;;
      repos/*/actions/runs/"$STUB_RUN_ID")
        failing run && { echo "stub: forced failure on run $STUB_RUN_ID" >&2; exit 1; }
        cat "$FX/run.json" ;;
      *) miss ;;
    esac ;;
  issue)
    isub="${1-}"; [[ $# -ge 1 ]] || miss; shift
    case "$isub" in
      list)
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -w|--web) shift ;;
            --app|-a|--assignee|-A|--author|-q|--jq|--json|-l|--label|-L|--limit|--mention|-m|--milestone|-S|--search|-s|--state|-t|--template|--type|-R|--repo)
              valflag "$@"; shift 2 ;;
            --app=*|--assignee=*|--author=*|--jq=*|--json=*|--label=*|--limit=*|--mention=*|--milestone=*|--search=*|--state=*|--template=*|--type=*|--repo=*) shift ;;
            -*) badflag "$1" ;;
            *)  miss ;;   # `issue list` takes no positional
          esac
        done
        failing issues && { echo "stub: forced failure on issue list" >&2; exit 1; }
        [[ -f "$FX/issues.json" ]] || miss
        cat "$FX/issues.json" ;;
      create)
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -e|--editor|-w|--web) shift ;;
            -a|--assignee|-b|--body|-F|--body-file|-l|--label|-m|--milestone|-p|--project|--recover|-t|--title|-R|--repo)
              valflag "$@"; shift 2 ;;
            --assignee=*|--body=*|--body-file=*|--label=*|--milestone=*|--project=*|--recover=*|--title=*|--repo=*) shift ;;
            -*) badflag "$1" ;;
            *)  miss ;;   # `issue create` takes no positional
          esac
        done
        failing create && { echo "stub: forced failure on issue create" >&2; exit 1; }
        printf 'https://github.com/stub/stub/issues/99\n' ;;
      comment|close)
        target=""
        while [[ $# -gt 0 ]]; do
          case "$1" in
            -R|--repo) valflag "$@"; shift 2 ;;
            --repo=*) shift ;;
            -e|--editor|-w|--web|--edit-last|--create-if-none|--delete-last|--yes)
              [[ "$isub" == comment ]] || badflag "$1"; shift ;;
            -b|--body|-F|--body-file|--attach)
              [[ "$isub" == comment ]] || badflag "$1"; valflag "$@"; shift 2 ;;
            --body=*|--body-file=*|--attach=*)
              [[ "$isub" == comment ]] || badflag "$1"; shift ;;
            -c|--comment|-r|--reason|--duplicate-of)
              [[ "$isub" == close ]] || badflag "$1"; valflag "$@"; shift 2 ;;
            --comment=*|--reason=*|--duplicate-of=*)
              [[ "$isub" == close ]] || badflag "$1"; shift ;;
            -*) badflag "$1" ;;
            *)  [[ -z "$target" ]] || miss; target="$1"; shift ;;
          esac
        done
        [[ -n "$target" ]] || miss
        failing "$isub" && { echo "stub: forced failure on issue $isub" >&2; exit 1; }
        # Real gh prints the comment URL / a close line on stdout: emit one so a SUT that
        # forgets >/dev/null breaks the marker-only-stdout contract observably.
        printf 'https://github.com/stub/stub/issues/99#stub-%s\n' "$isub" ;;
      *) miss ;;
    esac ;;
  label)
    lsub="${1-}"; [[ $# -ge 1 ]] || miss; shift
    [[ "$lsub" == create ]] || miss
    name=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -f|--force) shift ;;
        -c|--color|-d|--description|-R|--repo) valflag "$@"; shift 2 ;;
        --color=*|--description=*|--repo=*) shift ;;
        -*) badflag "$1" ;;
        *)  [[ -z "$name" ]] || miss; name="$1"; shift ;;
      esac
    done
    [[ -n "$name" ]] || miss
    failing label && { echo "stub: forced failure on label create" >&2; exit 1; }
    : ;;
  *) miss ;;
esac
GH
chmod +x "$BIN/gh"
# A PATH with jq but no gh, for the missing-tool row.
NOGH="$SANDBOX/nogh"; mkdir -p "$NOGH"; ln -s "$(command -v jq)" "$NOGH/jq"

# ── row plumbing ────────────────────────────────────────────────────────────────────────────
# setjob <dir> <run-id> <conclusion|ABSENT> [status] : write jobs.<run-id>.json. Every non-ABSENT
# fixture also carries the matrix PARENT name `deploy-script-tests`: the join is exact-name, so
# the parent must never answer for the `(1/4)` leg.
setjob() {
  assert_fixture_dir "$1"
  local rid="$2" concl="$3" st="${4:-completed}"
  if [[ "$concl" == ABSENT ]]; then
    printf '{"total_count":2,"jobs":[{"id":1,"run_id":%s,"name":"deploy-script-tests","status":"completed","conclusion":"success"},{"id":2,"run_id":%s,"name":"lint","status":"completed","conclusion":"success"}]}\n' \
      "$rid" "$rid" > "$1/jobs.$rid.json"
  else
    printf '{"total_count":3,"jobs":[{"id":1,"run_id":%s,"name":"deploy-script-tests (1/4)","status":"%s","conclusion":"%s"},{"id":2,"run_id":%s,"name":"deploy-script-tests","status":"completed","conclusion":"success"},{"id":3,"run_id":%s,"name":"lint","status":"completed","conclusion":"success"}]}\n' \
      "$rid" "$st" "$concl" "$rid" "$rid" > "$1/jobs.$rid.json"
  fi
}
SENT_BODY="still tracking\n\n<!-- soleur:red-on-main check=\"deploy-script-tests (1/4)\" -->\n"
# setissues <dir> <json-array> : the open ci/main-broken list the --report arm reads
setissues() { assert_fixture_dir "$1"; printf '%s\n' "$2" > "$1/issues.json"; }

mkrow() { # <name> -> prints dir; default shape: newest main run exercised the check and FAILED
  local d="$SANDBOX/rows/$1"; assert_fixture_dir "$d"
  rm -rf "$d"; mkdir -p "$d"
  printf '{"id":%s,"workflow_id":%s,"name":"Infra Validation","head_branch":"feat/x","status":"completed","conclusion":"failure"}\n' \
    "$RUN_ID" "$WFID" > "$d/run.json"
  printf '{"total_count":2,"workflow_runs":[{"id":%s,"head_branch":"main","status":"completed","conclusion":"failure","workflow_id":%s},{"id":%s,"head_branch":"main","status":"completed","conclusion":"success","workflow_id":%s}]}\n' \
    "$MAIN_NEW" "$WFID" "$MAIN_OLD" "$WFID" > "$d/wfruns.json"
  setjob "$d" "$MAIN_NEW" failure
  setjob "$d" "$MAIN_OLD" success
  printf '[]\n' > "$d/issues.json"
  printf '%s' "$d"
}

run() { # <dir> <sut-args...> ; RUN_PATH overrides PATH
  local d="$1"; shift
  assert_fixture_dir "$d"
  : > "$d/log"; rm -f "$d/out" "$d/err" "$d/rc"
  env FX="$d" STUB_LOG="$d/log" STUB_RUN_ID="$RUN_ID" STUB_WFID="$WFID" \
      PATH="${RUN_PATH:-$BIN:$PATH}" "$TIMEOUT_BIN" 30 "$BASH" "$SUT" "$@" > "$d/out" 2> "$d/err"
  echo $? > "$d/rc"
}
why() { echo "      why: $*" >&2; return 1; }
rc_is()   { [[ "$(cat "$1/rc")" == "$2" ]] || why "rc=$(cat "$1/rc"), want $2; out: $(tail -3 "$1/out" | tr '\n' '|') err: $(tail -2 "$1/err" | tr '\n' '|')"; }
outis()   { [[ "$(cat "$1/out")" == "$2" ]] || why "stdout is not exactly: $2 -- got: $(cat "$1/out")"; }
verdict() { tail -1 "$1/out" | grep -q "^SOLEUR_RED_ON_MAIN verdict=$2 " || why "last line is not verdict=$2: $(tail -1 "$1/out")"; }
onemarker() { [[ "$(grep -c '^SOLEUR_RED_ON_MAIN ' "$1/out")" == 1 ]] || why "want exactly 1 marker line, got: $(cat "$1/out")"; }
nomiss()  { ! grep -q '^STUB-MISS' "$1/log" || why "stub refused: $(grep '^STUB-MISS' "$1/log" | head -1)"; }
logs()    { grep -Fq -- "$2" "$1/log" || why "stub log lacks request: $2"; }
nologs()  { ! grep -Fq -- "$2" "$1/log" || why "stub log holds an UNWANTED request: $2"; }
nocall()  { [[ ! -s "$1/log" ]] || why "gh was called: $(head -1 "$1/log")"; }

case_ok() { CASES_RUN=$((CASES_RUN + 1)); if "$2"; then pass "$1"; else fail "$1"; fi; }
# case_mutant <id> <row-fn> <defect-fn> <python-old> <python-new>
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

# ── rows ────────────────────────────────────────────────────────────────────────────────────
row_H_selftest() { local d; d=$(mkrow H-selftest); assert_fixture_dir "$d"; run "$d" --self-test
  rc_is "$d" 0 && grep -Fxq 'SOLEUR_RED_ON_MAIN_SELFTEST ok' "$d/out" && nocall "$d"; }
row_H_help() { local d; d=$(mkrow H-help); assert_fixture_dir "$d"; run "$d" --help
  rc_is "$d" 0 && grep -q SOLEUR_RED_ON_MAIN "$d/out" && nocall "$d"; }
row_H_stub_fidelity() { local d rc; d=$(mkrow H-stub); assert_fixture_dir "$d"
  : > "$d/log"
  env FX="$d" STUB_LOG="$d/log" STUB_RUN_ID="$RUN_ID" STUB_WFID="$WFID" "$BIN/gh" api --arg n=x "repos/{owner}/{repo}/actions/runs/$RUN_ID" >/dev/null 2>&1; rc=$?
  [[ "$rc" == 64 ]] && grep -q '^STUB-MISS' "$d/log" \
    || why "invented flag --arg was answered (rc=$rc), not refused"; }
row_R_red() { local d; d=$(mkrow R-red); assert_fixture_dir "$d"; run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 1 && nomiss "$d" && onemarker "$d" \
    && outis "$d" "SOLEUR_RED_ON_MAIN verdict=red-on-main check=\"$CHECK\" main_run=$MAIN_NEW main_conclusion=failure"; }
row_R_conclusions() { local d
  # startup_failure is red: the runner never measured the job but the run IS broken.
  d=$(mkrow R-concl-startup); assert_fixture_dir "$d"; setjob "$d" "$MAIN_NEW" startup_failure
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 1 && nomiss "$d" && verdict "$d" red-on-main || return 1
  # stale / action_required are NOT evidence -- the job produced no verdict on code, so the
  # scan falls through to the older run (which did fail) rather than verdicting on them.
  local c
  for c in stale action_required; do
    d=$(mkrow "R-concl-$c"); assert_fixture_dir "$d"
    setjob "$d" "$MAIN_NEW" "$c"; setjob "$d" "$MAIN_OLD" failure
    run "$d" "$CHECK" --run-id "$RUN_ID"
    rc_is "$d" 1 && nomiss "$d" \
      && outis "$d" "SOLEUR_RED_ON_MAIN verdict=red-on-main check=\"$CHECK\" main_run=$MAIN_OLD main_conclusion=failure" || return 1
  done; }
row_R_query_shape() { local d; d=$(mkrow R-query); assert_fixture_dir "$d"
  # The window query and the paginated jobs call are the contract: a drifted branch filter or
  # a dropped --paginate silently reads the wrong evidence (a >100-job run truncates to page 1).
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 1 && nomiss "$d" \
    && logs "$d" "runs?branch=main&status=completed&per_page=5" \
    && logs "$d" "api --paginate" || return 1
  # Two concatenated page objects (the --paginate output shape): the leg on page 2 must be found.
  d=$(mkrow R-twopage); assert_fixture_dir "$d"
  printf '%s\n%s\n' \
    '{"total_count":150,"jobs":[{"id":1,"run_id":9101,"name":"deploy-script-tests","status":"completed","conclusion":"success"}]}' \
    '{"total_count":150,"jobs":[{"id":2,"run_id":9101,"name":"deploy-script-tests (1/4)","status":"completed","conclusion":"failure"}]}' \
    > "$d/jobs.$MAIN_NEW.json"
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 1 && nomiss "$d" && verdict "$d" red-on-main; }
row_R_report_dedupe_oldest() { local d; d=$(mkrow R-dedupe-old); assert_fixture_dir "$d"
  # TWO sentinel carriers, newest first in the list payload: the comment must land on the
  # OLDEST (#33), or the older tracker orphans forever.
  setissues "$d" "$(jq -nc --arg b "$SENT_BODY" '[{"number":55,"body":$b},{"number":33,"body":$b}]')"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 1 && nomiss "$d" && verdict "$d" red-on-main \
    && logs "$d" "issue comment 33 " && nologs "$d" "issue comment 55" \
    && nologs "$d" "issue create" && onemarker "$d"; }
row_R_green() { local d c
  for c in success neutral; do
    d=$(mkrow "R-green-$c"); assert_fixture_dir "$d"; setjob "$d" "$MAIN_NEW" "$c"
    run "$d" "$CHECK" --run-id "$RUN_ID"
    rc_is "$d" 0 && nomiss "$d" && onemarker "$d" \
      && outis "$d" "SOLEUR_RED_ON_MAIN verdict=green-on-main check=\"$CHECK\" main_run=$MAIN_NEW main_conclusion=$c" || return 1
  done; }
row_R_windowed() { local d; d=$(mkrow R-windowed); assert_fixture_dir "$d"
  # Skipped in the NEWEST run (path-filtered push), failed in the older one: the verdict must come
  # from the older run -- skipped is not evidence, it just says the job did not run there.
  setjob "$d" "$MAIN_NEW" skipped; setjob "$d" "$MAIN_OLD" failure
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 1 && nomiss "$d" \
    && outis "$d" "SOLEUR_RED_ON_MAIN verdict=red-on-main check=\"$CHECK\" main_run=$MAIN_OLD main_conclusion=failure"; }
row_R_no_evidence() { local d; d=$(mkrow R-noev); assert_fixture_dir "$d"
  setjob "$d" "$MAIN_NEW" ABSENT; setjob "$d" "$MAIN_OLD" ABSENT
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 2 && nomiss "$d" && onemarker "$d" \
    && outis "$d" "SOLEUR_RED_ON_MAIN verdict=no-evidence check=\"$CHECK\" main_run=none main_conclusion=none" || return 1
  # skipped in EVERY run is also not evidence.
  d=$(mkrow R-noev-skipped); assert_fixture_dir "$d"
  setjob "$d" "$MAIN_NEW" skipped; setjob "$d" "$MAIN_OLD" skipped
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 2 && nomiss "$d" && verdict "$d" no-evidence; }
row_R_exact_name() { local d; d=$(mkrow R-exact); assert_fixture_dir "$d"
  # Only the matrix PARENT `deploy-script-tests` ran on main -- never the (1/4) leg. A prefix
  # match would read the parent's green as the leg's green; exact-name says no-evidence.
  setjob "$d" "$MAIN_NEW" ABSENT; setjob "$d" "$MAIN_OLD" ABSENT
  run "$d" "deploy-script-tests" --run-id "$RUN_ID"
  rc_is "$d" 0 && nomiss "$d" && verdict "$d" green-on-main || return 1
  d=$(mkrow R-exact2); assert_fixture_dir "$d"
  setjob "$d" "$MAIN_NEW" success; setjob "$d" "$MAIN_OLD" success
  run "$d" "deploy-script-tests (2/4)" --run-id "$RUN_ID"
  rc_is "$d" 2 && nomiss "$d" && verdict "$d" no-evidence; }
row_R_no_main_runs() { local d; d=$(mkrow R-nomain); assert_fixture_dir "$d"
  printf '{"total_count":0,"workflow_runs":[]}\n' > "$d/wfruns.json"
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 2 && nomiss "$d" && verdict "$d" no-evidence; }
row_R_window_cap() { local d; d=$(mkrow R-cap); assert_fixture_dir "$d"
  # SIX completed main runs; only the 6th (outside the window) exercised the check. The probe
  # must NOT read past 5 -- a 6th-run jobs request is a stub miss AND the verdict is no-evidence.
  printf '{"total_count":6,"workflow_runs":[{"id":9106},{"id":9105},{"id":9104},{"id":9103},{"id":9102},{"id":9101}]}\n' > "$d/wfruns.json"
  local r; for r in 9106 9105 9104 9103 9102; do setjob "$d" "$r" ABSENT; done
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 2 && nomiss "$d" && verdict "$d" no-evidence && nologs "$d" "runs/9101/jobs"; }
row_R_gh_error() { local d; d=$(mkrow R-err-run); assert_fixture_dir "$d"; touch "$d/run.fail"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && nologs "$d" "issue create" || return 1
  d=$(mkrow R-err-wf); assert_fixture_dir "$d"; touch "$d/wfruns.fail"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && nologs "$d" "issue create" || return 1
  d=$(mkrow R-err-jobs); assert_fixture_dir "$d"; touch "$d/jobs.$MAIN_NEW.fail"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && nologs "$d" "issue create"; }
row_R_cancelled() { local d; d=$(mkrow R-cancelled); assert_fixture_dir "$d"; setjob "$d" "$MAIN_NEW" cancelled
  run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 1 && nomiss "$d" \
    && outis "$d" "SOLEUR_RED_ON_MAIN verdict=red-on-main check=\"$CHECK\" main_run=$MAIN_NEW main_conclusion=cancelled"; }
row_R_malformed() { local d; d=$(mkrow R-malformed); assert_fixture_dir "$d"
  printf '{unterminated garbage from a 502 page' > "$d/jobs.$MAIN_NEW.json"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 3 && nomiss "$d" && verdict "$d" error && nologs "$d" "issue create"; }
row_R_report_dedupe() { local d; d=$(mkrow R-dedupe); assert_fixture_dir "$d"
  setissues "$d" "$(jq -nc --arg b "$SENT_BODY" '[{"number":55,"body":$b},{"number":88,"body":"human-filed tracker, no sentinel"}]')"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 1 && nomiss "$d" && verdict "$d" red-on-main \
    && logs "$d" "issue list" && logs "$d" "issue comment 55 " \
    && nologs "$d" 'in:body' \
    && nologs "$d" "issue create" && nologs "$d" "issue close" && nologs "$d" "issue comment 88" \
    && outis "$d" "SOLEUR_RED_ON_MAIN verdict=red-on-main check=\"$CHECK\" main_run=$MAIN_NEW main_conclusion=failure"; }
row_R_report_files() { local d; d=$(mkrow R-files); assert_fixture_dir "$d"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 1 && nomiss "$d" && verdict "$d" red-on-main \
    && logs "$d" "label create ci/main-broken --force" \
    && logs "$d" "issue create" && logs "$d" '--milestone Post-MVP / Later' \
    && logs "$d" "--label ci/main-broken" && logs "$d" "--label meta/machinery" && logs "$d" "--label type/chore" \
    && logs "$d" 'soleur:red-on-main check="deploy-script-tests (1/4)"'; }
row_R_report_close_green() { local d; d=$(mkrow R-close); assert_fixture_dir "$d"
  setjob "$d" "$MAIN_NEW" success
  setissues "$d" "$(jq -nc --arg b "$SENT_BODY" '[{"number":55,"body":$b},{"number":77,"body":"x <!-- soleur:red-on-main check=\"other-check (2/4)\" -->"},{"number":88,"body":"human-filed tracker, no sentinel"}]')"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 0 && nomiss "$d" && verdict "$d" green-on-main \
    && logs "$d" "issue close 55 " && nologs "$d" "issue close 77" && nologs "$d" "issue close 88" \
    && nologs "$d" "issue create" && onemarker "$d"; }
row_R_report_nonsentinel() { local d; d=$(mkrow R-nonsentinel); assert_fixture_dir "$d"
  setjob "$d" "$MAIN_NEW" success
  # A human-filed tracker whose body NAMES the check but carries no sentinel is never closed.
  setissues "$d" '[{"number":88,"body":"deploy-script-tests (1/4) is broken on main, tracking manually"}]'
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 0 && nomiss "$d" && verdict "$d" green-on-main \
    && nologs "$d" "issue close" && nologs "$d" "issue comment" && nologs "$d" "issue create"; }
row_R_report_list_fail() { local d; d=$(mkrow R-listfail); assert_fixture_dir "$d"
  touch "$d/issues.fail"
  run "$d" "$CHECK" --run-id "$RUN_ID" --report
  rc_is "$d" 1 && verdict "$d" red-on-main \
    && nologs "$d" "issue create" && nologs "$d" "label create" \
    && grep -q 'could not list' "$d/err" || why "list-failure arm: out=$(cat "$d/out") err=$(cat "$d/err") log=$(cat "$d/log")"; }
row_R_usage() { local d a
  for a in "" "$CHECK" "$CHECK --run-id" "$CHECK --run-id abc" "$CHECK --run-id $RUN_ID --bogus" "$CHECK --run-id $RUN_ID --repo not-a-repo"; do
    d=$(mkrow R-usage); assert_fixture_dir "$d"
    # shellcheck disable=SC2086
    run "$d" $a; rc_is "$d" 3 && verdict "$d" error && nocall "$d" || return 1
  done
  # Check names that would break the marker/sentinel format or carry terminal-forging
  # control bytes (check names are PR-author-controlled) are refused before any gh call.
  for a in 'bad"name' 'bad-->name' $'bad\tname' $'bad\x1b[31mname' $'bad\x7fname'; do
    d=$(mkrow R-usage); assert_fixture_dir "$d"
    run "$d" "$a" --run-id "$RUN_ID"; rc_is "$d" 3 && verdict "$d" error && nocall "$d" || return 1
  done; }
row_R_missing_tool() { local d; d=$(mkrow R-missing); assert_fixture_dir "$d"
  RUN_PATH="$NOGH" run "$d" "$CHECK" --run-id "$RUN_ID"
  rc_is "$d" 3 && verdict "$d" error; }
row_R_repo_flag() { local d; d=$(mkrow R-repo); assert_fixture_dir "$d"
  run "$d" "$CHECK" --run-id "$RUN_ID" --repo acme/widgets --report
  rc_is "$d" 1 && nomiss "$d" \
    && logs "$d" "repos/acme/widgets/actions/runs/$RUN_ID" \
    && logs "$d" "repos/acme/widgets/actions/workflows/$WFID/runs" \
    && logs "$d" "--repo acme/widgets"; }

# defect probes for the mutation rows: the mutant must show the defect, not merely crash.
dfx_no_evidence_green()  { [[ "$(rc_of R-noev-skipped)" == 0 ]]; }
dfx_no_evidence_red()    { [[ "$(rc_of R-noev)" == 1 ]]; }
dfx_windowed_lost()      { [[ "$(rc_of R-windowed)" == 2 ]]; }
dfx_filed_on_listfail()  { grep -q "issue create" "$(rowdir R-listfail)/log"; }
dfx_closed_nonsentinel() { grep -q "issue close 88" "$(rowdir R-nonsentinel)/log"; }
dfx_unpaginated()        { ! grep -q -- "--paginate" "$(rowdir R-query)/log"; }
dfx_newest_first()       { grep -q "issue comment 55" "$(rowdir R-dedupe-old)/log"; }

echo "== check-red-on-main.sh (Guard 1)"
for r in H_selftest H_help H_stub_fidelity R_red R_green R_conclusions R_query_shape \
         R_windowed R_no_evidence R_exact_name \
         R_no_main_runs R_window_cap R_gh_error R_cancelled R_malformed \
         R_report_dedupe R_report_dedupe_oldest R_report_files R_report_close_green \
         R_report_nonsentinel R_report_list_fail \
         R_usage R_missing_tool R_repo_flag; do
  case_ok "$r" "row_$r"
done

echo "== mutation rows"
# M1 -- `skipped` treated as evidence: a path-filtered skip becomes a verdict-bearing conclusion.
case_mutant M1-skipped-evidence row_R_no_evidence dfx_no_evidence_green \
  '"completed success"|"completed neutral")' '"completed success"|"completed neutral"|"completed skipped")'
# M2 -- absent treated as red: a job nobody ran on main quarantines the check.
case_mutant M2-absent-is-red row_R_no_evidence dfx_no_evidence_red \
  'then "ABSENT -"' 'then "completed failure"'
# M3 -- window shrinks to the newest run only: skipped-in-newest + failed-in-older reads no-evidence.
case_mutant M3-window-of-one row_R_windowed dfx_windowed_lost \
  '.workflow_runs[:5]' '.workflow_runs[:1]'
# M4 -- the list-failure guard is removed wholesale: a transient `issue list` error files a
# duplicate. The WHOLE compound condition must go -- dropping only the rc half leaves the
# shape half still guarding (an empty body fails `type == "array"`), which is a crash-kill.
case_mutant M4-file-on-listfail row_R_report_list_fail dfx_filed_on_listfail \
  'if [[ "$rc" -ne 0 ]] || ! jq -e '\''type == "array"'\'' <<<"$open_json" >/dev/null 2>&1; then' \
  'if false; then'
# M5 -- the closer drops the sentinel filter: human-filed trackers get closed on a green verdict.
case_mutant M5-close-nonsentinel row_R_report_nonsentinel dfx_closed_nonsentinel \
  '[.[] | select(.body | type == "string" and contains($s)) | .number] | sort | .[]' \
  '[.[] | .number] | sort | .[]'
# M6 -- --paginate dropped: a >100-job run silently reads page 1 only. The row proves the
# jobs call went out WITHOUT the flag.
case_mutant M6-unpaginated row_R_query_shape dfx_unpaginated \
  'gh api --paginate "$RP/actions/runs/$rid/jobs?per_page=100"' \
  'gh api "$RP/actions/runs/$rid/jobs?per_page=100"'
# M7 -- dedupe comments on the NEWEST tracker: the older sentinel issue orphans forever.
case_mutant M7-newest-first row_R_report_dedupe_oldest dfx_newest_first \
  'contains($s)) | .number] | sort | .[0] // empty' \
  'contains($s)) | .number] | .[0] // empty'

# ── anti-vacuity accounting ──────────────────────────────────────────────────────────────────
echo
echo "cases_run=$CASES_RUN passes=$passes fails=$fails ledger=${#FAILED[@]}"
_min_cases=31
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
echo "check-red-on-main: all $passes cases passed"
