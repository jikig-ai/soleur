#!/usr/bin/env bash
# main-health-monitor-mutations-12626.test.sh — Guard 2 for #12626: drives the
# scheduled-run confirmation probe through a fake `gh` and pins its exit-code
# contract (0 PASS, 1 FAIL, 2 NOT YET, 3 CANNOT ESTABLISH, 78 xtrace refusal),
# with mutation rows against mutated COPIES of the probe. An exit-code contract
# nothing drives is a comment.
#
# Fixtures are synthesized (run ids are 1000-series, the scheduled actor is
# soleur-ai[bot]); nothing is written outside a mktemp dir. No row sleeps and
# none depends on the wall clock or the live repo.
set -uo pipefail
export TMPDIR="${TMPDIR:-/var/tmp}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE="$REPO_ROOT/scripts/followthroughs/main-health-monitor-mutations-12626.sh"
command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }
TMP="$(mktemp -d "$TMPDIR/mhm12626.XXXXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT

assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY\n' >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
passes=0; fails=0; asserted=0
FAILURES=()
pass() { passes=$((passes + 1)); asserted=$((asserted + 1)); printf '  PASS: %s\n' "$1"; }
fail() { fails=$((fails + 1)); asserted=$((asserted + 1)); FAILURES+=("$1"); printf '  FAIL: %s\n' "$1"; }

_p0=$passes; _f0=$fails; _n0=${#FAILURES[@]}
pass "self-test" >/dev/null; fail "self-test" >/dev/null
if [ "$passes" -ne $((_p0 + 1)) ] || [ "$fails" -ne $((_f0 + 1)) ] || [ "${#FAILURES[@]}" -ne $((_n0 + 1)) ]; then
  echo "[FATAL] instrument self-test: pass()/fail() did not each record"; exit 1
fi
passes=0; fails=0; asserted=0; FAILURES=()

# --- the fake gh: answers the endpoints the probe reads from $FX/*.json, applying --jq with real jq ---
mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
refuse() { printf 'REFUSED %s\n' "$*" >> "$FX/refused.log"; exit 64; }
[ "$1" = "api" ] || refuse "$@"
shift
jqx=""; ep=""
while (( $# )); do
  case "$1" in
    --jq) jqx="$2"; shift ;;
    -*) refuse "api $*" ;;
    *) ep="$1" ;;
  esac
  shift
done
printf '%s\n' "$ep" >> "$FX/requests.log"
case "$ep" in
  repos/*/actions/workflows/main-health-monitor.yml/runs\?event=workflow_dispatch\&per_page=30)
    [ -f "$FX/fail-runs" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    f="$FX/runs.json" ;;
  repos/*/actions/runs/*/jobs\?per_page=100)
    [ -f "$FX/fail-jobs" ] && { echo "gh: HTTP 500" >&2; exit 1; }
    r="${ep#*runs/}"; f="$FX/jobs-${r%%/*}.json" ;;
  *) refuse "$ep" ;;
esac
[ -f "$f" ] || exit 1
if [ -n "$jqx" ]; then jq -r "$jqx" "$f"; else cat "$f"; fi
FAKE
chmod +x "$TMP/bin/gh"

# --- fixture builders ---------------------------------------------------------------------------
# run <id> <actor> <conclusion> <created_at> [head_branch]
run() { printf '{"id":%s,"actor":{"login":"%s"},"head_branch":"%s","created_at":"%s","conclusion":"%s"}' \
        "$1" "$2" "${5:-main}" "$4" "$3"; }
# a workflow-runs listing body from run(...) JSON objects
runs_body() { local first=1; printf '{"workflow_runs":['; for r in "$@"; do [ $first -eq 1 ] || printf ','; first=0; printf '%s' "$r"; done; printf ']}'; }
# mut-legs <n_good> <n_bad_or_missing-as-absent> — writes a jobs body with the
# given number of green mut legs plus n_bad red ones (missing legs are modelled
# by simply having fewer entries)
jobs_body() { # <n_green_mut> <n_red_mut>
  local g="$1" b="$2" i
  printf '{"jobs":['
  for ((i=0;i<g;i++)); do [ "$i" -eq 0 ] || printf ','; printf '{"name":"test-webplat-mutations (leg-%d-mutation)","conclusion":"success"}' "$i"; done
  for ((i=0;i<b;i++)); do [ $((g+i)) -eq 0 ] || printf ','; printf '{"name":"test-webplat-mutations (leg-red-%d-mutation)","conclusion":"failure"}' "$i"; done
  printf ',{"name":"test-scripts (0/1)","conclusion":"success"}]}'
}
# mkfx <dir>: creates dir; caller writes runs.json + jobs-<id>.json
mkfx() { assert_fixture_dir "$1"; mkdir -p "$1"; : > "$1/requests.log"; }

# run_probe <fixture dir> [probe-path] -> rc; output on stdout
run_probe() {
  local fx="$1" p="${2:-$PROBE}" out rc
  out="$(env FX="$fx" PATH="$TMP/bin:$PATH" GH_TOKEN=x bash "$p" 2>&1)"; rc=$?
  printf '%s' "$out" > "$fx/last.out"
  return $rc
}
# row <name> <expected rc> <fixture dir>
row() {
  local name="$1" want="$2" fx="$3" got
  run_probe "$fx"; got=$?
  if [ "$got" -eq "$want" ]; then pass "$name -> rc $want"
  else fail "$name -> rc $got (want $want): $(tail -c 400 "$fx/last.out")"; fi
}

T0="2026-11-12T19:46:34Z"   # merge instant; fixture runs sit after it

# --------------------------- contract rows ------------------------------------------------------
mkfx "$TMP/fx-pass"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T00:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T06:00:29Z')" > "$TMP/fx-pass/runs.json"
jobs_body 3 0 > "$TMP/fx-pass/jobs-1000.json"; jobs_body 3 0 > "$TMP/fx-pass/jobs-1001.json"
row r-pass 0 "$TMP/fx-pass"
grep -q 'verdict=pass' "$TMP/fx-pass/last.out" && pass 'r-pass prints verdict=pass' || fail 'r-pass missing verdict=pass'
grep -q 'runs/1000/jobs' "$TMP/fx-pass/requests.log" && pass 'r-pass read jobs for run 1000' || fail 'r-pass skipped the jobs read for run 1000'
grep -q 'runs/1001/jobs' "$TMP/fx-pass/requests.log" && pass 'r-pass read jobs for run 1001' || fail 'r-pass skipped the jobs read for run 1001'

# 1. newest scheduled run failed -> FAIL naming the run id
mkfx "$TMP/fx-red-latest"
runs_body "$(run 1002 'soleur-ai[bot]' failure '2026-11-13T06:00:11Z')" \
          "$(run 1001 'soleur-ai[bot]' success  '2026-11-13T00:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' success  '2026-11-12T20:00:29Z')" > "$TMP/fx-red-latest/runs.json"
jobs_body 3 0 > "$TMP/fx-red-latest/jobs-1001.json"; jobs_body 3 0 > "$TMP/fx-red-latest/jobs-1000.json"
row r-red-latest 1 "$TMP/fx-red-latest"
grep -q 'run=1002' "$TMP/fx-red-latest/last.out" && pass 'r-red-latest names run 1002' || fail 'r-red-latest did not name run 1002'
grep -q 'verdict=fail' "$TMP/fx-red-latest/last.out" && pass 'r-red-latest prints verdict=fail' || fail 'r-red-latest missing verdict=fail'

# 2. green scheduled run missing a mut leg -> FAIL (the leg-silently-dropped shape)
mkfx "$TMP/fx-missing-leg"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-missing-leg/runs.json"
jobs_body 3 0 > "$TMP/fx-missing-leg/jobs-1001.json"
jobs_body 2 0 > "$TMP/fx-missing-leg/jobs-1000.json"
row r-missing-leg 1 "$TMP/fx-missing-leg"
grep -q 'mut-legs=2/2' "$TMP/fx-missing-leg/last.out" && pass 'r-missing-leg names the shortfall' || fail 'r-missing-leg missing evidence'

# 3. older green + later red -> FAIL (a check that stops at the first member is the defect class)
mkfx "$TMP/fx-later-red"
runs_body "$(run 1001 'soleur-ai[bot]' failure '2026-11-13T06:00:11Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-later-red/runs.json"
jobs_body 3 0 > "$TMP/fx-later-red/jobs-1000.json"
row r-later-red 1 "$TMP/fx-later-red"

# 4. only manual (deruelle) dispatches post-merge -> NOT YET
mkfx "$TMP/fx-manual-only"
runs_body "$(run 1001 deruelle success '2026-11-13T00:00:31Z')" \
          "$(run 1000 deruelle success '2026-11-12T20:00:29Z')" > "$TMP/fx-manual-only/runs.json"
row r-manual-only 2 "$TMP/fx-manual-only"
grep -q 'jobs' "$TMP/fx-manual-only/requests.log" && fail 'r-manual-only read jobs for a manual dispatch' || pass 'r-manual-only never read jobs'

# 5. cancelled run between two green scheduled runs -> ignored, PASS
mkfx "$TMP/fx-cancelled"
runs_body "$(run 1002 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1001 'soleur-ai[bot]' cancelled '2026-11-13T03:00:00Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-cancelled/runs.json"
jobs_body 3 0 > "$TMP/fx-cancelled/jobs-1000.json"; jobs_body 3 0 > "$TMP/fx-cancelled/jobs-1002.json"
row r-cancelled 0 "$TMP/fx-cancelled"

# 6. malformed jobs JSON -> CANNOT ESTABLISH (never a verdict on a broken read)
mkfx "$TMP/fx-malformed"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-malformed/runs.json"
jobs_body 3 0 > "$TMP/fx-malformed/jobs-1001.json"
printf 'not json{{{' > "$TMP/fx-malformed/jobs-1000.json"
row r-malformed 3 "$TMP/fx-malformed"

# 7. manual deruelle FAILURE between two green scheduled runs -> PASS (manual is not cadence evidence)
mkfx "$TMP/fx-manual-red"
runs_body "$(run 1003 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1002 deruelle          failure '2026-11-13T02:00:00Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-manual-red/runs.json"
jobs_body 3 0 > "$TMP/fx-manual-red/jobs-1000.json"; jobs_body 3 0 > "$TMP/fx-manual-red/jobs-1003.json"
row r-manual-red 0 "$TMP/fx-manual-red"

# 8. bash -x with GH_TOKEN set -> xtrace refusal
out="$(env GH_TOKEN=x bash -x "$PROBE" 2>&1)"; rc=$?
[ "$rc" -eq 78 ] && pass 'r-xtrace -> 78' || fail "r-xtrace -> rc $rc (want 78)"

# 9. only one green scheduled run -> NOT YET
mkfx "$TMP/fx-one-green"
runs_body "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-one-green/runs.json"
jobs_body 3 0 > "$TMP/fx-one-green/jobs-1000.json"
row r-one-green 2 "$TMP/fx-one-green"

# 10. runs listing API failure -> CANNOT ESTABLISH
mkfx "$TMP/fx-runs-fail"; touch "$TMP/fx-runs-fail/fail-runs"
runs_body "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-runs-fail/runs.json"
row r-runs-fail 3 "$TMP/fx-runs-fail"

# 11. jobs listing API failure -> CANNOT ESTABLISH
mkfx "$TMP/fx-jobs-fail"; touch "$TMP/fx-jobs-fail/fail-jobs"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-jobs-fail/runs.json"
row r-jobs-fail 3 "$TMP/fx-jobs-fail"

# 12. pre-merge runs do not count (created_at < MERGE_TS)
mkfx "$TMP/fx-premerge"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-12T18:00:11Z')" > "$TMP/fx-premerge/runs.json"
jobs_body 3 0 > "$TMP/fx-premerge/jobs-1001.json"; jobs_body 3 0 > "$TMP/fx-premerge/jobs-1000.json"
row r-premerge 2 "$TMP/fx-premerge"

# 13. scheduled run on a non-main branch does not count
mkfx "$TMP/fx-nonmain"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T00:00:29Z' main)" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-12T20:00:11Z' experiment)" > "$TMP/fx-nonmain/runs.json"
jobs_body 3 0 > "$TMP/fx-nonmain/jobs-1001.json"; jobs_body 3 0 > "$TMP/fx-nonmain/jobs-1000.json"
row r-nonmain 2 "$TMP/fx-nonmain"

# 14. red mut leg inside a green-looking run -> FAIL
mkfx "$TMP/fx-red-leg"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' success '2026-11-13T00:00:29Z')" > "$TMP/fx-red-leg/runs.json"
jobs_body 3 0 > "$TMP/fx-red-leg/jobs-1001.json"
jobs_body 2 1 > "$TMP/fx-red-leg/jobs-1000.json"
row r-red-leg 1 "$TMP/fx-red-leg"

# 15. GH_TOKEN unset -> CANNOT ESTABLISH (credential posture)
out="$(env -u GH_TOKEN PATH="$TMP/bin:$PATH" FX="$TMP/fx-pass" bash "$PROBE" 2>&1)"; rc=$?
[ "$rc" -eq 3 ] && pass 'r-notoken -> 3' || fail "r-notoken -> rc $rc (want 3)"

# 16. newer green after an older red -> FAIL (the red stays evidence; tail coverage, not first-hit)
mkfx "$TMP/fx-tail-red"
runs_body "$(run 1001 'soleur-ai[bot]' success '2026-11-13T06:00:31Z')" \
          "$(run 1000 'soleur-ai[bot]' failure '2026-11-13T00:00:29Z')" > "$TMP/fx-tail-red/runs.json"
jobs_body 3 0 > "$TMP/fx-tail-red/jobs-1001.json"
row r-tail-red 1 "$TMP/fx-tail-red"

# --------------------------- mutation rows ------------------------------------------------------
# Mutated COPIES of the probe (never the probe itself). A mutant that produces
# the contract rc on its rows is a SURVIVOR and the suite reds.
MUT_RUN=0; MUT_CAUGHT=0; MUT_REDS=0
mutant() { # <name> <old> <new> <row ids...>
  local name="$1" old="$2" new="$3"; shift 3
  MUT_RUN=$((MUT_RUN + 1))
  python3 - "$PROBE" "$TMP/mut-$name.sh" "$old" "$new" <<'PY' || { echo "  FAIL: mutant $name anchor did NOT land"; fails=$((fails+1)); return; }
import sys
src, dst, old, new = sys.argv[1:5]
s = open(src).read()
if s.count(old) != 1:
    sys.exit(3)
open(dst, "w").write(s.replace(old, new))
PY
  chmod +x "$TMP/mut-$name.sh"
  local caught=0 r
  for r in "$@"; do
    local fx="$TMP/fx-${r#r-}"
    run_probe "$fx" "$TMP/mut-$name.sh"; local got=$?
    local want; want="$(expected_rc "$r")"
    if [ "$got" -ne "$want" ]; then caught=$((caught + 1)); fi
  done
  if [ "$caught" -gt 0 ]; then
    MUT_CAUGHT=$((MUT_CAUGHT + 1)); MUT_REDS=$((MUT_REDS + caught))
    printf '  mutant %-22s went red on %d row(s) -> caught\n' "$name" "$caught"
  else
    printf '  mutant %-22s SURVIVOR (suite reds)\n' "$name"
  fi
}
expected_rc() { case "$1" in
  r-pass|r-cancelled|r-manual-red) echo 0 ;;
  r-red-latest|r-missing-leg|r-later-red|r-red-leg|r-tail-red) echo 1 ;;
  r-manual-only|r-one-green|r-premerge|r-nonmain) echo 2 ;;
  r-malformed|r-runs-fail|r-jobs-fail) echo 3 ;;
  *) echo 9 ;; esac }

# a probe that trusts run-level conclusions and never checks the mut legs
# cannot see the leg-silently-dropped shape
mutant m-no-jobs 'if [ "$mut_total" -lt "$MUT_LEG_MIN" ] || [ "$mut_green" != "$mut_total" ]; then' 'if false; then' r-missing-leg r-red-leg
# a probe that does not filter on the bot actor counts manual dispatches
mutant m-actor '   | select(.actor.login == $actor)' '' r-manual-only r-manual-red
# a probe that treats cancelled as failure evidence
mutant m-cancel-evidence 'or .conclusion == "failure")]' 'or .conclusion == "failure" or .conclusion == "cancelled")]' r-cancelled
# a probe satisfied by one green run closes on the first sweep
mutant m-one-enough '[ "$green" -ge "$MIN_GREEN" ]' '[ "$green" -ge 1 ]' r-one-green
# a probe that skips the post-merge window counts pre-split runs
mutant m-premerge '   | select(.created_at >= $since)' '' r-premerge
# a probe that swallows a failed runs read as an empty sample repolls instead of
# surfacing CANNOT ESTABLISH — and can worse-case pass on a later empty fixture
mutant m-api-quiet 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 3; }' 'fail_api() { echo "CANNOT ESTABLISH: GitHub API read failed ($1)"; exit 0; }' r-runs-fail r-jobs-fail r-malformed
# a probe that accepts a non-main scheduled run
mutant m-branch '   | select(.head_branch == "main")' '' r-nonmain
if [ "$MUT_RUN" -eq "$MUT_CAUGHT" ] && [ "$MUT_RUN" -ge 7 ]; then pass "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught"
else fail "MUTANTS: $MUT_CAUGHT of $MUT_RUN caught (every mutant must be caught)"; fi

# harness row: an always-PASS probe must turn the red-expectation rows red
printf '#!/usr/bin/env bash\necho PASS\nexit 0\n' > "$TMP/always-pass.sh"; chmod +x "$TMP/always-pass.sh"
_harness_reds=0
for r in r-red-latest r-missing-leg r-later-red r-red-leg r-tail-red r-manual-only r-one-green r-malformed; do
  run_probe "$TMP/fx-${r#r-}" "$TMP/always-pass.sh"; _rc=$?
  [ "$_rc" -ne "$(expected_rc "$r")" ] && _harness_reds=$((_harness_reds + 1))
done
[ "$_harness_reds" -ge 7 ] && pass "HARNESS: an always-PASS probe turns $_harness_reds rows red" \
  || fail "HARNESS: an always-PASS probe turned only $_harness_reds rows red"

printf 'main-health-monitor-mutations-12626: %d passed, %d failed, %d assertion(s) executed\n' "$passes" "$fails" "$asserted"
_total=$((passes + fails))
_FLOOR=24
if [ "$_total" -lt "$_FLOOR" ]; then
  printf '[FATAL] assertion floor: executed %d < %d\n' "$_total" "$_FLOOR" >&2
  exit 1
fi
exit $(( ${#FAILURES[@]} > 0 ))
