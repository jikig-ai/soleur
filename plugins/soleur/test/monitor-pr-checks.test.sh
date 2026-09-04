#!/usr/bin/env bash
# Unit suite for plugins/soleur/scripts/monitor-pr-checks.sh.
#
# THE LOAD-BEARING ARM IS T3: the HEALTHY, STILL-RUNNING state must emit. Every other
# property here (terminal states, exit codes, arg validation) was already satisfied by the
# hand-rolled loop this script replaces — that loop covered all four terminal states and
# still went silent for 50 minutes, because emitting on the in-progress path was the one
# case nobody thought to assert. A suite that checks only terminal behaviour reproduces
# exactly the blind spot the script exists to close.
#
# `gh` is stubbed on PATH; no network, no real PR.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUT="$DIR/soleur/scripts/monitor-pr-checks.sh"
[[ -x "$SUT" ]] || { printf 'FATAL: SUT not executable at %s\n' "$SUT" >&2; exit 1; }

pass_n=0; fail_n=0
ok()  { pass_n=$((pass_n+1)); printf '  [ok] %s\n' "$1"; }
no()  { fail_n=$((fail_n+1)); printf '  [FAIL] %s\n' "$1" >&2; [[ -n "${2:-}" ]] && printf '        %s\n' "$2" >&2; return 0; }

# INSTRUMENT SELF-TEST (ADR-193): drive both helpers once, then roll back, so a suite whose
# ok()/no() were neutered cannot report green.
_p=$pass_n _f=$fail_n; ok "selftest"; no "selftest" >/dev/null 2>&1
if [[ "$pass_n" -eq $((_p+1)) && "$fail_n" -eq $((_f+1)) ]]; then
  pass_n=$_p; fail_n=$_f; ok "INSTRUMENT: ok() and fail() each move their own counter"
else
  pass_n=$_p; fail_n=$_f; no "INSTRUMENT: helpers do not discriminate — every assertion below is decorative"
fi

STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
mkstub() {  # mkstub <view-json-tuple> <checks-json>
  cat > "$STUB/gh" <<EOF
#!/usr/bin/env bash
case "\$2" in
  view)   printf '%s' '$1' ;;
  checks) printf '%s' '$2json' ;;
esac
EOF
  # write checks separately to avoid quoting hell
  python3 - "$STUB/gh" "$1" "$2" <<'PY'
import sys,pathlib
p,view,checks=sys.argv[1],sys.argv[2],sys.argv[3]
pathlib.Path(p).write_text(
 "#!/usr/bin/env bash\n"
 'case "$2" in\n'
 f"  view)   printf '%s' {chr(39)}{view}{chr(39)} ;;\n"
 f"  checks) printf '%s' {chr(39)}{checks}{chr(39)} ;;\n"
 "esac\n")
PY
  chmod +x "$STUB/gh"
}
# timeout 90, not 20: T3b runs 3 polls at the 10s floor, so the third emit lands at t=20 and a
# 20s cap killed it mid-assertion. The arm was right and the harness was too tight — worth naming,
# because "the test that proves the heartbeat" failing for a harness reason is the one failure most
# likely to get "fixed" by weakening the assertion.
run() { PATH="$STUB:$PATH" timeout 90 bash "$SUT" "$@"; }

RUNNING_CHECKS='[{"name":"a","bucket":"pass"},{"name":"b","bucket":"pass"},{"name":"test-scripts","bucket":"pending"}]'
GREEN_CHECKS='[{"name":"a","bucket":"pass"},{"name":"b","bucket":"pass"}]'
RED_CHECKS='[{"name":"a","bucket":"pass"},{"name":"b","bucket":"fail"}]'

# ── T1 merged ────────────────────────────────────────────────────────────────────
mkstub 'MERGED|CLEAN|false' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"MERGED — PR #7778 landed"* ]] && ok "T1 MERGED terminates rc=0 and says so" || no "T1 merged" "rc=$rc out=$out"

# ── T2 closed unmerged ───────────────────────────────────────────────────────────
mkstub 'CLOSED|DIRTY|false' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"CLOSED WITHOUT MERGE"* ]] && ok "T2 CLOSED terminates rc=1" || no "T2 closed" "rc=$rc out=$out"

# ── T3 THE POINT OF THE SCRIPT ───────────────────────────────────────────────────
# Healthy, still running, nothing terminal. The hand-rolled loop emitted NOTHING here.
mkstub 'OPEN|BLOCKED|true' "$RUNNING_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"2/3 pass"* && "$out" == *"1 pending"* && "$out" == *"test-scripts"* ]]; then
  ok "T3 the HEALTHY in-progress poll EMITS a progress line (counts + what it waits on)"
else
  no "T3 in-progress emission — the defect this script exists to close" "rc=$rc out=[$out]"
fi
# T3b: the emission path is capable of firing on EVERY poll — asserted at --heartbeat-every 1
# rather than at the default. This arm originally read "3 polls -> 3 lines" with no flag, which
# encoded the OVER-correction (emit unconditionally) and went red the moment throttling landed.
# Re-scoped rather than deleted: the property worth pinning is that nothing structurally caps the
# emission below one-per-poll; T3c pins the throttle, and the two together are the contract.
mkstub 'OPEN|BLOCKED|true' "$RUNNING_CHECKS"
out="$(run 7778 --interval 10 --max-polls 3 --heartbeat-every 1)"
lines="$(grep -c 'pass · ' <<<"$out")"
[[ "$lines" -eq 3 ]] && ok "T3b at --heartbeat-every 1 every poll emits (3 polls -> 3 lines)" || no "T3b per-poll emission" "got $lines lines"

# ── T3c/T3d: change-plus-heartbeat, the OTHER half of the contract ───────────────
# Emitting every poll unconditionally is the over-correction: a 35-minute run at a 120s cadence is
# ~17 identical lines, and the Monitor tool auto-stops a watch that produces too many events —
# which reproduces silence by another route. Unchanged state must therefore be throttled, but not
# to zero.
mkstub 'OPEN|BLOCKED|true' "$RUNNING_CHECKS"
out="$(run 7778 --interval 10 --max-polls 6 --heartbeat-every 3)"
lines="$(grep -c 'pass · ' <<<"$out")"
# poll 1 emits (baseline, prev empty); polls 3 and 6 emit as heartbeats; 2/4/5 are suppressed.
[[ "$lines" -eq 3 ]] && ok "T3c unchanged state is THROTTLED to a heartbeat (6 polls, every-3 -> 3 lines)"   || no "T3c heartbeat throttling" "expected 3 lines, got $lines"
[[ "$out" == *"unchanged, still watching"* ]] && ok "T3d the heartbeat line SAYS it is unchanged, not silent"   || no "T3d heartbeat is labelled" "out=[$out]"

# ── T4 red checks ────────────────────────────────────────────────────────────────
mkstub 'OPEN|BLOCKED|true' "$RED_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"SETTLED WITH NON-PASS"* && "$out" == *"fail:b"* ]] && ok "T4 a failing check terminates rc=1 and NAMES it" || no "T4 red" "rc=$rc out=$out"

# ── T5 green but auto-merge not armed ────────────────────────────────────────────
mkstub 'OPEN|CLEAN|false' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"AUTO-MERGE NOT ARMED"* ]] && ok "T5 all-green + no auto-merge reports that it needs an explicit merge" || no "T5 automerge-off" "rc=$rc out=$out"

# ── T6 green but BEHIND ──────────────────────────────────────────────────────────
mkstub 'OPEN|BEHIND|true' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"BEHIND"* ]] && ok "T6 green-but-BEHIND is surfaced, not waited on forever" || no "T6 behind" "rc=$rc out=$out"

# ── T7 a gh failure must not kill the loop ───────────────────────────────────────
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
[[ "$rc" -eq 2 && "$out" == *"UNKNOWN"* ]] && ok "T7 a failing gh degrades to UNKNOWN and keeps polling (does not die silently)" || no "T7 gh failure" "rc=$rc out=$out"

# ── T8 argument validation ───────────────────────────────────────────────────────
mkstub 'OPEN|BLOCKED|true' "$RUNNING_CHECKS"
for bad in "" "abc" "--interval 5 7778"; do
  # shellcheck disable=SC2086
  out="$(run $bad 2>&1)"; rc=$?
  [[ "$rc" -eq 3 ]] || { no "T8 rejects bad args ($bad)" "rc=$rc"; continue; }
done
ok "T8 non-numeric PR, missing PR, and interval<10 all exit 3"

printf '\nmonitor-pr-checks.test.sh: %s passed, %s failed\n' "$pass_n" "$fail_n"
_ran=$((pass_n + fail_n))
if [[ "$_ran" -lt 12 ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 12.\n' "$_ran" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 12)\n' "$_ran"
[[ "$fail_n" -eq 0 ]] || exit 1
