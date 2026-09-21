#!/usr/bin/env bash
# Guard 7 (#7226 / #5914, ADR-237, plan D6): .github/actions/dispatch-web-redeploy/track.sh.
#
# Property: git_data_redeploy succeeds ONLY if some web-platform-release run newer than
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
#   4    only runs at/below the baseline succeed                            RED at timeout
#   5    dispatched run cancelled, later push run deploys success           PASS
#   Q    a run qualifies on the first poll (before dispatch "returns")      PASS
#   D    `gh workflow run` rejected                                         RED
#   H    decision stubbed to `exit 0`: rows 1-4 must then FAIL their assertions
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TRACK="$REPO_ROOT/.github/actions/dispatch-web-redeploy/track.sh"
ACTION="$REPO_ROOT/.github/actions/dispatch-web-redeploy/action.yml"
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
# (the last present tick repeats), jobs.<id>.json. Every call is appended to calls.log.
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
  cat "$d/jobs.$3.json" 2>/dev/null || echo '{"jobs":[]}'
  exit 0
fi
echo "UNEXPECTED gh argv: $*" >> "$d/calls.log"
echo "gh stub: unexpected argv: $*" >&2
exit 64
STUB
chmod +x "$WORK/bin/gh"

_run() { printf '{"databaseId":%s,"status":"completed","conclusion":"%s","event":"%s"}' "$1" "$2" "$3"; }
_jobs() {  # _jobs ID JOBNAME CONCLUSION
  printf '{"jobs":[{"name":"release / build","conclusion":"success"},{"name":"%s","conclusion":"%s"},{"name":"live-verify","conclusion":"success"}]}' "$2" "$3" \
    > "$S/jobs.$1.json"
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
check_5() { _scenario 5
  printf '[%s]' "$(_run 101 cancelled workflow_dispatch)" > "$S/runs.1.json"
  printf '[%s,%s]' "$(_run 102 success push)" "$(_run 101 cancelled workflow_dispatch)" > "$S/runs.2.json"
  _jobs 101 deploy cancelled; _jobs 102 deploy success
  _exec "$1" && grep -q 'run databaseId=102' "$S/out" && grep -q 'concluded cancelled' "$S/out" \
    && grep -q 'Redeploy confirmed' "$S/summary" && _no_unexpected; }
check_Q() { _scenario Q
  printf '[%s]' "$(_run 101 success workflow_dispatch)" > "$S/runs.1.json"
  _jobs 101 deploy success
  _exec "$1" || return 1
  # Order: baseline read, then dispatch, then the poll.
  local b w p
  b="$(grep -n -- '--limit 1 --json databaseId$' "$S/calls.log" | head -1 | cut -d: -f1)"
  w="$(grep -n '^workflow run ' "$S/calls.log" | head -1 | cut -d: -f1)"
  p="$(grep -n -- '--limit 50 ' "$S/calls.log" | head -1 | cut -d: -f1)"
  [[ -n "$b" && -n "$w" && -n "$p" ]] && (( b < w && w < p )) && _no_unexpected; }
check_D() { _scenario D; echo 1 > "$S/dispatch.rc"
  ! _exec "$1" && grep -q "was rejected" "$S/out" && ! grep -q -- '--limit 50' "$S/calls.log" && _no_unexpected; }

for row in 1a 1b 1c 2 3a 3b 4 5 Q D; do
  if "check_$row" "$TRACK"; then _report "row $row" ok
  else _report "row $row" bad; sed 's/^/    /' "$S/out" >&2; sed 's/^/    calls: /' "$S/calls.log" >&2; fi
done

# H: stubbed decision. A track.sh that just exits 0 must FAIL every RED row's assertion.
STUBBED="$WORK/track-stubbed.sh"
sed '0,/^set -euo pipefail$/s//set -euo pipefail\nexit 0/' "$TRACK" > "$STUBBED"
grep -qx 'exit 0' "$STUBBED" || { _report "H precondition (stub inserted)" bad; }
for row in 1a 1b 1c 2 3a 3b 4; do
  if "check_$row" "$STUBBED"; then _report "H row $row catches a stubbed exit 0" bad "(assertion held against an always-green tracker)"
  else _report "H row $row catches a stubbed exit 0" ok; fi
done

# The stub must itself refuse unexpected argv (else rows could pass on a drifted call).
_scenario stub
if STUB_DIR="$S" "$WORK/bin/gh" run list --workflow other.yml >/dev/null 2>&1; then
  _report "gh stub rejects unexpected argv" bad
else
  rc=$?; [[ $rc -eq 64 ]] && _report "gh stub rejects unexpected argv (exit 64)" ok || _report "gh stub exit code" bad "(got $rc)"
fi

# Action shape: inputs exactly {github-token (required), fingerprint (optional)}; every
# embedded `run:` body parses.
if command -v python3 >/dev/null && python3 -c 'import yaml' 2>/dev/null; then
  if python3 - "$ACTION" "$WORK" <<'PY'
import sys, yaml, subprocess, os
a = yaml.safe_load(open(sys.argv[1]))
ins = a["inputs"]
assert set(ins) == {"github-token", "fingerprint"}, ins
assert ins["github-token"]["required"] is True
assert ins["fingerprint"].get("required", False) is False
assert a["runs"]["using"] == "composite"
for i, st in enumerate(a["runs"]["steps"]):
    if "run" in st:
        p = os.path.join(sys.argv[2], f"step{i}.sh")
        open(p, "w").write(st["run"])
        subprocess.run(["bash", "-n", p], check=True)
PY
  then _report "action.yml inputs + run bodies parse" ok; else _report "action.yml inputs + run bodies parse" bad; fi
else
  _report "action.yml check skipped (python3 + PyYAML unavailable)" ok
fi
bash -n "$TRACK" && _report "track.sh bash -n" ok || _report "track.sh bash -n" bad

echo "test-dispatch-web-redeploy: $pass passed, $fail failed"
if (( fail )); then printf '  - %s\n' "${FAILURES[@]}" >&2; exit 1; fi
