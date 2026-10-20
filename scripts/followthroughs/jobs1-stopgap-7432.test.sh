#!/usr/bin/env bash
# jobs1-stopgap-7432.test.sh — Guard 2 for #7432 (Item I of #9217): drives the soak probe through a strict fake `gh`
# and pins its exit-code contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED, 78 xtrace
# refusal), with kill rows against mutated COPIES of the probe. An exit-code contract nothing drives is a comment.
#
# The fake `gh` accepts EXACTLY the argv the probe is modeled to send (exact arity on every branch) and exits 64 on
# anything else, logging the refusal to $FX/refused.log; every row asserts that log is empty (or, for a kill row,
# non-empty). It also models the real gh 2.102 refusal: the job-log endpoint exits 1 with "the response contains
# terminal escape sequences" unless `--allow-escape-sequences` is passed, and every fixture log carries an ESC byte,
# as every real monitor log does. Without that, the probe's log fetch could be wrong in production and green here.
# Fixtures are synthesized (run ids are 9xxxx, plus the two real judged ids the committed probe pins at R4b4; the
# tracker number is the real #7432 only because the probe names it).
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
export TZ=UTC
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/jobs1-stopgap-7432.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/main-health-monitor.yml"
RUNNER="$REPO_ROOT/apps/web-platform/infra/run-registered-suites.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/jobs1-soak.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

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
assert_fixture_dir "$TMP"

passes=0; fails=0; asserted=0
FAILURES=()
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }

# instrument self-test: both helpers must move their counters
_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass "self-test" >/dev/null; fail "self-test" >/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  echo "[FATAL] instrument self-test: pass()/fail() did not each record"; exit 1
fi
passes=0; fails=0; asserted=0; FAILURES=()

START="2026-11-01T00:00:00Z"
START_EPOCH="$(date -u -d "$START" +%s)"
isoat() { date -u -d "@$((START_EPOCH + $1))" +%Y-%m-%dT%H:%M:%SZ; }   # <seconds after the window start>

# --- the strict fake gh ----------------------------------------------------------------------------------------------------
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
refuse() { printf 'REFUSED %s\n' "$*" >> "$FX/refused.log"; exit 64; }
R=jikig-ai/soleur
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  # gh run list -R R --workflow W --branch main --limit 200 --created ">=START" --json F   (nothing else)
  [ $# -eq 14 ] || refuse "$@"
  [ "$3" = "-R" ] && [ "$4" = "$R" ] && [ "$5" = "--workflow" ] && [ "$6" = "main-health-monitor.yml" ] || refuse "$@"
  [ "$7" = "--branch" ] && [ "$8" = "main" ] && [ "$9" = "--limit" ] && [ "${10}" = "200" ] || refuse "$@"
  [ "${11}" = "--created" ] && [ "${13}" = "--json" ] && [ "${14}" = "databaseId,status,conclusion,createdAt,event" ] || refuse "$@"
  case "${12}" in ">="*) since="${12#>=}" ;; *) refuse "$@" ;; esac
  [ -f "$FX/fail-runs" ] && { echo "gh: HTTP 500" >&2; exit 1; }
  [ -f "$FX/runs-raw" ] && { cat "$FX/runs-raw"; exit 0; }
  jq -c --arg s "$since" '[.[] | select(.createdAt >= $s)] | sort_by(.createdAt) | reverse | .[0:200]' "$FX/runs.json"
  exit 0
fi
[ "$1" = "api" ] || refuse "$@"
if [ "$2" = "--allow-escape-sequences" ]; then
  # the ONLY flagged call: the job log, exactly `gh api --allow-escape-sequences repos/R/actions/jobs/<id>/logs`
  [ $# -eq 3 ] || refuse "$@"
  case "$3" in
    "repos/$R/actions/jobs/"*"/logs")
      jid="${3#repos/$R/actions/jobs/}"; jid="${jid%%/*}"
      [ -f "$FX/log-$jid.txt" ] || { echo "gh: HTTP 404" >&2; exit 1; }
      cat "$FX/log-$jid.txt"; exit 0 ;;
  esac
  refuse "$@"
fi
ep="$2"
case "$ep" in
  "repos/$R/contents/.github/workflows/main-health-monitor.yml?ref=main")
    [ "$3" = "--jq" ] && [ "$4" = ".content" ] && [ $# -eq 4 ] || refuse "$@"
    [ -f "$FX/fail-contents" ] && { echo "gh: HTTP 502" >&2; exit 1; }
    base64 -w0 "$FX/workflow.txt"; echo; exit 0 ;;
  "repos/$R/actions/runs/"*"/jobs?per_page=100")
    [ $# -eq 2 ] || refuse "$@"
    rid="${ep#repos/$R/actions/runs/}"; rid="${rid%%/*}"
    [ -f "$FX/jobs-$rid.json" ] || { echo "gh: HTTP 404" >&2; exit 1; }
    cat "$FX/jobs-$rid.json"; exit 0 ;;
  "repos/$R/check-runs/"*"/annotations?per_page=100")
    [ $# -eq 2 ] || refuse "$@"
    jid="${ep#repos/$R/check-runs/}"; jid="${jid%%/*}"
    [ -f "$FX/ann-$jid.json" ] || { echo "gh: HTTP 404" >&2; exit 1; }
    cat "$FX/ann-$jid.json"; exit 0 ;;
  "repos/$R/actions/jobs/"*"/logs")
    # real gh 2.102 refuses a body that carries ESC bytes unless the flag is passed; an ESC-free body is served
    [ $# -eq 2 ] || refuse "$@"
    jid="${ep#repos/$R/actions/jobs/}"; jid="${jid%%/*}"
    [ -f "$FX/log-$jid.txt" ] || { echo "gh: HTTP 404" >&2; exit 1; }
    if LC_ALL=C grep -q "$(printf '\033')" "$FX/log-$jid.txt"; then
      echo "the response contains terminal escape sequences; pass --allow-escape-sequences to output it anyway" >&2
      exit 1
    fi
    cat "$FX/log-$jid.txt"; exit 0 ;;
esac
refuse "$@"
FAKE
chmod +x "$TMP/bin/gh"

# --- fixture builders ------------------------------------------------------------------------------------------------------
# new_fx: a fresh fixture dir with a compliant workflow (exactly one JOBS assignment, in the tests step) and no runs
new_fx() {
  FX="$TMP/fx.$1"; assert_fixture_dir "$FX"; rm -rf "$FX"; mkdir -p "$FX"
  export FX
  printf '%s\n' 'name: main-health-monitor' '# JOBS: 1 in a whole-line comment is not an assignment' 'jobs:' '  health-check:' '    steps:' \
    '      - name: Run test suite' '        id: tests' '        env:' '          JOBS: 1' '      - name: Run infra suites' '        id: infra' '        env:' '          TEST_GROUP: infra' > "$FX/workflow.txt"
  echo '[]' > "$FX/runs.json"
}
# mkrun <rid> <offset s> <status> <conclusion> <infra: success|failure|skipped|cancelled|ABSENT> <timeout 0|1> [red suite...]
# knobs read from the environment and UNSET after each call (so a knob never leaks into the next fixture):
#   MK_K (default 4; "none" omits the width line)  MK_DUPK=1 (a second width line)  MK_ELAPSED (default 1, or 0 when timeout=1)
#   MK_UNACC=1 (the real shape: an UNACCOUNTED line AND unaccounted=1 in the tally)  MK_UNACCLINE=1 (the line only)  MK_SUMU=1 (the tally only)
#   MK_UNACC_PRE=1 (an UNACCOUNTED line BEFORE the infra env dump, outside the slice)  MK_SUMMARY=none (no tally line)  MK_SUMF=<n> (failed count)
#   MK_SUMDUP=1 (the tally twice)  MK_DECOY=1 (SOLEUR|-prefixed look-alike tally and width lines)  MK_JOBDECOY=1 (a non-health-check job FIRST)
#   MK_ANNDECOY=1 (an annotation with another title, saying infra=success, FIRST)  MK_NOESC=1 (a log with no ESC byte)  MK_TESTTMO=1 (the tests-step timeout annotation, a decoy)
#   MK_MSG (the whole outcome message)  MK_ANN2=1 (a second valid outcome annotation)  MK_NOLOG / MK_NOJOBS / MK_NOHC=1
mkrun() {
  local rid="$1" off="$2" st="$3" concl="$4" infra="$5" to="$6"; shift 6
  local jid=$((rid + 1000)) created el k msg; created="$(isoat "$off")"
  k="${MK_K-4}"; el="${MK_ELAPSED-$([ "$to" = 1 ] && echo 0 || echo 1)}"
  jq -c --argjson id "$rid" --arg c "$created" --arg s "$st" --arg k "$concl" \
    '. + [{databaseId:$id, createdAt:$c, status:$s, conclusion:$k, event:"workflow_dispatch"}]' "$FX/runs.json" > "$FX/runs.tmp" && mv "$FX/runs.tmp" "$FX/runs.json"
  if [ -z "${MK_NOJOBS:-}" ]; then
    if [ -n "${MK_NOHC:-}" ]; then printf '{"jobs":[{"id":%d,"name":"other"}]}\n' "$((jid + 1))" > "$FX/jobs-$rid.json"
    elif [ -n "${MK_JOBDECOY:-}" ]; then printf '{"jobs":[{"id":%d,"name":"other"},{"id":%d,"name":"health-check"}]}\n' "$((jid + 1))" "$jid" > "$FX/jobs-$rid.json"
    else printf '{"jobs":[{"id":%d,"name":"health-check"},{"id":%d,"name":"other"}]}\n' "$jid" "$((jid + 1))" > "$FX/jobs-$rid.json"; fi
  fi
  msg="${MK_MSG-SOLEUR_MAIN_HEALTH tests=failure infra=$infra tests_elapsed_s=100$([ "$el" = 1 ] && echo ' infra_elapsed_s=200')}"
  if [ "$infra" = ABSENT ]; then echo '[]' > "$FX/ann-$jid.json"
  else jq -n --arg m "$msg" '[{title:"main-health-outcomes",message:$m}]' > "$FX/ann-$jid.json"
  fi
  if [ "$to" = 1 ]; then
    jq '. + [{title:"",message:"The action '"'"'Run infra suites'"'"' has timed out after 60 minutes."}]' "$FX/ann-$jid.json" > "$FX/ann.tmp" && mv "$FX/ann.tmp" "$FX/ann-$jid.json"
  fi
  if [ -n "${MK_TESTTMO:-}" ]; then
    jq '. + [{title:"",message:"The action '"'"'Run test suite'"'"' has timed out after 110 minutes."}]' "$FX/ann-$jid.json" > "$FX/ann.tmp" && mv "$FX/ann.tmp" "$FX/ann-$jid.json"
  fi
  if [ -n "${MK_ANNDECOY:-}" ]; then
    jq '[{title:"other-title",message:"SOLEUR_MAIN_HEALTH tests=success infra=success"}] + .' "$FX/ann-$jid.json" > "$FX/ann.tmp" && mv "$FX/ann.tmp" "$FX/ann-$jid.json"
  fi
  if [ -n "${MK_ANN2:-}" ]; then
    jq --arg m "$msg" '. + [{title:"main-health-outcomes",message:$m}]' "$FX/ann-$jid.json" > "$FX/ann.tmp" && mv "$FX/ann.tmp" "$FX/ann-$jid.json"
  fi
  if [ -z "${MK_NOLOG:-}" ]; then
    local nf=$# uacc=0 sf
    { [ -z "${MK_UNACC_PRE:-}" ] || echo "2026-11-01T00:00:10.0000000Z UNACCOUNTED  tests-part-decoy.test.sh"
      echo "2026-11-01T00:00:00.0000000Z RED  apps/web-platform/infra/tests-part-decoy.test.sh"
      echo "2026-11-01T00:00:30.0000000Z Running 1 registered infra suite(s) with -P 1…"
      echo "2026-11-01T00:01:00.0000000Z   TEST_GROUP: infra"
      [ -n "${MK_NOESC:-}" ] || printf '2026-11-01T00:01:10.0000000Z \033[36;1mgroup\033[0m\n'
      [ "$k" = none ] || printf '2026-11-01T00:01:30.0000000Z Running 179 registered infra suite(s) with -P %s…\n' "$k"
      [ -z "${MK_DUPK:-}" ] || printf '2026-11-01T00:01:31.0000000Z Running 179 registered infra suite(s) with -P 4…\n'
      local s; for s in "$@"; do echo "2026-11-01T00:02:00.0000000Z RED  apps/web-platform/infra/$s"; done
      { [ -n "${MK_UNACC:-}" ] || [ -n "${MK_UNACCLINE:-}" ]; } && echo "2026-11-01T00:02:30.0000000Z UNACCOUNTED  some-killed-shim.test.sh"
      { [ -n "${MK_UNACC:-}" ] || [ -n "${MK_SUMU:-}" ]; } && uacc=1
      sf="${MK_SUMF-$nf}"
      [ -z "${MK_DECOY:-}" ] || { echo "2026-11-01T00:02:40.0000000Z SOLEUR| Running 3 registered infra suite(s) with -P 1…"; echo "2026-11-01T00:02:41.0000000Z SOLEUR| === registered infra suites: 0 passed, 5 failed, 0 unaccounted (of 5) ==="; }
      [ "${MK_SUMMARY:-}" = none ] || printf '2026-11-01T00:03:00.0000000Z === registered infra suites: %d passed, %d failed, %d unaccounted (of 179) ===\n' $((179 - sf - uacc)) "$sf" "$uacc"
      [ -z "${MK_SUMDUP:-}" ] || printf '2026-11-01T00:03:01.0000000Z === registered infra suites: %d passed, %d failed, %d unaccounted (of 179) ===\n' $((179 - sf - uacc)) "$sf" "$uacc"
      echo "2026-11-01T00:03:30.0000000Z === done ==="; } > "$FX/log-$jid.txt"
  fi
  unset MK_K MK_DUPK MK_ELAPSED MK_UNACC MK_UNACCLINE MK_SUMU MK_UNACC_PRE MK_SUMMARY MK_SUMF MK_SUMDUP MK_DECOY MK_JOBDECOY MK_ANNDECOY MK_NOESC MK_TESTTMO MK_MSG MK_ANN2 MK_NOLOG MK_NOJOBS MK_NOHC
}
good_runs() { local i; for i in $(seq 1 "$1"); do mkrun $((90000 + i)) $((i * 3600)) completed success success 0; done; }
run_probe() {  # run_probe <probe path> [extra env...]; sets RC and OUT, resets the refused log first
  : > "$FX/refused.log"
  OUT="$(cd "$FX" && env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GH_TOKEN=synthetic SOLEUR_FT_EARLIEST="${EARLIEST-$START}" "${@:2}" bash "$1" 2>&1)"; RC=$?
}
expect() {  # expect <label> <rc> [output substring...]
  local label="$1" want="$2" sub; shift 2
  if [ "$RC" -eq "$want" ]; then pass "$label: exit $want"; else fail "$label: want exit $want, got $RC ($OUT)"; fi
  for sub in "$@"; do
    case "$OUT" in *"$sub"*) pass "$label: output names '$sub'" ;; *) fail "$label: output lacks '$sub' ($OUT)" ;; esac
  done
  if [ -s "$FX/refused.log" ]; then fail "$label: the probe sent a refused argv ($(head -1 "$FX/refused.log"))"; else pass "$label: every gh argv was modeled"; fi
}
expect_not() {  # expect_not <label> <output substring>: the output must NOT carry it
  case "$OUT" in *"$2"*) fail "$1: output must not carry '$2' ($OUT)" ;; *) pass "$1: output does not carry '$2'" ;; esac
}
mutate() {  # mutate <name> <old> <new> [base file]: a mutated COPY (of the probe by default) by exact literal; it must land exactly once. Sets MUT.
  local m="$TMP/mut.$1.sh" base="${4:-$PROBE}"
  if ! python3 - "$base" "$m" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(1)
open(dst, "w").write(s.replace(old, new))
PY
  then fail "mutant $1: the mutation did not land exactly once"; return 1; fi
  if cmp -s "$base" "$m"; then fail "mutant $1: the mutated copy is identical to its base"; return 1; fi
  MUT="$m"
}
kill_row() {  # kill_row <label> <want rc of the mutant>: RC (from the mutant) must be exactly the stated one
  if [ "$RC" -eq "$2" ]; then pass "$1 (mutant exit $2)"; else fail "$1: the mutant exited $RC, want $2 ($OUT)"; fi
}

# helper self-test: expect/expect_not/kill_row/mutate each own a verdict and pass()/fail() cannot vouch for them. Drive each with an
# input that MUST fail and require exactly one recorded failure, then with a good input and require none; unwind every counter so the
# floor below stays exact. Reported with printf + exit, never through the helpers under test.
_selftest_helpers() {
  local p0=$passes f0=$fails a0=$asserted n0=${#FAILURES[@]} d
  FX="$TMP/fx.selftest"; assert_fixture_dir "$FX"; mkdir -p "$FX"; : > "$FX/refused.log"
  _must_fail() {  # _must_fail <name>: the fails counter must have moved by exactly one since the snapshot in $d
    if [ $((fails - d)) -ne 1 ]; then printf '[FATAL] helper self-test: %s did not record exactly one failure for a wrong input\n' "$1" >&2; exit 1; fi
  }
  RC=1; OUT="abc"
  d=$fails; expect "selftest" 0 >/dev/null; _must_fail "expect (rc compare)"
  RC=0; OUT="abc"; d=$fails; expect "selftest" 0 "zzz" >/dev/null; _must_fail "expect (substring)"
  RC=0; OUT="abc"; echo REFUSED > "$FX/refused.log"; d=$fails; expect "selftest" 0 >/dev/null; _must_fail "expect (refused.log)"; : > "$FX/refused.log"
  OUT="abc"; d=$fails; expect_not "selftest" "abc" >/dev/null; _must_fail "expect_not"
  RC=1; d=$fails; kill_row "selftest" 0 >/dev/null; _must_fail "kill_row"
  d=$fails; mutate selftest-absent 'THIS-LITERAL-IS-NOT-IN-THE-PROBE' 'x' >/dev/null; _must_fail "mutate (absent literal)"
  d=$fails; mutate selftest-many 'set ' 'x' >/dev/null; _must_fail "mutate (literal not unique)"
  d=$fails; mutate selftest-same 'N=12' 'N=12' >/dev/null; _must_fail "mutate (identical copy)"
  # and the good inputs must record no failure
  RC=0; OUT="abc"; d=$fails; expect "selftest" 0 "abc" >/dev/null; [ "$fails" -eq "$d" ] || { printf '[FATAL] helper self-test: expect failed a good input\n' >&2; exit 1; }
  RC=0; d=$fails; kill_row "selftest" 0 >/dev/null; [ "$fails" -eq "$d" ] || { printf '[FATAL] helper self-test: kill_row failed a good input\n' >&2; exit 1; }
  d=$fails; mutate selftest-ok 'N=12' 'N=11' >/dev/null; [ "$fails" -eq "$d" ] || { printf '[FATAL] helper self-test: mutate failed a good input\n' >&2; exit 1; }
  passes=$p0; fails=$f0; asserted=$a0; FAILURES=("${FAILURES[@]:0:$n0}")
}
_selftest_helpers

[ -r "$PROBE" ] || { echo "[FATAL] probe not found at $PROBE"; exit 1; }

# R0 control: 12 clean runs at the default width, one JOBS assignment on main
new_fx r0; good_runs 12; run_probe "$PROBE"; expect "R0 12 clean runs" 0 "-P 4"
# R1 the infra pin is still on main -> NOT YET, never 0 (bare and QUOTED keys both count)
new_fx r1a; good_runs 12; printf '%s\n' '        env:' '          JOBS: 1' >> "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1a infra pin still on main" 2
new_fx r1b; good_runs 12; printf '%s\n' '        env:' '          "JOBS": 1' >> "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1b a double-quoted JOBS key counts as a pin" 2
new_fx r1c; good_runs 12; printf '%s\n' '        env:' "          'JOBS': 1" >> "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1c a single-quoted JOBS key counts as a pin" 2
# R2 fewer than 12 runs; bad runs before the window start are ignored; a bad run exactly at the start is counted
new_fx r2a; good_runs 11; run_probe "$PROBE"; expect "R2a 11 clean runs" 2
new_fx r2b; good_runs 12; mkrun 90100 -1 completed success failure 1; run_probe "$PROBE"; expect "R2b a ceiling kill one second BEFORE the window start is ignored" 0
new_fx r2c; good_runs 11; mkrun 90101 0 completed success failure 1; run_probe "$PROBE"; expect "R2c a ceiling kill exactly AT the window start is counted" 1 90101
# R3 two ceiling kills among 12 -> exit 1 naming both
new_fx r3; mkrun 90001 3600 completed success success 0; mkrun 90002 7200 completed success failure 1; mkrun 90003 10800 completed success failure 1; for i in $(seq 4 12); do mkrun $((90000 + i)) $((i * 3600)) completed success success 0; done
run_probe "$PROBE"; expect "R3 two ceiling kills" 1 90002 90003
# R4 classification and precedence
new_fx r4a; good_runs 9; mkrun 90020 40000 completed success failure 0 some-other.test.sh; mkrun 90022 40500 completed success failure 0 another.test.sh; mkrun 90021 41000 completed success failure 1
run_probe "$PROBE"; expect "R4a TWO strikes AND a ceiling kill: the kill wins" 1 90021
new_fx r4b; good_runs 11; mkrun 90030 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh some-other.test.sh
run_probe "$PROBE"; expect "R4b ONE strike is tolerated, and the PASS line names it" 0 "Tolerated strike(s): 90030(some-other.test.sh)"
new_fx r4b2; good_runs 10; mkrun 90030 40000 completed success failure 0 some-other.test.sh; mkrun 90031 41000 completed success failure 0 another.test.sh
run_probe "$PROBE"; expect "R4b2 TWO strikes need a person" 5 90030 90031 some-other.test.sh another.test.sh
new_fx r4b3; good_runs 10; mkrun 90030 40000 completed success failure 0 some-other.test.sh; mkrun 90031 41000 completed success failure 0 another.test.sh
mutate judged 'JUDGED_REPRODUCING_RUNS="39378082716 39446197504"' 'JUDGED_REPRODUCING_RUNS="90030 90031"' && { run_probe "$MUT"; expect "R4b3 two strikes both judged reproducing by a committed id list" 0 "Judged-reproducing run(s): 90030 90031"; }
new_fx r4b4; good_runs 10; mkrun 39378082716 40000 completed success failure 0 git-data-wipe-assert.test.sh; mkrun 39446197504 41000 completed success failure 0 git-data-wipe-assert.test.sh
run_probe "$PROBE"; expect "R4b4 the committed judged ids are honoured by the un-mutated probe" 0 "Judged-reproducing run(s): 39378082716 39446197504"
new_fx r4c; good_runs 11; mkrun 90032 40000 completed success failure 0
run_probe "$PROBE"; expect "R4c infra=failure with no RED line at all is a measurement defect" 5 90032
new_fx r4d; good_runs 11; mkrun 90033 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4d an allowlisted-RED-only run reads clean, through the flagged log fetch" 0 "Allowlisted tag-drift RED in run(s): 90033"
new_fx r4e; good_runs 11; MK_UNACC=1 mkrun 90034 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e an allowlisted RED plus UNACCOUNTED lines (the OOM-killed-shim shape) is NOT clean" 5 90034
new_fx r4f; good_runs 11; mkrun 90035 40000 completed success skipped 0; run_probe "$PROBE"; expect "R4f infra=skipped (the step never ran) is not clean" 5 90035
new_fx r4g; good_runs 11; mkrun 90036 40000 completed success cancelled 0; run_probe "$PROBE"; expect "R4g infra=cancelled is not clean" 5 90036
new_fx r4h; for i in $(seq 1 12); do MK_TESTTMO=1 mkrun $((91000 + i)) $((i * 3600 + 100)) completed success success 0; done
run_probe "$PROBE"; expect "R4h the TESTS-step timeout annotation is not an infra ceiling kill (12 clean runs that all carry it)" 0
new_fx r4i; good_runs 10; mkrun 90037 40000 completed success failure 0 inngest-bootstrap.test.sh; mkrun 90038 41000 completed success failure 0 x-cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4i a suffix and a superstring of the allowlisted name are NOT the allowlisted suite" 5 90037 90038
new_fx r4j; good_runs 10; mkrun 90039 40000 completed success failure 0 'x@mention.test.sh'; mkrun 90040 41000 completed success failure 0 other.test.sh
run_probe "$PROBE"; expect "R4j a RED name outside a plain path alphabet is replaced before it reaches a public comment" 5 "<unsafe-name>"
expect_not "R4j" "x@mention"
new_fx r4k; good_runs 11; MK_ELAPSED=0 mkrun 90041 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4k infra=failure with NO infra_elapsed_s and no timeout annotation is a kill that lost its annotation" 1 90041
new_fx r4l; good_runs 11; mkrun 90060 40000 completed success failure 0 foo.test.sh bar.test.sh
run_probe "$PROBE"; expect "R4l ONE run holding TWO non-allowlisted REDs is two strikes, not one" 5 90060 foo.test.sh bar.test.sh
new_fx r4l2; good_runs 11; MK_MSG="SOLEUR_MAIN_HEALTH tests=failure infra=failure infra_elapsed_s=" mkrun 90061 40000 completed success failure 0 other.test.sh
run_probe "$PROBE"; expect "R4l2 an EMPTY infra_elapsed_s token is not a number: the step did not complete" 1 90061
new_fx r4n; good_runs 11; MK_ELAPSED=1 mkrun 90062 40000 completed success failure 1 other.test.sh
run_probe "$PROBE"; expect "R4n the infra timeout annotation kills even when infra_elapsed_s is present" 1 90062
new_fx r4o; good_runs 11; MK_ELAPSED=1 mkrun 90063 40000 completed success success 1
run_probe "$PROBE"; expect "R4o the infra timeout annotation kills even when the verdict token says success" 1 90063
new_fx r4p; good_runs 10; mkrun 90064 40000 completed success failure 0 a_b/c_d.test.sh; mkrun 90065 41000 completed success failure 0 e.test.sh
run_probe "$PROBE"; expect "R4p a RED name with an underscore and a slash is a plain path, not an unsafe name" 5 a_b/c_d.test.sh
new_fx r4q; good_runs 10; mkrun 90030 40000 completed success failure 0 some-other.test.sh; mkrun 90032 41000 completed success failure 0 another.test.sh
mutate judged2 'JUDGED_REPRODUCING_RUNS="39378082716 39446197504"' 'JUDGED_REPRODUCING_RUNS="900301"' && { run_probe "$MUT"; expect "R4q a judged id that merely CONTAINS a run id (900301 vs 90030) judges nothing" 5 90030 90032; }
# accounting: the runner's own tally is the proof
new_fx r4e2; good_runs 11; MK_UNACCLINE=1 mkrun 90070 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e2 an UNACCOUNTED line alone (the tally says 0) is a measurement defect" 5 90070
new_fx r4e3; good_runs 11; MK_SUMU=1 mkrun 90071 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e3 unaccounted=1 in the tally with no UNACCOUNTED line is a measurement defect" 5 90071
new_fx r4e4; good_runs 11; MK_UNACC_PRE=1 mkrun 90072 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e4 an UNACCOUNTED line BEFORE the infra env dump is outside the slice and is ignored" 0 "Allowlisted tag-drift RED in run(s): 90072"
new_fx r4e5; good_runs 11; MK_SUMMARY=none mkrun 90073 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e5 an infra=failure run with no runner tally line cannot be a clean allowlisted run" 5 90073
new_fx r4e6; good_runs 11; MK_SUMF=0 mkrun 90074 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e6 a tally that counts fewer failures than there are RED lines (a forged RED line) is a measurement defect" 5 90074
new_fx r4e7; good_runs 11; MK_SUMDUP=1 mkrun 90076 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e7 a log carrying the runner's tally TWICE is a measurement defect (exactly one is required)" 5 90076
new_fx r4e8; good_runs 11; MK_DECOY=1 mkrun 90077 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
run_probe "$PROBE"; expect "R4e8 SOLEUR|-prefixed look-alike tally and width lines inside a suite excerpt change nothing" 0 "Allowlisted tag-drift RED in run(s): 90077"
new_fx r4r; good_runs 11; mkrun 90078 40000 completed success failure 0 '*'
run_probe "$PROBE"; expect "R4r a RED name of * is ONE strike named <unsafe-name>, never expanded against the working directory" 0 "Tolerated strike(s): 90078(<unsafe-name>)"
new_fx r4s; good_runs 11; MK_JOBDECOY=1 mkrun 90079 40000 completed success success 0; run_probe "$PROBE"; expect "R4s the health-check job is picked by NAME, not by position" 0
new_fx r4t; good_runs 11; MK_ANNDECOY=1 mkrun 90080 40000 completed success failure 1; run_probe "$PROBE"; expect "R4t an annotation with another title (saying infra=success) is ignored: the kill still reads" 1 90080
# precedence: every conflict between two verdict classes, so a reordered block cannot stay green
new_fx r10a; good_runs 10; mkrun 90080 40000 completed success skipped 0; mkrun 90081 41000 completed success failure 1
run_probe "$PROBE"; expect "R10a a kill AND a hard failure: the kill wins" 1 90081
new_fx r10b; good_runs 9; mkrun 90082 40000 completed success skipped 0; mkrun 90083 40500 completed success failure 0 foo.test.sh; mkrun 90084 41000 completed success failure 0 bar.test.sh
run_probe "$PROBE"; expect "R10b a hard failure AND two strikes: the hard failure is named" 5 "measurement defect"
expect_not "R10b" "REDs outside the allowlist"
new_fx r10c; good_runs 9; mkrun 90085 40000 completed success ABSENT 0; mkrun 90086 40500 completed success failure 0 foo.test.sh; mkrun 90087 41000 completed success failure 0 bar.test.sh
run_probe "$PROBE"; expect "R10c two strikes AND an unreadable run: the strikes win" 5 "REDs outside the allowlist"
new_fx r10d; good_runs 10; mkrun 90088 40000 completed success ABSENT 0; mkrun 90089 41000 in_progress "" ABSENT 0
run_probe "$PROBE"; expect "R10d an unreadable run AND a still-running run: unreadable wins over not-yet" 3 90088
new_fx r10e; good_runs 10; mkrun 90090 40000 completed success ABSENT 0
run_probe "$PROBE"; expect "R10e an unreadable run among FEWER than 12: unreadable wins over short" 3 90090
# boundaries
new_fx w6; good_runs 11; MK_K=2 mkrun 90091 40000 completed success success 0; run_probe "$PROBE"; expect "W6 -P 2 is the smallest accepted width" 0 "-P 4 2"
new_fx w7; good_runs 11; MK_K=99999999999999999999999 mkrun 90092 40000 completed success success 0; run_probe "$PROBE"; expect "W7 a K that overflows integer comparison is refused, not accepted" 3 90092
new_fx w8; good_runs 11; MK_NOESC=1 mkrun 90093 40000 completed success success 0; run_probe "$PROBE"; expect "W8 a log with no ESC byte (gh serves it unflagged too) reads the same" 0
new_fx r5e2; for i in $(seq 1 199); do mkrun $((80000 + i)) $((i * 60)) completed success success 0; done; run_probe "$PROBE"; expect "R5e2 199 runs is under the 200 limit" 0
new_fx r5p; good_runs 10; jq -c '. + [.[0], .[1]]' "$FX/runs.json" > "$FX/runs.tmp" && mv "$FX/runs.tmp" "$FX/runs.json"; run_probe "$PROBE"; expect "R5p duplicate run ids do not each count as a run" 2
new_fx r1d; good_runs 12; printf '%s\n' '        env:' '          JOBS=2' >> "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1d a JOBS= assignment counts as a pin" 2
new_fx r1e; good_runs 12; printf '%s\n' '        env:' '          MAX_JOBS: 2' >> "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1e MAX_JOBS is not a JOBS assignment" 0
new_fx r1f; good_runs 12; grep -v 'JOBS: 1' "$FX/workflow.txt" > "$FX/w.tmp" && mv "$FX/w.tmp" "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1f a workflow with NO JOBS assignment still passes the read, and says so" 0 "(-P 4; 0 JOBS"
new_fx r1g; good_runs 12; printf 'unrelated: yaml\nJOBS: 1\n' > "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1g a contents body that is not the monitor workflow" 3
new_fx r1h; good_runs 12; : > "$FX/workflow.txt"; run_probe "$PROBE"; expect "R1h an empty contents body" 3
new_fx r1i; good_runs 12; run_probe "$PROBE" GH_TOKEN=; expect "R1i GH_TOKEN unset" 3
new_fx r8b; good_runs 12; : > "$FX/refused.log"
OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GITHUB_TOKEN=synthetic SOLEUR_FT_EARLIEST="$START" bash -x "$PROBE" 2>&1)"; RC=$?
expect "R8b run under xtrace with only GITHUB_TOKEN set" 78
# R5 never 0 on a read it could not make
new_fx r5a; good_runs 11; mkrun 90040 40000 completed success ABSENT 0; run_probe "$PROBE"; expect "R5a a non-cancelled run with no main-health-outcomes annotation" 3
new_fx r5b; good_runs 12; : > "$FX/fail-contents"; run_probe "$PROBE"; expect "R5b a failed contents read" 3
new_fx r5c; good_runs 12; EARLIEST="" run_probe "$PROBE"; expect "R5c SOLEUR_FT_EARLIEST empty" 3
new_fx r5d; good_runs 12; EARLIEST="not-a-date" run_probe "$PROBE"; expect "R5d SOLEUR_FT_EARLIEST not an ISO timestamp" 3
new_fx r5d2; good_runs 12; EARLIEST="2026-13-45T25:61:61Z" run_probe "$PROBE"; expect "R5d2 a well-formed but impossible timestamp is refused, not read as an empty window" 3
new_fx r5e; for i in $(seq 1 200); do mkrun $((80000 + i)) $((i * 60)) completed success success 0; done; run_probe "$PROBE"; expect "R5e a run list that fills the limit" 3
new_fx r5f; good_runs 12; : > "$FX/fail-runs"; run_probe "$PROBE"; expect "R5f a failed run-list read" 3
new_fx r5o; good_runs 12; echo '{}' > "$FX/runs-raw"; run_probe "$PROBE"; expect "R5o a run list that is an object, not an array" 3
new_fx r5g; good_runs 12; rm "$FX/ann-91001.json"; run_probe "$PROBE"; expect "R5g a failed annotation read" 3
new_fx r5h; good_runs 12; echo '[]' > "$FX/ann-91003.json"; run_probe "$PROBE"; expect "R5h an empty annotation list on a counted run" 3
new_fx r5i; good_runs 11; MK_ANN2=1 mkrun 90042 40000 completed success success 0; run_probe "$PROBE"; expect "R5i TWO outcome annotations on one run (first=success must not be trusted)" 3 90042
new_fx r5j; good_runs 11; MK_MSG="something else entirely infra=success" mkrun 90043 40000 completed success success 0; run_probe "$PROBE"; expect "R5j an annotation that does not start SOLEUR_MAIN_HEALTH" 3 90043
new_fx r5k; good_runs 11; MK_MSG="SOLEUR_MAIN_HEALTH tests=failure infra=failure infra=success infra_elapsed_s=5" mkrun 90044 40000 completed success failure 0 other.test.sh; run_probe "$PROBE"; expect "R5k two infra= tokens in one message (last-wins would read success)" 3 90044
new_fx r5l; good_runs 11; MK_NOLOG=1 mkrun 90045 40000 completed success failure 0; run_probe "$PROBE"; expect "R5l a failed job-log read" 3 90045
new_fx r5m; good_runs 11; MK_NOJOBS=1 mkrun 90046 40000 completed success success 0; run_probe "$PROBE"; expect "R5m a failed jobs read" 3 90046
new_fx r5n; good_runs 11; MK_NOHC=1 mkrun 90047 40000 completed success success 0; run_probe "$PROBE"; expect "R5n a run with no health-check job" 3 90047
# W the width proof: read from every counted run's log, BEFORE kill classification
new_fx w1; good_runs 11; MK_K=1 mkrun 90050 40000 completed success success 0; run_probe "$PROBE"; expect "W1 a run that ran at -P 1 (a pinned run inside the window) is unreadable" 3 "90050(width:1)"
new_fx w2; good_runs 11; MK_K=none mkrun 90051 40000 completed success success 0; run_probe "$PROBE"; expect "W2 a run whose log carries no width line" 3 "90051(width:none)"
new_fx w3; good_runs 11; MK_DUPK=1 mkrun 90052 40000 completed success success 0; run_probe "$PROBE"; expect "W3 a run whose log carries two width lines" 3 90052
new_fx w4; good_runs 11; MK_K=1 mkrun 90053 40000 completed success failure 1; run_probe "$PROBE"; expect "W4 a pinned run that was KILLED reads as unreadable, never a false FAIL" 3 "90053(width:1)"
new_fx w5; good_runs 11; MK_K=6 mkrun 90054 40000 completed success success 0; run_probe "$PROBE"; expect "W5 a different default width (-P 6) is recorded, not refused" 0 "-P 4 6"
# R6 monotone: 12 clean then a later bad run still passes
new_fx r6; good_runs 12; mkrun 90200 99999 completed success failure 1; run_probe "$PROBE"; expect "R6 a bad run AFTER the 12 oldest" 0
# R7 pending: a still-running run among the first 12
new_fx r7; good_runs 11; mkrun 90300 50000 in_progress "" ABSENT 0; run_probe "$PROBE"; expect "R7 a counted run is still running" 2
new_fx r7b; good_runs 5; mkrun 90301 50000 in_progress "" ABSENT 0; run_probe "$PROBE"; expect "R7b a still-running run among FEWER than 12: the message names the running run, not the short count" 2 "still running"
# R8 xtrace refusal
new_fx r8; good_runs 12; : > "$FX/refused.log"
OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GH_TOKEN=synthetic SOLEUR_FT_EARLIEST="$START" bash -x "$PROBE" 2>&1)"; RC=$?
expect "R8 run under xtrace with GH_TOKEN set" 78
# R9 a cancelled run is skipped, and a skipped run is not a clean one: 11 clean + 1 cancelled is still short
new_fx r9; good_runs 11; mkrun 90400 40000 completed cancelled ABSENT 0; run_probe "$PROBE"; expect "R9 11 clean runs plus one cancelled run" 2
# P1 must-PASS non-canonical: 14 runs in shuffled order, 2 cancelled, one clean run whose only RED is the allowlisted suite
new_fx p1
mkrun 90012 12 completed success success 0; mkrun 90005 5 completed cancelled ABSENT 0; mkrun 90001 1 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
mkrun 90009 9 completed success success 0; mkrun 90003 3 completed success success 0; mkrun 90013 13 completed cancelled ABSENT 0; mkrun 90002 2 completed success success 0
mkrun 90004 4 completed success success 0; mkrun 90006 6 completed success success 0; mkrun 90007 7 completed success success 0; mkrun 90008 8 completed success success 0
mkrun 90010 10 completed success success 0; mkrun 90011 11 completed success success 0; mkrun 90015 14 completed success success 0; mkrun 90014 16 completed success failure 1
run_probe "$PROBE"; expect "P1 shuffled, two cancelled, allowlisted RED, a bad run after the 12th" 0 "Allowlisted tag-drift RED in run(s): 90001"
# X cross-checks against the REAL files this probe reads
new_fx x; good_runs 12; cp "$WORKFLOW" "$FX/workflow.txt"; run_probe "$PROBE"; expect "X the real workflow on this tree passes the pin-count read" 0
_tok="$(grep -vE '^[[:space:]]*#' "$WORKFLOW" | grep -cE "(^|[^A-Za-z0-9_])[\"']?JOBS[\"']?[[:space:]]*[:=]" || true)"
if [ "$_tok" = 1 ]; then pass "X the real workflow carries exactly one JOBS assignment"; else fail "X the real workflow carries $_tok JOBS assignments, want 1"; fi
_wfs="$(grep -vE '^[[:space:]]*#' "$WORKFLOW")"
for _lit in 'main-health-outcomes' 'SOLEUR_MAIN_HEALTH' 'name: Run infra suites' 'id: infra' 'infra_elapsed_s' 'health-check:'; do
  case "$_wfs" in *"$_lit"*) pass "X the real workflow still carries the literal the probe reads: $_lit" ;; *) fail "X the real workflow lost the literal the probe reads: $_lit" ;; esac
done
_rs="$(grep -vE '^[[:space:]]*#' "$RUNNER")"
for _lit in 'registered infra suite(s)' 'with -P ' "UNACCOUNTED  %s" '=== registered infra suites:' 'unaccounted (of'; do
  case "$_rs" in *"$_lit"*) pass "X the real runner still emits the literal the probe parses: $_lit" ;; *) fail "X the real runner lost the literal the probe parses: $_lit" ;; esac
done
_known="$(sed -n 's/^KNOWN_DETERMINISTIC_REDS="\(.*\)"$/\1/p' "$PROBE")"
[ -n "$_known" ] && pass "X the allowlist constant was read from the probe" || fail "X the allowlist constant could not be read from the probe"
for _s in $_known; do
  if [ -f "$REPO_ROOT/apps/web-platform/infra/$_s" ]; then pass "X the allowlisted suite exists on this tree: $_s"; else fail "X the allowlisted suite is not a file on this tree: $_s"; fi
done

# --- kill rows: each mutated COPY of the probe must change the verdict of the row that guards it, to an EXACT exit ------------
new_fx m1; good_runs 12; printf '%s\n' '        env:' '          JOBS: 1' >> "$FX/workflow.txt"
if mutate m1 '"$pins" -ge 2' '"$pins" -ge 99'; then run_probe "$MUT"; kill_row "K1 dropping the pin-count threshold is caught by R1a" 0; fi
new_fx m2; good_runs 11
if mutate m2 'N=12' 'N=11'; then run_probe "$MUT"; kill_row "K2 lowering the sample size is caught by R2a" 0; fi
new_fx m3; good_runs 10; mkrun 90030 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh; mkrun 90031 41000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m3 'KNOWN_DETERMINISTIC_REDS="cloud-init-inngest-bootstrap.test.sh"' 'KNOWN_DETERMINISTIC_REDS=""'; then run_probe "$MUT"; kill_row "K3 emptying the allowlist is caught (two allowlisted runs become two strikes)" 5; fi
new_fx m4; good_runs 12
if mutate m4 '--branch main' '--branch feat-x'; then run_probe "$MUT"; if [ "$RC" -eq 3 ] && [ -s "$FX/refused.log" ]; then pass "K4 a wrong branch selector is refused by the strict stub"; else fail "K4 survived (rc $RC)"; fi; fi
new_fx m5; good_runs 12; mkrun 90500 -1 completed success failure 1
if mutate m5 '--created ">=$EARLIEST"' '--created ">=2000-01-01T00:00:00Z"'; then run_probe "$MUT"; kill_row "K5 a hard-coded window start is caught by R2b" 1; fi
new_fx m6; good_runs 12
if mutate m6 '--limit 200' '--limit 100'; then run_probe "$MUT"; if [ "$RC" -eq 3 ] && [ -s "$FX/refused.log" ]; then pass "K6 a changed list limit is refused by the strict stub"; else fail "K6 survived (rc $RC)"; fi; fi
new_fx m7; good_runs 12
if mutate m7 '*x*)' '*zz*)'; then
  OUT="$(env -i PATH="$TMP/bin:/usr/bin:/bin" HOME="$TMP" FX="$FX" GH_TOKEN=synthetic SOLEUR_FT_EARLIEST="$START" bash -x "$MUT" 2>&1)"; RC=$?
  kill_row "K7 removing the xtrace refusal is caught by R8" 0
fi
new_fx m8; good_runs 11; mkrun 90033 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m8 'gh api --allow-escape-sequences' 'gh api'; then run_probe "$MUT"; kill_row "K8 dropping --allow-escape-sequences is caught by the fake gh's real refusal (R4d)" 3; fi
new_fx m9; good_runs 11; MK_K=1 mkrun 90050 40000 completed success success 0
if mutate m9 '[ "$k" -lt 2 ]' '[ "$k" -lt 0 ]'; then run_probe "$MUT"; kill_row "K9a dropping the K >= 2 floor is caught by W1" 0; fi
new_fx m10; good_runs 11; MK_DUPK=1 mkrun 90052 40000 completed success success 0
if mutate m10 '[ "$nw" != 1 ]' '[ "$nw" -lt 1 ]'; then run_probe "$MUT"; kill_row "K9b dropping the exactly-one width line is caught by W3" 0; fi
new_fx m11; good_runs 11; MK_ELAPSED=0 mkrun 90041 40000 completed success failure 0 other.test.sh
if mutate m11 '! grep -qE '"'"'^infra_elapsed_s=[0-9]+$'"'"' <<<"$toks"' '! true'; then run_probe "$MUT"; kill_row "K10 dropping the no-infra_elapsed_s kill route is caught by R4k" 0; fi
new_fx m13; good_runs 10; mkrun 90030 40000 completed success failure 0 some-other.test.sh; mkrun 90031 41000 completed success failure 0 another.test.sh
if mutate m13a 'JUDGED_REPRODUCING_RUNS="39378082716 39446197504"' 'JUDGED_REPRODUCING_RUNS="90030 90031"' && mutate m13b '*" $rid "*) judged="$judged $rid"; return ;; esac' '*" zz "*) judged="$judged $rid"; return ;; esac' "$TMP/mut.m13a.sh"; then
  run_probe "$MUT"; kill_row "K12 a judged-id list that is never consulted is caught by R4b3" 5
fi
new_fx m14; good_runs 10; mkrun 90030 40000 completed success failure 0 some-other.test.sh; mkrun 90031 41000 completed success failure 0 another.test.sh
if mutate m14 '"$nstrikes" -ge 2' '"$nstrikes" -ge 3'; then run_probe "$MUT"; kill_row "K13 raising the strike threshold is caught by R4b2" 0; fi
new_fx m15; good_runs 11; MK_ANN2=1 mkrun 90042 40000 completed success success 0
if mutate m15 'if length == 1 then' 'if length >= 1 then'; then run_probe "$MUT"; kill_row "K14 accepting several outcome annotations is caught by R5i" 0; fi
new_fx m16; good_runs 10; mkrun 90039 40000 completed success failure 0 'x@mention.test.sh'; mkrun 90040 41000 completed success failure 0 other.test.sh
if mutate m16 'name="<unsafe-name>"' 'name="$s"'; then run_probe "$MUT"; kill_row "K15 echoing a raw RED name is caught by R4j" 5; case "$OUT" in *"x@mention"*) pass "K15 the mutant does echo the raw name";; *) fail "K15 the mutant did not echo the raw name ($OUT)";; esac; fi
new_fx m17; good_runs 11; mkrun 90400 40000 completed cancelled ABSENT 0
if mutate m17 'select(.conclusion != "cancelled")' 'select(.conclusion != "zz")'; then run_probe "$MUT"; kill_row "K16 counting cancelled runs is caught by R9" 3; fi
new_fx m18; good_runs 12
if mutate m18 '[ "$rt" = "$EARLIEST" ]' 'true'; then EARLIEST="2026-13-45T25:61:61Z" run_probe "$MUT"; kill_row "K17 dropping the timestamp round-trip is caught by R5d2" 2; fi
new_fx m21; good_runs 12; echo '{}' > "$FX/runs-raw"
if mutate m21 'if type == "array" then length else error("not an array") end' 'length'; then run_probe "$MUT"; kill_row "K20 dropping the array-type check is caught by R5o" 2; fi
new_fx m19; for i in $(seq 1 12); do MK_TESTTMO=1 mkrun $((91000 + i)) $((i * 3600 + 100)) completed success success 0; done
if mutate m19 'action .Run infra suites. has timed out' 'timed out'; then run_probe "$MUT"; kill_row "K18 a generic timed-out regex is caught by R4h" 1; fi
new_fx m20; good_runs 10; mkrun 90037 40000 completed success failure 0 inngest-bootstrap.test.sh; mkrun 90038 41000 completed success failure 0 x-cloud-init-inngest-bootstrap.test.sh
if mutate m20 '*" $name "*) :' '*"$name"*) :'; then run_probe "$MUT"; kill_row "K19 an unfenced allowlist match is caught by R4i" 0; fi
new_fx m22; good_runs 11; mkrun 90060 40000 completed success failure 0 foo.test.sh bar.test.sh
if mutate m22 'nstrikes=$((nstrikes + n_other))' 'nstrikes=$((nstrikes + 1))'; then run_probe "$MUT"; kill_row "K21 counting a run as ONE strike however many REDs it holds is caught by R4l" 0; fi
new_fx m23; good_runs 10; mkrun 90030 40000 completed success failure 0 some-other.test.sh; mkrun 90032 41000 completed success failure 0 another.test.sh
if mutate m23a 'JUDGED_REPRODUCING_RUNS="39378082716 39446197504"' 'JUDGED_REPRODUCING_RUNS="900301"' && mutate m23b '*" $rid "*) judged=' '*"$rid"*) judged=' "$TMP/mut.m23a.sh"; then run_probe "$MUT"; kill_row "K22 an unfenced judged-id match is caught by R4q" 0; fi
new_fx m24; good_runs 11; MK_MSG="SOLEUR_MAIN_HEALTH tests=failure infra=failure infra_elapsed_s=" mkrun 90061 40000 completed success failure 0 other.test.sh
if mutate m24 "'^infra_elapsed_s=[0-9]+\$'" "'^infra_elapsed_s='"; then run_probe "$MUT"; kill_row "K23 a digits-free infra_elapsed_s match is caught by R4k/R4l2" 0; fi
new_fx m25; good_runs 11; MK_ELAPSED=1 mkrun 90062 40000 completed success failure 1 other.test.sh
if mutate m25 'if [ "$tmo" -gt 0 ] || {' 'if false || {'; then run_probe "$MUT"; kill_row "K24 dropping the timeout-annotation kill route is caught by R4n" 0; fi
new_fx m26; good_runs 11; MK_ELAPSED=1 mkrun 90063 40000 completed success success 1
if mutate m26 '  if [ "$tmo" -gt 0 ] ||' '  if [ "$infra" = success ]; then return; fi
  if [ "$tmo" -gt 0 ] ||'; then run_probe "$MUT"; kill_row "K25 returning clean before the kill test is caught by R4o" 0; fi
new_fx m27; good_runs 11; MK_UNACCLINE=1 mkrun 90070 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m27 "^[0-9TZ:.-]+ +UNACCOUNTED  '" "^NEVERMATCHES  '"; then run_probe "$MUT"; kill_row "K26 dropping the UNACCOUNTED-line scan is caught by R4e2" 0; fi
new_fx m28; good_runs 11; MK_SUMU=1 mkrun 90071 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m28 '[ "$su" != 0 ]' 'false'; then run_probe "$MUT"; kill_row "K27 ignoring the tally's unaccounted count is caught by R4e3" 0; fi
new_fx m29; good_runs 11; MK_SUMF=0 mkrun 90074 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m29 '[ "$sf" != "$nred" ]' 'false'; then run_probe "$MUT"; kill_row "K28 ignoring a tally/RED-line mismatch is caught by R4e6" 0; fi
new_fx m30; good_runs 11; MK_UNACC_PRE=1 mkrun 90072 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m30 'grep -qE '"'"'^[0-9TZ:.-]+ +UNACCOUNTED  '"'"' <<<"$slice"' 'grep -qE '"'"'^[0-9TZ:.-]+ +UNACCOUNTED  '"'"' <<<"$log"'; then run_probe "$MUT"; kill_row "K29 scanning the whole log instead of the infra slice is caught by R4e4" 5; fi
new_fx m31; good_runs 11; MK_K=99999999999999999999999 mkrun 90092 40000 completed success success 0
if mutate m31 '[ "${#k}" -gt 3 ] || ' ''; then run_probe "$MUT"; kill_row "K30 dropping the width-length cap is caught by W7" 0; fi
new_fx m32; good_runs 10; jq -c '. + [.[0], .[1]]' "$FX/runs.json" > "$FX/runs.tmp" && mv "$FX/runs.tmp" "$FX/runs.json"
if mutate m32 'unique_by(.databaseId) | ' ''; then run_probe "$MUT"; kill_row "K31 counting a duplicated run id twice is caught by R5p" 0; fi
new_fx m33; good_runs 11; MK_NOESC=1 mkrun 90093 40000 completed success success 0
if mutate m33 'gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$jid/logs"' 'gh api --allow-escape-sequences "repos/$REPO/actions/jobs/$jid/logs" --jq .'; then run_probe "$MUT"; if [ "$RC" -eq 3 ] && [ -s "$FX/refused.log" ]; then pass "K32 an extra operand on the flagged log call is refused by the strict stub"; else fail "K32 survived (rc $RC)"; fi; fi
new_fx m37; good_runs 11; MK_SUMDUP=1 mkrun 90076 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m37 '|| [ "$sumn" != 1 ] || [ "$su" != 0 ]' '|| [ "$su" != 0 ]'; then run_probe "$MUT"; kill_row "K34 dropping the exactly-one tally conjunct is caught by R4e7" 0; fi
new_fx m38; good_runs 11; MK_DECOY=1 mkrun 90077 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m38 "SUMMARY_RE='^[0-9TZ:.-]+ +=== registered" "SUMMARY_RE='=== registered"; then run_probe "$MUT"; kill_row "K35 dropping the tally line's timestamp anchor is caught by R4e8" 5; fi
new_fx m39; good_runs 11; MK_DECOY=1 mkrun 90077 40000 completed success failure 0 cloud-init-inngest-bootstrap.test.sh
if mutate m39 "WIDTH_RE='^[0-9TZ:.-]+ +Running" "WIDTH_RE='Running"; then run_probe "$MUT"; kill_row "K36 dropping the width line's timestamp anchor is caught by R4e8" 3; fi
new_fx m40; good_runs 11; mkrun 90078 40000 completed success failure 0 '*'
if mutate m40 '
set -f
' '
set +f
'; then run_probe "$MUT"; kill_row "K37 enabling pathname expansion is caught by R4r (a RED name of * expands to the fixture files)" 5; fi
new_fx m41; good_runs 11; MK_JOBDECOY=1 mkrun 90079 40000 completed success success 0
if mutate m41 '[.jobs[] | select(.name == "health-check")][0].id // empty' '.jobs[0].id'; then run_probe "$MUT"; kill_row "K38 picking the first job instead of health-check is caught by R4s" 3; fi
new_fx m42; good_runs 11; MK_ANNDECOY=1 mkrun 90080 40000 completed success failure 1
if mutate m42 '.title == "main-health-outcomes" and ' ''; then run_probe "$MUT"; kill_row "K39 dropping the annotation title filter is caught by R4t" 3; fi

# --- accounting --------------------------------------------------------------------------------------------------------------
printf '=== jobs1-stopgap-7432: %d passed, %d failed ===\n' "$passes" "$fails"
MIN_ASSERTIONS=278
if [ "$asserted" -lt "$MIN_ASSERTIONS" ] || [ $((passes + fails)) -ne "$asserted" ]; then
  printf '[FATAL] anti-vacuity: %d assertions (floor %d), %d recorded\n' "$asserted" "$MIN_ASSERTIONS" $((passes + fails)) >&2
  exit 1
fi
[ "$fails" -eq 0 ] || { printf 'FAILED:\n'; printf '  %s\n' "${FAILURES[@]}"; exit 1; }
exit 0
