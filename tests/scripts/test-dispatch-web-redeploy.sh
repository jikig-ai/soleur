#!/usr/bin/env bash
# Guard 7 (#7226 / #5914, ADR-237, plan D6): .github/actions/dispatch-web-redeploy/track.sh.
#
# Property: the git-data-pin-redeploy.yml `redeploy` job succeeds ONLY if some web-platform-release run newer than
# the pre-dispatch baseline has a `deploy` job that concluded `success`.
#
# Hermetic: `gh` is a PATH stub that answers ONLY the exact argv track.sh is expected to
# send and exits 64 (logging UNEXPECTED) on anything else, so a drifted call shape reds
# the suite instead of silently answering. Poll interval 1 s, timeout 2 s.
#
#   row  scenario                                                           expected
#   1a   baseline read exits 1                                              RED, no dispatch
#   1b   baseline databaseId non-numeric                                    RED, no dispatch
#   1c   baseline listing empty                                             RED, no dispatch
#   2    newer run concluded success, its deploy job `skipped`              RED at timeout
#   3a   deploy job renamed                                                 RED at timeout
#   3b   deploy job missing from `jobs`                                     RED at timeout
#   1d   baseline databaseId 0                                              RED, no dispatch
#   4    only runs at/below the baseline succeed                            RED at timeout
#   4b   baseline run itself (workflow_run arm) deploys success             RED, never viewed
#   5    dispatched run cancelled, later workflow_run run deploys success   PASS
#   N    deploy conclusion null on tick 1, success on tick 2 (normal path)  PASS
#   O    run 101 deploys success while newer 102 is cancelled               PASS
#   DD   two jobs named `deploy` (failure + success)                        RED at timeout
#   QU   only a `queued` newer run (no jobs yet)                            RED, never viewed
#   Q    a run qualifies on the first poll (before dispatch "returns")      PASS
#   P    a push-arm run with a successful deploy job                        RED, never viewed
#   D    `gh workflow run` rejected                                         RED
#   H    decision stubbed to `exit 0`: every RED row must then FAIL its assertion
#
# source-run-gate.sh (git-data-pin-redeploy.yml's gate on the triggering apply run):
#   G1   git_data_host_create success                                       proceed=true
#   G2   git_data_host_replace success                                      proceed=true
#   G3   both skipped (an ordinary apply run)                               proceed=false, rc 0
#   G4   replace failure                                                    proceed=false, rc 0
#   G8   replace failure: ::warning:: + summary "pin may be published"     proceed=false, rc 0
#   G5   `gh run view` fails                                                RED (fail closed)
#   G6   source run id non-numeric (never echoed)                           RED, no gh call
#   G7   jobs output not a {jobs:[...]} document                            RED (fail closed)
#   GH   gate stubbed to `exit 0`: rows G3-G7 must then FAIL their assertions
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRACK="$REPO_ROOT/.github/actions/dispatch-web-redeploy/track.sh"
export TMPDIR="${TMPDIR:-/var/tmp}"

pass=0; fail=0; FAILURES=()
_report() {
  if [[ "$2" == ok ]]; then pass=$((pass + 1)); echo "[ok] $1"
  else fail=$((fail + 1)); FAILURES+=("$1"); echo "[FAIL] $1 ${3:-}" >&2; fi
}
# Instrument self-test (ADR-193).
_report "instrument self-test (pass arm)" ok
_report "instrument self-test (fail arm)" bad "(expected; unwound)"
(( pass == 1 && fail == 1 )) || { echo "FAIL: reporter self-test" >&2; exit 1; }
pass=0; fail=0; FAILURES=()

[[ -r "$TRACK" ]] || { echo "FAIL: track.sh not readable at $TRACK" >&2; exit 1; }
command -v jq >/dev/null || { echo "FAIL: jq required" >&2; exit 1; }

WORK="$(mktemp -d "$TMPDIR/dispatch-redeploy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# --- gh stub -------------------------------------------------------------------------
# Scenario dir ($STUB_DIR): baseline.out / baseline.rc, dispatch.rc, runs.<tick>.json
# (the last present tick repeats), jobs.<id>.<tick>.json falling back to jobs.<id>.json
# (<tick> = the number of poll-list calls so far). Every call is appended to calls.log.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
d="${STUB_DIR:?}"
printf '%s\n' "$*" >> "$d/calls.log"
case "$*" in
  "run list --workflow web-platform-release.yml --limit 1 --json databaseId")
    [[ -f "$d/baseline.out" ]] && cat "$d/baseline.out"
    exit "$(cat "$d/baseline.rc" 2>/dev/null || echo 0)" ;;
  "workflow run web-platform-release.yml --ref main -f bump_type=patch")
    exit "$(cat "$d/dispatch.rc" 2>/dev/null || echo 0)" ;;
  "run list --workflow web-platform-release.yml --limit 50 --json databaseId,status,conclusion,event")
    n=$(( $(cat "$d/tick" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/tick"
    while (( n > 1 )) && [[ ! -f "$d/runs.$n.json" ]]; do n=$((n - 1)); done
    cat "$d/runs.$n.json" 2>/dev/null || echo '[]'
    exit 0 ;;
esac
if [[ "$1 $2 $4 $5" == "run view --json jobs" && "$3" =~ ^[0-9]+$ && $# -eq 5 ]]; then
  [[ -f "$d/view.rc" ]] && exit "$(cat "$d/view.rc")"
  t=$(cat "$d/tick" 2>/dev/null || echo 0)
  if [[ -f "$d/jobs.$3.$t.json" ]]; then cat "$d/jobs.$3.$t.json"
  else cat "$d/jobs.$3.json" 2>/dev/null || echo '{"jobs":[]}'; fi
  exit 0
fi
echo "UNEXPECTED gh argv: $*" >> "$d/calls.log"
echo "gh stub: unexpected argv: $*" >&2
exit 64
STUB
chmod +x "$WORK/bin/gh"

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
_run() {  # _run ID CONCLUSION EVENT [STATUS]
  printf '{"databaseId":%s,"status":"%s","conclusion":"%s","event":"%s"}' "$1" "${4:-completed}" "$2" "$3"; }
_jobs() {  # _jobs ID JOBNAME CONCLUSION [TICK]; CONCLUSION "null" writes a JSON null
  local c="\"$3\""; [[ "$3" == null ]] && c=null
  assert_fixture_dir "$S"
  printf '{"jobs":[{"name":"release / build","conclusion":"success"},{"name":"%s","conclusion":%s},{"name":"live-verify","conclusion":"success"}]}' "$2" "$c" \
    > "$S/jobs.$1${4:+.$4}.json"
}
_scenario() { S="$WORK/s-$1"; rm -rf "$S"; mkdir -p "$S"; : > "$S/calls.log"
  printf '[{"databaseId":100,"status":"completed","conclusion":"success","event":"push"}]' > "$S/baseline.out"; }

# _exec SCRIPT -> rc, output in $S/out
_exec() {
  local rc=0
  STUB_DIR="$S" PATH="$WORK/bin:$PATH" REDEPLOY_POLL_INTERVAL_S=1 REDEPLOY_TIMEOUT_S=2 \
    GITHUB_STEP_SUMMARY="$S/summary" bash "$1" >"$S/out" 2>&1 || rc=$?
  return "$rc"
}
_no_unexpected() { ! grep -q '^UNEXPECTED' "$S/calls.log"; }
_dispatched() { grep -qx 'workflow run web-platform-release.yml --ref main -f bump_type=patch' "$S/calls.log"; }

# Row checks: each returns 0 when the row's assertion HOLDS for the given script.
check_1a() { _scenario 1a; rm -f "$S/baseline.out"; echo 1 > "$S/baseline.rc"
  ! _exec "$1" && ! _dispatched && grep -q 'could not read the pre-dispatch baseline' "$S/out" && _no_unexpected; }
check_1b() { _scenario 1b; printf '[{"databaseId":"abc"}]' > "$S/baseline.out"
  ! _exec "$1" && ! _dispatched && grep -q "got 'abc'" "$S/out" && _no_unexpected; }
check_1c() { _scenario 1c; printf '[]' > "$S/baseline.out"
  ! _exec "$1" && ! _dispatched && grep -q 'could not read the pre-dispatch baseline' "$S/out" && _no_unexpected; }
check_1d() { _scenario 1d; printf '[{"databaseId":0}]' > "$S/baseline.out"
  ! _exec "$1" && ! _dispatched && grep -q "got '0'" "$S/out" && _no_unexpected; }
check_2() { _scenario 2
  printf '[%s,%s]' "$(_run 101 success workflow_dispatch)" "$(_run 100 success push)" > "$S/runs.1.json"
  _jobs 101 deploy skipped
  ! _exec "$1" && _dispatched && grep -q 'baseline databaseId=100' "$S/out" \
    && grep -q 'last seen databaseId=101' "$S/out" && _no_unexpected; }
check_3a() { _scenario 3a
  printf '[%s]' "$(_run 101 success workflow_dispatch)" > "$S/runs.1.json"
  _jobs 101 "deploy-web" success
  ! _exec "$1" && _dispatched && grep -q '::error::.*last seen databaseId=101' "$S/out" && _no_unexpected; }
check_3b() { _scenario 3b
  printf '[%s]' "$(_run 101 success workflow_dispatch)" > "$S/runs.1.json"
  printf '{"jobs":[{"name":"release / build","conclusion":"success"}]}' > "$S/jobs.101.json"
  ! _exec "$1" && _dispatched && grep -q '::error::.*last seen databaseId=101' "$S/out" && _no_unexpected; }
check_4() { _scenario 4
  printf '[%s,%s]' "$(_run 100 success push)" "$(_run 99 success push)" > "$S/runs.1.json"
  _jobs 100 deploy success; _jobs 99 deploy success
  ! _exec "$1" && _dispatched && grep -q 'baseline databaseId=100' "$S/out" \
    && grep -q 'last seen databaseId=100' "$S/out" \
    && ! grep -q '^run view 100 ' "$S/calls.log" && _no_unexpected; }
# 4b: the baseline run itself is on a deploying arm and deployed success. Strictly-greater
# must exclude it (a `>=` would read the pre-dispatch deploy as the redeploy).
check_4b() { _scenario 4b
  printf '[%s]' "$(_run 100 success workflow_run)" > "$S/runs.1.json"
  _jobs 100 deploy success
  ! _exec "$1" && _dispatched && grep -q 'last seen databaseId=100' "$S/out" \
    && ! grep -q '^run view 100 ' "$S/calls.log" && _no_unexpected; }
check_5() { _scenario 5
  printf '[%s]' "$(_run 101 cancelled workflow_dispatch)" > "$S/runs.1.json"
  printf '[%s,%s]' "$(_run 102 success workflow_run)" "$(_run 101 cancelled workflow_dispatch)" > "$S/runs.2.json"
  _jobs 101 deploy cancelled; _jobs 102 deploy success
  _exec "$1" && grep -q 'run databaseId=102' "$S/out" && grep -q 'concluded cancelled' "$S/out" \
    && grep -q 'Redeploy confirmed' "$S/summary" && _no_unexpected; }
# N: the normal path. Tick 1 the run is in progress and its deploy job has no conclusion
# yet (JSON null); tick 2 it concluded success. An in-progress run must be re-queried.
check_N() { _scenario N
  printf '[%s]' "$(_run 101 "" workflow_dispatch in_progress)" > "$S/runs.1.json"
  printf '[%s]' "$(_run 101 success workflow_dispatch)" > "$S/runs.2.json"
  _jobs 101 deploy null 1; _jobs 101 deploy success 2
  _exec "$1" && grep -q 'run databaseId=101 .*concluded success' "$S/out" \
    && [[ "$(grep -c '^run view 101 ' "$S/calls.log")" -ge 2 ]] \
    && grep -q 'Redeploy confirmed' "$S/summary" && _no_unexpected; }
# O: every newer run is examined, not just the newest: 101 deployed while 102 was cancelled.
check_O() { _scenario O
  printf '[%s,%s]' "$(_run 102 cancelled workflow_run)" "$(_run 101 success workflow_dispatch)" > "$S/runs.1.json"
  _jobs 101 deploy success; _jobs 102 deploy cancelled
  _exec "$1" && grep -q 'run databaseId=101 .*concluded success' "$S/out" && _no_unexpected; }
# DD: an ambiguous (duplicate) `deploy` name never qualifies, even with one success.
check_DD() { _scenario DD
  printf '[%s]' "$(_run 101 success workflow_dispatch)" > "$S/runs.1.json"
  printf '{"jobs":[{"name":"deploy","conclusion":"failure"},{"name":"deploy","conclusion":"success"}]}' > "$S/jobs.101.json"
  ! _exec "$1" && _dispatched && grep -q '::error::.*last seen databaseId=101' "$S/out" && _no_unexpected; }
# QU: a queued run has no jobs yet; it is not viewed (and a fixture claiming success on it
# must not count).
check_QU() { _scenario QU
  printf '[%s]' "$(_run 101 "" workflow_dispatch queued)" > "$S/runs.1.json"
  _jobs 101 deploy success
  ! _exec "$1" && _dispatched && grep -q 'last seen databaseId=101' "$S/out" \
    && ! grep -q '^run view 101 ' "$S/calls.log" && _no_unexpected; }
check_Q() { _scenario Q
  printf '[%s]' "$(_run 101 success workflow_dispatch)" > "$S/runs.1.json"
  _jobs 101 deploy success
  _exec "$1" || return 1
  # Order: baseline read, then dispatch, then the poll.
  local b w p
  b="$(grep -n -- '--limit 1 --json databaseId$' "$S/calls.log" | head -1 | cut -d: -f1)" || true
  w="$(grep -n '^workflow run ' "$S/calls.log" | head -1 | cut -d: -f1)" || true
  p="$(grep -n -- '--limit 50 ' "$S/calls.log" | head -1 | cut -d: -f1)" || true
  [[ -n "$b" && -n "$w" && -n "$p" ]] && (( b < w && w < p )) && _no_unexpected; }
# P: a push-arm run never deploys (ADR-217); even a fixture claiming a successful deploy
# job on it must not count, and it must not even be queried.
check_P() { _scenario P
  printf '[%s]' "$(_run 101 success push)" > "$S/runs.1.json"
  _jobs 101 deploy success
  ! _exec "$1" && _dispatched && ! grep -q '^run view 101 ' "$S/calls.log" && _no_unexpected; }
check_D() { _scenario D; echo 1 > "$S/dispatch.rc"
  ! _exec "$1" && grep -q "was rejected" "$S/out" && ! grep -q -- '--limit 50' "$S/calls.log" && _no_unexpected; }

for row in 1a 1b 1c 1d 2 3a 3b 4 4b 5 N O DD QU P Q D; do
  if "check_$row" "$TRACK"; then _report "row $row" ok
  else _report "row $row" bad; sed 's/^/    /' "$S/out" >&2; sed 's/^/    calls: /' "$S/calls.log" >&2; fi
done

# H: stubbed decision. A track.sh that just exits 0 must FAIL every RED row's assertion.
STUBBED="$WORK/track-stubbed.sh"
sed '0,/^set -euo pipefail$/s//set -euo pipefail\nexit 0/' "$TRACK" > "$STUBBED"
grep -qx 'exit 0' "$STUBBED" || { _report "H precondition (stub inserted)" bad; }
for row in 1a 1b 1c 1d 2 3a 3b 4 4b DD QU P; do
  if "check_$row" "$STUBBED"; then _report "H row $row catches a stubbed exit 0" bad "(assertion held against an always-green tracker)"
  else _report "H row $row catches a stubbed exit 0" ok; fi
done

# M: named mutations of track.sh. Each must turn the listed row RED.
_mutant() {  # _mutant NAME FROM TO -> path; fails if FROM is absent (a stale mutation)
  local m="$WORK/track-mut-$1.sh"
  python3 - "$TRACK" "$m" "$2" "$3" <<'PY' || return 1
import sys
s = open(sys.argv[1]).read()
if s.count(sys.argv[3]) != 1: sys.exit(1)
open(sys.argv[2], "w").write(s.replace(sys.argv[3], sys.argv[4]))
PY
  echo "$m"
}
_mut_row() {  # _mut_row NAME FROM TO ROW
  local m
  if ! m="$(_mutant "$1" "$2" "$3")"; then _report "M $1 (mutation site present)" bad; return; fi
  if "check_$4" "$m"; then _report "M $1 turns row $4 RED" bad "(row held against the mutant)"
  else _report "M $1 turns row $4 RED" ok; fi
}
_mut_row pending-final '*) ;;' '*) FINAL[$id]="pending" ;;' N
_mut_row newest-only '| sort | .[]' '| sort | .[-1:] | .[]' O
_mut_row ge-baseline '.databaseId > $b' '.databaseId >= $b' 4b
_mut_row baseline-zero '^[1-9][0-9]*$' '^[0-9]+$' 1d
_mut_row view-queued '[[ "$status" == queued ]] && continue' ':' QU

# --- source-run-gate.sh (G rows) -------------------------------------------------------
GATE="$REPO_ROOT/.github/actions/dispatch-web-redeploy/source-run-gate.sh"
_gjobs() {  # _gjobs BIRTH_CONCLUSION REPLACE_CONCLUSION -> jobs.555.json
  printf '{"jobs":[{"name":"preflight","conclusion":"success"},{"name":"git_data_host_create","conclusion":"%s"},{"name":"git_data_host_replace","conclusion":"%s"}]}' "$1" "$2" > "$S/jobs.555.json"
}
_gexec() {  # _gexec SCRIPT RUN_ID -> rc; stdout+stderr in $S/out, outputs in $S/ghout
  local rc=0; : > "$S/ghout"
  STUB_DIR="$S" PATH="$WORK/bin:$PATH" SOURCE_RUN_ID="$2" GITHUB_OUTPUT="$S/ghout" GITHUB_STEP_SUMMARY="$S/summary" \
    bash "$1" >"$S/out" 2>&1 || rc=$?
  return "$rc"
}
check_G1() { _scenario G1; _gjobs success skipped
  _gexec "$1" 555 && grep -qx 'proceed=true' "$S/ghout" && grep -qx 'source_job=git_data_host_create' "$S/ghout" && _no_unexpected; }
check_G2() { _scenario G2; _gjobs skipped success
  _gexec "$1" 555 && grep -qx 'proceed=true' "$S/ghout" && grep -qx 'source_job=git_data_host_replace' "$S/ghout" && _no_unexpected; }
check_G3() { _scenario G3; _gjobs skipped skipped
  _gexec "$1" 555 && grep -qx 'proceed=false' "$S/ghout" && ! grep -q 'proceed=true' "$S/ghout" \
    && grep -q '::notice::.*git_data_host_create=skipped' "$S/out" && _no_unexpected; }
check_G4() { _scenario G4; _gjobs skipped failure
  _gexec "$1" 555 && grep -qx 'proceed=false' "$S/ghout" && grep -q 'git_data_host_replace=failure' "$S/out" && _no_unexpected; }
check_G8() { _scenario G8; _gjobs skipped failure
  _gexec "$1" 555 && grep -qx 'proceed=false' "$S/ghout" \
    && grep -q '::warning::.*pin may be published' "$S/out" \
    && grep -q 'pin may be published; dispatch git-data-pin-redeploy.yml' "$S/summary" && _no_unexpected; }
check_G5() { _scenario G5; _gjobs success skipped; echo 1 > "$S/view.rc"
  ! _gexec "$1" 555 && ! grep -q 'proceed=true' "$S/ghout" && grep -q 'fail closed' "$S/out" && _no_unexpected; }
check_G6() { _scenario G6
  ! _gexec "$1" 'abc::warning::x' && ! grep -q 'proceed=true' "$S/ghout" && ! grep -q '^run view' "$S/calls.log" \
    && ! grep -q 'abc' "$S/out" && _no_unexpected; }
check_G7() { _scenario G7; printf '{"message":"Not Found"}' > "$S/jobs.555.json"
  ! _gexec "$1" 555 && ! grep -q 'proceed=true' "$S/ghout" && grep -q 'fail closed' "$S/out" && _no_unexpected; }
[[ -r "$GATE" ]] || { _report "source-run-gate.sh readable" bad; }
for row in G1 G2 G3 G4 G5 G6 G7 G8; do
  if "check_$row" "$GATE"; then _report "row $row" ok
  else _report "row $row" bad; sed 's/^/    /' "$S/out" >&2; sed 's/^/    calls: /' "$S/calls.log" >&2; fi
done
GSTUB="$WORK/gate-stubbed.sh"
sed '0,/^set -euo pipefail$/s//set -euo pipefail\nexit 0/' "$GATE" > "$GSTUB"
grep -qx 'exit 0' "$GSTUB" || _report "GH precondition (stub inserted)" bad
for row in G3 G4 G5 G6 G7 G8; do
  if "check_$row" "$GSTUB"; then _report "GH row $row catches a stubbed exit 0" bad "(assertion held against an always-green gate)"
  else _report "GH row $row catches a stubbed exit 0" ok; fi
done
bash -n "$GATE" && _report "source-run-gate.sh bash -n" ok || _report "source-run-gate.sh bash -n" bad

# The stub must itself refuse unexpected argv (else rows could pass on a drifted call).
_scenario stub
if STUB_DIR="$S" "$WORK/bin/gh" run list --workflow other.yml >/dev/null 2>&1; then
  _report "gh stub rejects unexpected argv" bad
else
  rc=$?; [[ $rc -eq 64 ]] && _report "gh stub rejects unexpected argv (exit 64)" ok || _report "gh stub exit code" bad "(got $rc)"
fi

bash -n "$TRACK" && _report "track.sh bash -n" ok || _report "track.sh bash -n" bad

echo "test-dispatch-web-redeploy: $pass passed, $fail failed"
if (( fail )); then printf '  - %s\n' "${FAILURES[@]}" >&2; exit 1; fi
