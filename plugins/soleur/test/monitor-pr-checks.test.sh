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

# ── T6b: DIRTY, the sibling of BEHIND that the first cut missed ──────────────────
# Both are "green, but a human must act", and both occur WHILE auto-merge is armed. Found by
# running this script against a real PR that went green and then DIRTY: it polled straight through.
mkstub 'OPEN|DIRTY|true' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"DIRTY"* && "$out" == *"conflict"* ]] && ok "T6b green-but-DIRTY is surfaced as needing action, not polled through" || no "T6b dirty" "rc=$rc out=$out"

# ── T9: `skipping` is a real bucket (pass|fail|pending|skipping|cancel) ─────────
# It is part of the array length, so counting it in `tot` but in no tally made the pass fraction
# UNREACHABLE on any PR with a path-filtered job — the script printed `1/3 pass` and `ALL GREEN`
# on adjacent lines. Every PR in this repo has skipped checks, so this was wrong on every run.
SKIP_CHECKS='[{"name":"a","bucket":"pass"},{"name":"e2e","bucket":"skipping"},{"name":"d","bucket":"skipping"}]'
mkstub 'OPEN|CLEAN|false' "$SKIP_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 0 && "$out" == *"1/1 pass"* && "$out" == *"2 skipped"* ]]; then
  ok "T9 skipped checks are reported and excluded from the pass denominator (1/1, not 1/3)"
else
  no "T9 skipping bucket accounting" "rc=$rc out=[$out]"
fi

# ── T10: a DRAFT must never get a 'go merge it' verdict ──────────────────────────
# `gh pr view --json state` returns OPEN for a draft (isDraft is a separate field), so the
# auto-merge branch fired and exited rc=0 telling the operator to merge a PR GitHub will refuse.
mkstub 'OPEN|DRAFT|false' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -ne 0 && "$out" == *"DRAFT"* ]] && ok "T10 a green DRAFT is NOT reported as ready to merge" || no "T10 draft" "rc=$rc out=$out"

# ── T11: green + BLOCKED + auto-merge armed must not poll forever ────────────────
# BLOCKED with nothing pending means branch protection is unsatisfied OUTSIDE the check list;
# auto-merge sits there indefinitely. It rendered identically to CLEAN, which lands in seconds.
mkstub 'OPEN|BLOCKED|true' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -ne 0 && "$out" == *"BLOCKED"* ]] && ok "T11 green-but-BLOCKED is surfaced, not polled through" || no "T11 blocked" "rc=$rc out=$out"

# ── T12: a NON-REQUIRED failure under auto-merge is not a false red ──────────────
mkstub 'OPEN|UNSTABLE|true' "$RED_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 2 && "$out" == *"NON-REQUIRED"* ]] && ok "T12 a non-required failure under UNSTABLE keeps watching instead of exiting red" || no "T12 unstable" "rc=$rc out=$out"

# ── T13: degraded input must not render as measured input ────────────────────────
# The fallbacks are literals, not readings; printing five zeroes in the same shape as real counts
# is the "a zero that does not say what it means" class.
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
[[ "$out" == *"gh probe FAILED"* && "$out" != *"0/0 pass"* ]] && ok "T13 a gh outage says so instead of printing fabricated zeroes" || no "T13 degraded rendering" "out=[$out]"

# ── T14: every line carries a poll counter (unique heartbeats, TIMEOUT countdown) ─
mkstub 'OPEN|BLOCKED|true' "$RUNNING_CHECKS"
out="$(run 7778 --interval 10 --max-polls 2 --heartbeat-every 1)"
[[ "$out" == *"(poll 1/2)"* && "$out" == *"(poll 2/2)"* ]] && ok "T14 each line carries (poll n/MAX) — heartbeats are unique, not byte-identical" || no "T14 poll counter" "out=[$out]"

# ── T7 a gh failure must not kill the loop ───────────────────────────────────────
printf '#!/usr/bin/env bash\nexit 1\n' > "$STUB/gh"; chmod +x "$STUB/gh"
# RE-SCOPED (not deleted): this asserted the OLD rendering, `UNKNOWN|UNKNOWN|automerge=false 0/0`,
# which T13 established was the defect — degraded input printed in the same shape as measured input.
# The property that still matters is the one this arm was written for: a gh failure must not kill
# the loop, and must not be mistaken for a settled PR. It keeps polling and exits rc=2.
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
lines="$(grep -c 'poll [0-9]*/' <<<"$out")"
if [[ "$rc" -eq 2 && "$lines" -ge 1 && "$out" != *"SETTLED"* && "$out" != *"MERGED"* ]]; then
  ok "T7 a failing gh keeps polling and never forges a terminal verdict (rc=2, no SETTLED/MERGED)"
else
  no "T7 gh failure" "rc=$rc lines=$lines out=$out"
fi

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
if [[ "$_ran" -lt 19 ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 19.\n' "$_ran" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 19)\n' "$_ran"
[[ "$fail_n" -eq 0 ]] || exit 1
