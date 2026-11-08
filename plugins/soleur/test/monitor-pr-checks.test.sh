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
# The script takes a per-PR lock (P4c of #10924); keep every arm off a developer's real lock directory. The lock
# itself is covered by monitor-lock.test.sh, which carries no 10 s interval-floor sleeps (about 30 s, against this suite's 245 s).
export SOLEUR_MONITOR_LOCK_DIR="$STUB/locks"
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

# ── T23: red-on-main annotation on the terminal-fail exit path ────────────────
# The AC this PR added ("annotates failing check names with the probe verdict") had ZERO
# asserted coverage — T4's RED_CHECKS lacks `link`, so annotate printed the no-link note
# unasserted. Here the gh stub answers BOTH the monitor's pr checks AND the real probe's
# `gh api` endpoints, so the marker line is exercised end-to-end.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  pr)
    case "$2" in
      view)   printf '%s' 'OPEN|CLEAN|false' ;;
      checks) printf '%s' '[{"name":"a","bucket":"pass","link":""},{"name":"b","bucket":"fail","link":"https://github.com/x/y/actions/runs/4242"},{"name":"c","bucket":"fail","link":""}]' ;;
    esac ;;
  api)
    ep=""
    for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done
    case "$ep" in
      */actions/runs/4242)  printf '%s' '{"id":4242,"workflow_id":9}' ;;
      */workflows/9/runs?*) printf '%s' '{"workflow_runs":[{"id":555}]}' ;;
      */runs/555/jobs?*)    printf '%s' '{"jobs":[{"name":"b","status":"completed","conclusion":"failure"}]}' ;;
      *) echo "stub-miss api: $*" >&2; exit 64 ;;
    esac ;;
esac
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"SETTLED WITH NON-PASS"* \
      && "$out" == *'SOLEUR_RED_ON_MAIN verdict=red-on-main check="b" main_run=555 main_conclusion=failure'* \
      && "$out" == *'red-on-main: "c" has no actions/runs/<id> link — not probed.'* ]]; then
  ok "T23 terminal-fail annotates each failing check with the probe verdict (and the no-link branch)"
else
  no "T23 red-on-main annotation" "rc=$rc out=[$out]"
fi

# T23b: the 10-check probe budget — 11 failing checks probe exactly 10, then announce the cap.
python3 - "$STUB/gh" <<'PY'
import sys, json, pathlib
checks = [{"name": f"chk{i:02d}", "bucket": "fail",
           "link": f"https://github.com/x/y/actions/runs/{4300+i}"} for i in range(1, 12)]
# Single quotes in the printf arg make the JSON's double-quotes literal — no escaping needed
# (JSON never contains a single quote).
stub = (
 "#!/usr/bin/env bash\n"
 'case "$1" in\n'
 "  pr)\n"
 '    case "$2" in\n'
 "      view)   printf '%s' 'OPEN|CLEAN|false' ;;\n"
 f"      checks) printf '%s' '{json.dumps(checks)}' ;;\n"
 "    esac ;;\n"
 "  api)\n"
 '    ep=""\n'
 '    for a in "$@"; do case "$a" in repos/*) ep="$a" ;; esac; done\n'
 '    case "$ep" in\n'
 '      */jobs?*)           printf \'%s\' \'{"jobs":[{"name":"x","status":"completed","conclusion":"success"}]}\' ;;\n'
 '      */workflows/9/runs?*) printf \'%s\' \'{"workflow_runs":[{"id":555}]}\' ;;\n'
 '      */actions/runs/*)   printf \'%s\' \'{"id":4242,"workflow_id":9}\' ;;\n'
 '    esac ;;\n'
 "esac\n")
pathlib.Path(sys.argv[1]).write_text(stub)
PY
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
probes="$(grep -c '^    SOLEUR_RED_ON_MAIN ' <<<"$out")"
if [[ "$rc" -eq 1 && "$out" == *"probe budget (10 checks) reached"* && "$probes" -eq 10 ]]; then
  ok "T23b the probe budget caps at 10 (11 failing checks -> 10 markers + cap line)"
else
  no "T23b probe budget cap" "rc=$rc probes=$probes out=[$out]"
fi

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

# ── T15: the ordering bug, found by this script ON ITS OWN PR ───────────────────
# Green + auto-merge OFF + a mergeState that CANNOT merge. The first cut ran the
# "AUTO-MERGE NOT ARMED, needs an explicit merge" branch BEFORE the mergeState dispatch and
# special-cased only DRAFT — so a green BEHIND PR was told to merge something GitHub would refuse.
# MEASURED live: it printed `ALL GREEN … needs an explicit merge` at mergeState=BEHIND.
# Fixing DRAFT alone fixed the instance and left the class; this arm pins all four states.
for _ms in BEHIND DIRTY BLOCKED DRAFT; do
  mkstub "OPEN|${_ms}|false" "$GREEN_CHECKS"
  out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
  if [[ "$rc" -ne 0 && "$out" == *"${_ms}"* && "$out" != *"needs an explicit merge"* ]]; then :; else
    no "T15 green + automerge-off + ${_ms} must not advise a merge" "rc=$rc out=$out"; _t15=bad
  fi
done
[[ "${_t15:-ok}" == "ok" ]] && ok "T15 a green PR that CANNOT merge (BEHIND/DIRTY/BLOCKED/DRAFT) is never advised to merge"

# ── T16: the positive control — CLEAN + automerge off DOES advise a merge ────────
mkstub 'OPEN|CLEAN|false' "$GREEN_CHECKS"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"needs an explicit merge"* ]] && ok "T16 CLEAN + auto-merge off still DOES advise the explicit merge (T15 is not just 'never advise')" || no "T16 clean advises merge" "rc=$rc out=$out"

# ── T17: the MERGED line must use the SAME denominator as the poll line ─────────
# The landing run for #7839 printed `68/68 pass` on the status line and `68/73 pass` on the MERGED
# line two lines apart: the poll renderer used $gradable and the terminal line used raw $tot. The
# fraction was fixed in one place and left raw in the other — the instance, not the class.
# FIXTURE MUST MAKE pass != gradable. The first cut reused SKIP_CHECKS (pass=1, gradable=1), where
# `$pass` and `$gradable` render the SAME string — so a MERGED line hardcoded to `$pass/$pass`
# (always N/N, hiding every discrepancy) passed. Mutation-proven: that build was green at 28/28.
# One non-required failure makes gradable=2 against pass=1, and a PR CAN merge in that state.
MERGED_MIXED='[{"name":"a","bucket":"pass"},{"name":"opt","bucket":"fail"},{"name":"e2e","bucket":"skipping"},{"name":"d","bucket":"skipping"}]'
mkstub 'MERGED|CLEAN|true' "$MERGED_MIXED"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
# Asserted against the MERGED LINE ALONE. The first cut checked `$out` as a whole, whose positive
# clauses were satisfied by the POLL line printed just above — so a MERGED line rendering `$pass/$pass`
# (always N/N, hiding every discrepancy, i.e. the whole subject of this PR) passed 23/23 green.
_merged_line="$(grep '^MERGED' <<<"$out" || true)"
if [[ "$rc" -eq 0 && "$_merged_line" == *"landed (1/2 pass, 2 skipped,"* ]]; then
  ok "T17 the MERGED LINE ITSELF renders gradable+skips (asserted in isolation, not against the poll line)"
else
  no "T17 MERGED denominator" "rc=$rc merged_line=[$_merged_line]"
fi

# ── T18: a probe failure must name WHICH probe and carry the error ──────────────
# `[gh probe FAILED — state unknown]` named neither the call nor the reason, so four occurrences
# on a live run were undiagnosable afterwards. That is the same "a signal that does not say what
# it means" defect this script exists to fix, one level in.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh: connection reset by peer" >&2
exit 1
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$out" == *"gh probe FAILED:"* && "$out" == *"pr view"* && "$out" == *"connection reset"* ]]; then
  ok "T18 a probe failure names the failing call and quotes gh's stderr"
else
  no "T18 probe failure diagnosability" "rc=$rc out=[$out]"
fi

# ── T18b/T18c: ONE-SIDED probe failures — the arms that make attribution non-vacuous ────
# T18's stub fails BOTH calls, so `failed_probe` is "pr view + pr checks" and a build that wrote
# "pr view" in both branches matched it. MUTATION-PROVEN vacuous: replacing the checks-branch
# label with "pr view" left the suite 23/23 green, certifying a script in which half this PR's
# headline fix does not exist. Every failure stub in the file was all-or-nothing.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  view)   printf '%s' 'OPEN|CLEAN|true' ;;
  checks) echo "gh: HTTP 502 from api.github.com" >&2; exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"
if [[ "$out" == *"check counts UNAVAILABLE"* && "$out" == *"502"* && "$out" != *"pr view"* && "$out" == *"OPEN|CLEAN"* ]]; then
  ok "T18b only-checks-fails: names checks, does NOT say 'pr view', and still reports the state it DID measure"
else
  no "T18b probe attribution / partial-failure reporting" "out=[$out]"
fi

cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  view)   echo "gh: could not resolve host" >&2; exit 1 ;;
  checks) printf '%s' '[{"name":"a","bucket":"pass"}]' ;;
esac
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"
if [[ "$out" == *"FAILED: pr view"* && "$out" != *"pr checks"* && "$out" == *"could not resolve"* ]]; then
  ok "T18c only-view-fails: names 'pr view' and NOT 'pr checks' (the mirror — together these pin attribution)"
else
  no "T18c probe attribution mirror" "out=[$out]"
fi

# ── T19: a successful call's stderr must not be printed as the failed call's cause ──
# gh writes to stderr on SUCCESS (the release-upgrade nag). Both fragments were rendered
# unconditionally with identical separators and no attribution, so the working call's benign
# notice appeared first, as the most prominent "cause" of the other call's failure.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  view)   echo "gh: A new release of gh is available: 2.62.0 -> 2.63.2" >&2; printf '%s' 'OPEN|CLEAN|true' ;;
  checks) echo "gh: HTTP 502" >&2; exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"
[[ "$out" != *"new release"* && "$out" == *"502"* ]] && ok "T19 only a FAILED call's stderr is carried (the success nag is not shown as the cause)" || no "T19 stderr attribution" "out=[$out]"

# ── T20: mktemp failure must REFUSE TO RUN, not report a false outage ───────────────
# CRITICAL regression this PR introduced: unchecked mktemp -> ERRTMP="" (which is SET, so `set -u`
# is silent) -> `2>""` fails the redirection -> the gh call never runs -> probe_ok=0 forever.
# MEASURED with gh healthy: the monitor burned its whole budget and closed with
# "This is an unreachable GitHub, not a quiet PR" while GitHub was reachable.
mkstub 'OPEN|CLEAN|true' "$GREEN_CHECKS"
cat > "$STUB/mktemp" <<'EOF'
#!/usr/bin/env bash
echo "mktemp: No space left on device" >&2
exit 1
EOF
chmod +x "$STUB/mktemp"
out="$(run 7778 --interval 10 --max-polls 2 2>&1)"; rc=$?
rm -f "$STUB/mktemp"
if [[ "$rc" -eq 3 && "$out" == *"Refusing to run"* && "$out" != *"probe FAILED"* ]]; then
  ok "T20 an unwritable TMPDIR REFUSES to start (rc=3) instead of reporting a gh outage that is not happening"
else
  no "T20 mktemp failure handling" "rc=$rc out=[$out]"
fi

# ── T21: all-skipped settles as NOTHING TO GRADE, never 'ALL GREEN' ─────────────────
ALLSKIP='[{"name":"a","bucket":"skipping"},{"name":"b","bucket":"skipping"}]'
mkstub 'OPEN|CLEAN|false' "$ALLSKIP"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"NOTHING TO GRADE"* && "$out" != *"ALL GREEN"* ]] && ok "T21 a fully path-filtered PR settles as NOTHING TO GRADE, not ALL GREEN over 0/0" || no "T21 all-skipped verdict" "rc=$rc out=[$out]"

# ── T19b: the OTHER stderr branch — view FAILS while checks SUCCEEDS with a nag ──────
# T19 only exercises the partial-failure renderer (`check counts UNAVAILABLE`). The
# `gh probe FAILED` renderer is a DIFFERENT line with its own fragments, and a mutation swapping
# `checks_fail_err` back to `checks_err` there survived T19 untouched. Here `pr checks` SUCCEEDS
# while printing the upgrade nag, so a build that renders the successful call's stderr shows it.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  view)   echo "gh: could not resolve host" >&2; exit 1 ;;
  checks) echo "gh: A new release of gh is available: 2.62.0 -> 2.63.2" >&2; printf '%s' '[{"name":"a","bucket":"pass"}]' ;;
esac
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"
[[ "$out" == *"FAILED: pr view"* && "$out" != *"new release"* ]] && ok "T19b the probe-FAILED line carries only the FAILED call's stderr (not the successful call's nag)" || no "T19b stderr attribution on the probe-FAILED branch" "out=[$out]"

# ── T22: MERGED while `gh pr checks` fails — the degraded guard on the terminal line ──
# The realistic co-occurrence: the poll that first observes MERGED is also the one where the head
# branch was just auto-deleted, so `gh pr checks` returns empty with a non-zero exit. Without the
# guard the closing line rendered the `[]` literal as `landed (0/0 pass, 0 skipped, 0 fail, 0
# cancel)` — fabricated zeros as the final word on a landed PR. Mutation-proven: disabling the
# guard left the suite green until this arm existed.
cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
case "$2" in
  view)   printf '%s' 'MERGED|UNKNOWN|true' ;;
  checks) echo "gh: no checks reported on the 'feat/x' branch" >&2; exit 1 ;;
esac
EOF
chmod +x "$STUB/gh"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
_ml="$(grep '^MERGED' <<<"$out" || true)"
if [[ "$rc" -eq 0 && "$_ml" == *"were NOT measured"* && "$_ml" != *"0/0 pass"* ]]; then
  ok "T22 MERGED with a failed checks probe says the counts were NOT measured (never fabricated zeros)"
else
  no "T22 MERGED degraded guard" "rc=$rc merged_line=[$_ml]"
fi

# ── T24: the merge queue (#9454) ─────────────────────────────────────────────────
# A QUEUED PR can read BEHIND, BLOCKED, or auto-merge-off while it is perfectly healthy, and each
# of those verdicts tells the caller to do something that dequeues it (sync it, merge it by hand,
# admin-merge it). The arms read the queue through `sync-pr-behind.sh <pr> --queue-state` (the one
# shared read). The stub serves RAW GraphQL and applies the --jq the script passes, so the real
# verdict program runs. view-seq / gql-seq are per-call lists (last repeats): view tuples
# `STATE|MERGESTATE|AUTOMERGE` (the token FAIL = `gh pr view` errors, no output), gql modes queued | not_queued
# | dequeued (disarmed) | merged (not queued, state MERGED) | removed (a current RemovedFromMergeQueueEvent, auto-merge armed) | removed_disarmed |
# fail. The stub keeps only the TOP-LEVEL pullRequest fields the query names (nested braces stripped), so a query
# that drops state / autoMergeRequest / the removal timeline / the head commit date gets an answer without it.
mkqstub() {  # <view-seq> <checks-json> <gql-seq>
  rm -f "$STUB/gql-calls" "$STUB/gql-n" "$STUB/view-n"
  printf '%s' "$1" > "$STUB/view-seq"; printf '%s' "$2" > "$STUB/checks.json"; printf '%s' "$3" > "$STUB/gql-seq"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
pick() {  # <seq-file> <counter-file> → the n-th comma item, the last one repeating
  local n a
  n=$(( $(cat "$d/$2" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$d/$2"
  IFS=, read -ra a < "$d/$1"
  printf '%s' "${a[$((n-1))]:-${a[${#a[@]}-1]}}"
}
case "$1 $2" in
  "pr view")   v="$(pick view-seq view-n)"; if [[ "$v" == FAIL ]]; then echo "gh: HTTP 502 from fixture" >&2; exit 1; fi; printf '%s' "$v" ;;
  "pr checks") cat "$d/checks.json" ;;
  "api graphql")
    echo "$*" >> "$d/gql-calls"
    jqx=""; q=""; prev=""; for a in "$@"; do [[ "$prev" == --jq ]] && jqx="$a"; [[ "$a" == query=* ]] && q="${a#query=}"; prev="$a"; done
    m="$(pick gql-seq gql-n)"
    c='"commits":{"nodes":[{"commit":{"committedDate":"2026-10-04T00:00:00Z"}}]}'
    case "$m" in
      queued)     pr='{"isInMergeQueue":true,"mergeQueueEntry":{"state":"QUEUED"},"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},'"$c"'}' ;;
      queued_null) pr='{"isInMergeQueue":true,"mergeQueueEntry":{"state":"QUEUED"},"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[]},'"$c"'}' ;;
      not_queued) pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},'"$c"'}' ;;
      dequeued)   pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[]},'"$c"'}' ;;
      removed)    pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},'"$c"'}' ;;
      removed_disarmed) pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},'"$c"'}' ;;
      merged)     pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"MERGED","autoMergeRequest":null,"timelineItems":{"nodes":[]},'"$c"'}' ;;
      *) echo "gh: HTTP 502 from fixture (graphql)" >&2; exit 1 ;;
    esac
    tops=" $(printf '%s' "$q" | tr '\n' ' ' | sed -E 's/.*pullRequest\(number: \$number\) *\{//') "
    while :; do t2="$(sed -E 's/\{[^{}]*\}//g' <<<"$tops")"; [[ "$t2" == "$tops" ]] && break; tops="$t2"; done
    for f in isInMergeQueue mergeQueueEntry state autoMergeRequest timelineItems commits; do
      [[ "$tops" =~ (^|[^A-Za-z_])${f}([^A-Za-z_]|$) ]] || pr="$(jq -c "del(.$f)" <<<"$pr")"
    done
    printf '{"data":{"repository":{"pullRequest":%s}}}' "$pr" | jq -r "$jqx" ;;
  *) echo "stub-miss: $*" >&2; exit 64 ;;
esac
EOF
  chmod +x "$STUB/gh"
}
for _row in "BEHIND|true|needs a sync" "BLOCKED|true|held by branch protection" "BLOCKED|false|needs an explicit merge" "CLEAN|false|needs an explicit merge"; do
  IFS='|' read -r _ms _am _bad <<<"$_row"
  mkqstub "OPEN|${_ms}|${_am}" "$GREEN_CHECKS" queued
  out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
  if [[ "$rc" -eq 2 && "$out" == *"IN MERGE QUEUE"* && "$out" != *"$_bad"* && "$out" != *"CHECKS GREEN BUT"* && "$out" != *"AUTO-MERGE NOT ARMED"* ]]; then
    ok "T24 a QUEUED PR at ${_ms}/automerge=${_am} reads IN MERGE QUEUE and keeps watching (never '${_bad}')"
  else
    no "T24 queued PR at ${_ms}/automerge=${_am}" "rc=$rc out=[$out]"
  fi
done
# T24b: controls — the same states with the PR NOT queued, or the read failing, keep today's verdicts.
mkqstub 'OPEN|BEHIND|true' "$GREEN_CHECKS" not_queued
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"CHECKS GREEN BUT BEHIND"* && "$out" != *"IN MERGE QUEUE — PR"* ]] && ok "T24b control: BEHIND and NOT queued still says needs a sync" || no "T24b not-queued control" "rc=$rc out=[$out]"
mkqstub 'OPEN|BLOCKED|false' "$GREEN_CHECKS" not_queued
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"BLOCKED"* && "$out" != *"IN MERGE QUEUE — PR"* ]] && ok "T24b control: BLOCKED and NOT queued is still surfaced (the queue read is not a blanket pass)" || no "T24b blocked control" "rc=$rc out=[$out]"
mkqstub 'OPEN|BEHIND|true' "$GREEN_CHECKS" fail
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"CHECKS GREEN BUT BEHIND"* && "$out" != *"IN MERGE QUEUE"* ]] && ok "T24c a FAILED queue read never changes a verdict (fails open to the old guidance, not to 'queued')" || no "T24c failed read" "rc=$rc out=[$out]"
# T24d: a healthy CLEAN + armed PR pays for no queue read at all.
mkqstub 'OPEN|CLEAN|true' "$RUNNING_CHECKS" queued
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 2 && ! -s "$STUB/gql-calls" ]] && ok "T24d CLEAN + armed + pending checks makes no queue read" || no "T24d no wasted call" "rc=$rc calls=$(cat "$STUB/gql-calls" 2>/dev/null | wc -l)"
# T24e: the read asks about THIS PR in THIS repo (--repo), and is a single GraphQL call per poll.
mkqstub 'OPEN|BEHIND|true' "$GREEN_CHECKS" queued
out="$(run 7778 --interval 10 --max-polls 1 --repo acme/widgets)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"IN MERGE QUEUE"* && "$(grep -c '^api graphql' "$STUB/gql-calls")" -eq 1 ]] \
   && grep -qE -e '-F owner=acme -F name=widgets -F number=7778 ' "$STUB/gql-calls" && grep -q 'isInMergeQueue' "$STUB/gql-calls"; then
  ok "T24e --repo acme/widgets is passed to the queue read as owner/name, PR 7778, one call per poll"
else
  no "T24e repo/PR plumbing" "rc=$rc calls=$(cat "$STUB/gql-calls" 2>/dev/null | cut -c1-200)"
fi
# T24f: seen queued, then OPEN + out of the queue + auto-merge off = a dequeue: ends the watch loudly
# (rc 1) naming the recovery, instead of "needs an explicit merge" (which would push an agent to --admin).
mkqstub 'OPEN|BEHIND|true,OPEN|CLEAN|false' "$GREEN_CHECKS" queued,dequeued
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"IN MERGE QUEUE"* && "$out" == *"LEFT THE MERGE QUEUE UNMERGED"* \
      && "$out" == *"merge-queue-dequeue.md"* && "$out" == *"startswith(\"gh-readonly-queue/main/pr-7778-\")"* \
      && "$out" != *"needs an explicit merge"* ]]; then
  ok "T24f queued then dequeued ends LEFT THE MERGE QUEUE UNMERGED (rc 1) with the recovery, never 'needs an explicit merge'"
else
  no "T24f dequeue verdict" "rc=$rc out=[$out]"
fi

# T24g: a PR NEVER seen queued whose merge_group run failed: a removal event, auto-merge still armed, mergeState CLEAN.
# No BEHIND/BLOCKED/unarmed tick ever read the queue, so the old script saw a green armed PR and (after the arm flipped)
# said "ALL GREEN, AUTO-MERGE NOT ARMED - needs an explicit merge". The removal event is read on a heartbeat tick and ends
# the watch as LEFT THE MERGE QUEUE UNMERGED naming the reason; no wording steers toward an explicit/--admin merge.
mkqstub 'OPEN|CLEAN|true' "$GREEN_CHECKS" removed
out="$(run 7778 --interval 10 --max-polls 2 --heartbeat-every 1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"LEFT THE MERGE QUEUE UNMERGED"* && "$out" == *"checks_timed_out"* && "$out" == *"merge-queue-dequeue.md"* \
      && "$out" != *"needs an explicit merge"* && "$out" != *"--admin merge"* && "$out" != *"ALL GREEN"* ]]; then
  ok "T24g a never-seen-queued PR with a removal event (armed, CLEAN) ends LEFT THE MERGE QUEUE UNMERGED with the reason, never 'explicit merge'"
else
  no "T24g removal event, never seen queued" "rc=$rc out=[$out]"
fi
mkqstub 'OPEN|CLEAN|false' "$GREEN_CHECKS" removed_disarmed
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"LEFT THE MERGE QUEUE UNMERGED"* && "$out" != *"needs an explicit merge"* ]] && ok "T24g2 removal event + auto-merge off + never seen queued: LEFT THE MERGE QUEUE UNMERGED, not 'explicit merge'" || no "T24g2 removal event, disarmed" "rc=$rc out=[$out]"
# control: a PR that was simply never armed (no removal event, never queued) keeps today's verdict.
mkqstub 'OPEN|CLEAN|false' "$GREEN_CHECKS" dequeued
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 0 && "$out" == *"AUTO-MERGE NOT ARMED"* && "$out" != *"LEFT THE MERGE QUEUE"* ]] && ok "T24g3 control: unarmed, no removal event, never queued: still 'AUTO-MERGE NOT ARMED'" || no "T24g3 unarmed control" "rc=$rc out=[$out]"
# T24m (#11789): a QUEUED PR reads autoMergeRequest=null on the REST view — the queue owns the merge —
# so `automerge=false` alone must never stand as "disarmed": the queue verdict annotates the emission.
mkqstub 'OPEN|CLEAN|false' "$GREEN_CHECKS" queued_null
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"automerge=false(queued)"* && "$out" == *"IN MERGE QUEUE"* \
      && "$out" != *"AUTO-MERGE NOT ARMED"* && "$out" != *"needs an explicit merge"* ]]; then
  ok "T24m queued + autoMergeRequest=null: the poll line is annotated (queued), never the not-armed verdict"
else no "T24m queued+null annotation" "rc=$rc out=[$out]"; fi
mkqstub 'OPEN|BLOCKED|false' "$GREEN_CHECKS" queued_null
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"automerge=false(queued)"* && "$out" == *"IN MERGE QUEUE"* \
      && "$out" != *"AUTO-MERGE NOT ARMED"* && "$out" != *"CHECKS GREEN BUT BLOCKED"* ]]; then
  ok "T24m2 queued + autoMergeRequest=null at BLOCKED: annotated, never the not-armed or BLOCKED verdict"
else no "T24m2 queued+null at BLOCKED" "rc=$rc out=[$out]"; fi
# T24h: an UNKNOWN read is not a positive not-queued read. Seen queued, then the read fails while the PR reads
# OPEN CLEAN / auto-merge off: the old in_queue collapsed that to "not queued" and printed a terminal LEFT (rc 1)
# for a PR that was queued and healthy. It must hold the previous verdict and keep watching (rc 2 at the cap).
mkqstub 'OPEN|BEHIND|true,OPEN|CLEAN|false' "$GREEN_CHECKS" queued,fail
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
[[ "$rc" -eq 2 && "$out" == *"IN MERGE QUEUE"* && "$out" != *"LEFT THE MERGE QUEUE"* && "$out" != *"needs an explicit merge"* ]] && ok "T24h seen queued, then an UNREADABLE queue: no LEFT, no explicit-merge line, the watch goes on (rc 2)" || no "T24h unknown read after queued" "rc=$rc out=[$out]"
# T24i: `gh pr view` failing (state UNKNOWN, auto-merge literal false) on the poll after a queued sighting must not end the
# watch with LEFT either: the verdict needs state OPEN from a measured read (probe_ok).
mkqstub 'OPEN|BEHIND|true,FAIL' "$GREEN_CHECKS" queued
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
[[ "$rc" -eq 2 && "$out" != *"LEFT THE MERGE QUEUE"* && "$out" != *"SETTLED"* ]] && ok "T24i a failed 'gh pr view' after a queued sighting never forges LEFT THE MERGE QUEUE (needs OPEN + probe_ok)" || no "T24i view failure after queued" "rc=$rc out=[$out]"
# T24i2: the same view failure while the queue read ANSWERS not-queued (the UNKNOWN state is not OPEN, so no read is
# even attempted and nothing may be concluded from a stale queued sighting + the fallback `automerge=false`).
mkqstub 'OPEN|BEHIND|true,FAIL' "$GREEN_CHECKS" queued,not_queued
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
[[ "$rc" -eq 2 && "$out" != *"LEFT THE MERGE QUEUE"* && "$out" != *"SETTLED"* ]] && ok "T24i2 view failure + a not-queued answer available: still no forged LEFT (the read needs state OPEN)" || no "T24i2 view failure, not-queued answer" "rc=$rc out=[$out]"
# T24j: the query names every field the verdict needs (the stub answers only what it names): a query that loses
# the removal timeline or the head commit date reads `-` and reddens T24g; this row pins the contract directly.
mkqstub 'OPEN|BEHIND|true' "$GREEN_CHECKS" queued
run 7778 --interval 10 --max-polls 1 >/dev/null
if grep -q 'timelineItems' "$STUB/gql-calls" && grep -q 'REMOVED_FROM_MERGE_QUEUE_EVENT' "$STUB/gql-calls" && grep -q 'committedDate' "$STUB/gql-calls" && grep -q 'autoMergeRequest' "$STUB/gql-calls"; then
  ok "T24j the monitor's queue read selects the removal timeline, autoMergeRequest and the head commit date"
else no "T24j query contract" "calls=$(cut -c1-200 "$STUB/gql-calls" 2>/dev/null)"; fi
# T24l: the LEFT arm for a PR seen queued (auto-merge off, no removal event) reads the verdict's STATE and confirms with ONE
# re-read, like queue_read_settled. (a) the queue's own merge landing between two polls (`not_queued MERGED`) is not a
# departure: the view still said BLOCKED / auto-merge off, the answer says MERGED; (b) a not-queued OPEN answer whose
# confirming re-read says MERGED is not one either; (c) two consecutive OPEN not-queued answers are: LEFT, after exactly
# three queue reads (queued, not_queued, not_queued).
mkqstub 'OPEN|BLOCKED|false' "$GREEN_CHECKS" queued,merged
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"IN MERGE QUEUE"* && "$out" != *"LEFT THE MERGE QUEUE"* && "$out" != *"needs an explicit merge"* ]]; then
  ok "T24l queued, then a not_queued MERGED answer (merge landing): no LEFT, the watch holds for the MERGED view"
else no "T24l merge-completion window" "rc=$rc out=[$out]"; fi
mkqstub 'OPEN|BLOCKED|false' "$GREEN_CHECKS" queued,not_queued,merged
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
if [[ "$rc" -eq 2 && "$out" != *"LEFT THE MERGE QUEUE"* && "$(grep -c "^api graphql" "$STUB/gql-calls")" -eq 3 ]]; then
  ok "T24l2 not_queued OPEN whose confirming re-read says MERGED: no LEFT (3 reads: the re-read happened)"
else no "T24l2 confirming re-read" "rc=$rc reads=$(grep -c "^api graphql" "$STUB/gql-calls" 2>/dev/null) out=[$out]"; fi
mkqstub 'OPEN|BLOCKED|false' "$GREEN_CHECKS" queued,not_queued,not_queued
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"LEFT THE MERGE QUEUE UNMERGED"* && "$(grep -c "^api graphql" "$STUB/gql-calls")" -eq 3 ]]; then
  ok "T24l3 two consecutive OPEN not_queued answers after a queued sighting: LEFT THE MERGE QUEUE UNMERGED (one confirming re-read)"
else no "T24l3 confirmed departure" "rc=$rc reads=$(grep -c "^api graphql" "$STUB/gql-calls" 2>/dev/null) out=[$out]"; fi
mkqstub 'OPEN|BLOCKED|false' "$GREEN_CHECKS" queued,not_queued,queued
out="$(run 7778 --interval 10 --max-polls 2)"; rc=$?
if [[ "$rc" -eq 2 && "$out" != *"LEFT THE MERGE QUEUE"* ]]; then
  ok "T24l4 not_queued then queued again on the confirming re-read: still in the queue, no LEFT"
else no "T24l4 re-read says queued" "rc=$rc out=[$out]"; fi
# T24k: --repo must be OWNER/REPO. A URL / host-qualified / malformed value used to be accepted by the argument
# parser and silently ignored by the queue read (which then asked about the cwd repo's PR of the same number).
mkstub 'OPEN|BLOCKED|true' "$RUNNING_CHECKS"
_bad_ok=1
for bad in "https://github.com/acme/widgets" "github.com/acme/widgets" "acme" "acme/widgets/extra" "acme widgets" "-x/y" "/widgets"; do
  out="$(PATH="$STUB:$PATH" timeout 30 bash "$SUT" 7778 --interval 10 --max-polls 1 --repo "$bad" 2>&1)"; rc=$?
  [[ "$rc" -eq 3 && "$out" == *"--repo must be OWNER/REPO"* && "$out" != *"pass"* ]] || { _bad_ok=0; echo "  --repo '$bad' -> rc=$rc out=[$out]" >&2; }
done
[[ "$_bad_ok" -eq 1 ]] && ok "T24k --repo rejects URL / host / malformed values (rc 3, usage message), never falling back to the cwd repo" || no "T24k --repo validation" "see above"
out="$(PATH="$STUB:$PATH" timeout 30 bash "$SUT" 7778 --interval 10 --max-polls 1 --repo acme/widgets 2>&1)"; rc=$?
[[ "$rc" -eq 2 ]] && ok "T24k control: --repo acme/widgets is accepted" || no "T24k control --repo" "rc=$rc out=[$out]"

# ── T30 ADR-276 S3 (#9728): a draft-era red `test` row on a PR that was marked ready ─────────────
# With CI_DRAFT_LIGHT on, a draft PR's `test` concludes red by design. After `gh pr ready` that row stays the newest
# `test` row for the 38 to 51 minutes the ready run takes, so `gh pr checks` reports `fail` for it. The monitor must
# read plugins/soleur/scripts/ci-head-verdict.sh (stubbed here through the CI_HEAD_VERDICT_BIN seam) and report
# PENDING, not FAILED, while the verdict is pending-full or no-run; stalled and awaiting-approval end the watch with
# the recovery command; full-decided and n/a keep today's reading; a resolver that errors keeps today's reading.
cat > "$STUB/verdict.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_VLOG"
# The REAL error shape: a state=error marker (outside the six-state set) AND exit 3, as ci-head-verdict.sh prints it.
[[ -f "$STUB_VSTATE.fail" ]] && { printf 'SOLEUR_CI_HEAD_VERDICT state=error pr=7778 sha=0000000000000000000000000000000000000000 run=none reason=api-error\n'; exit 3; }
st="$(cat "$STUB_VSTATE")"; why=stub; [[ "$st" == stalled ]] && why=undecided-after-120m
[[ "$st" == no-run-conflicting ]] && { st=no-run; why=conflicting; }
printf 'SOLEUR_CI_HEAD_VERDICT state=%s pr=7778 sha=0000000000000000000000000000000000000000 run=none reason=%s\n' "$st" "$why"
EOF
chmod +x "$STUB/verdict.sh"
export STUB_VLOG="$STUB/verdict-calls" STUB_VSTATE="$STUB/verdict-state" CI_HEAD_VERDICT_BIN="$STUB/verdict.sh"
TEST_RED_CHECKS='[{"name":"a","bucket":"pass"},{"name":"test","bucket":"fail"},{"name":"test-scripts","bucket":"pending"}]'
TEST_RED_ONLY='[{"name":"a","bucket":"pass"},{"name":"test","bucket":"fail"}]'
setv() { printf '%s' "$1" > "$STUB_VSTATE"; rm -f "$STUB_VSTATE.fail" "$STUB_VLOG"; }
mkstub 'OPEN|BLOCKED|true' "$TEST_RED_CHECKS"
setv pending-full
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 2 && "$out" == *"0 fail"* && "$out" != *"NON-PASS"* && "$out" == *"test(ready run pending-full)"* ]]; then
  ok "T30a pending-full: the draft-era red test is PENDING (0 fail, no NON-PASS line), labelled with why"
else no "T30a pending-full reports the draft row as FAILED" "rc=$rc out=[$out]"; fi
[[ "$(cat "$STUB_VLOG" 2>/dev/null)" == "verdict 7778" ]] && ok "T30a the resolver is asked once, for this PR, via the verdict subcommand" || no "T30a resolver call" "log=[$(cat "$STUB_VLOG" 2>/dev/null)]"
mkstub 'OPEN|BLOCKED|true' "$TEST_RED_ONLY"
setv pending-full
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 2 && "$out" != *"SETTLED"* && "$out" == *"TIMEOUT"* ]]; then
  ok "T30b pending-full with the red test as the only non-pass row: no settle, no exit 1 (it keeps watching)"
else no "T30b a red test row alone settled the watch while the ready run is in flight" "rc=$rc out=[$out]"; fi
setv no-run
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 2 && "$out" != *"SETTLED"* && "$out" == *"test(ready run no-run)"* ]]; then
  ok "T30c no-run: PENDING (a ready run may still register), never settled red"
else no "T30c no-run" "rc=$rc out=[$out]"; fi
setv stalled
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"READY RUN STALLED"* && "$out" == *"undecided-after-120m"* && "$out" != *"75 minutes"* && "$out" == *"gh pr ready --undo 7778"* && "$out" == *"gh pr ready 7778"* && "$out" != *"SETTLED WITH NON-PASS"* ]]; then
  ok "T30d stalled: the watch ends rc=1 with the recovery command and no fix loop on the draft-red row"
else no "T30d stalled" "rc=$rc out=[$out]"; fi
setv no-run-conflicting
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"CONFLICTING"* && "$out" == *"git merge origin/main"* && "$out" != *"gh pr ready 7778"* && "$out" != *"SETTLED WITH NON-PASS"* ]]; then
  ok "T30i a conflicting PR (no-run, reason conflicting) ends the watch rc=1 naming the conflict, never the undo/ready advice"
else no "T30i conflicting no-run" "rc=$rc out=[$out]"; fi
setv no-run
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 2 && "$out" != *"CONFLICTING"* ]] && ok "T30j a plain no-run (not conflicting) keeps watching" || no "T30j plain no-run" "rc=$rc out=[$out]"
setv awaiting-approval
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"READY RUN AWAITING APPROVAL"* && "$out" == *"approve"* ]]; then
  ok "T30e awaiting-approval: the watch ends rc=1 and names the approval it needs"
else no "T30e awaiting-approval" "rc=$rc out=[$out]"; fi
setv full-decided
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"SETTLED WITH NON-PASS"* && "$out" == *"fail:test"* ]]; then
  ok "T30f full-decided: a real red test is still FAILED (the row is authoritative; never hidden as PENDING)"
else no "T30f full-decided must report the red test" "rc=$rc out=[$out]"; fi
setv n/a
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"fail:test"* ]] && ok "T30g n/a: today's reading (a red test on a never-draft PR is FAILED)" || no "T30g n/a" "rc=$rc out=[$out]"
setv pending-full; touch "$STUB_VSTATE.fail"
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"fail:test"* && "$out" != *"test(ready run"* ]] && ok "T30h a resolver that errors (state=error marker, exit 3) keeps today's reading (fail toward FAILED, never toward PENDING)" || no "T30h resolver error" "rc=$rc out=[$out]"
mkstub 'OPEN|BLOCKED|true' "$RED_CHECKS"
setv pending-full
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"fail:b"* && ! -e "$STUB_VLOG" ]]; then
  ok "T30i a red non-test check is untouched and the resolver is not even called"
else no "T30i non-test red" "rc=$rc out=[$out] calls=$(cat "$STUB_VLOG" 2>/dev/null)"; fi
mkstub 'OPEN|BLOCKED|true' '[{"name":"b","bucket":"fail"},{"name":"test","bucket":"fail"},{"name":"c","bucket":"pending"}]'
setv pending-full
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
[[ "$out" == *"1 fail"* && "$out" == *"fail:b"* && "$out" != *"fail:test"* ]] && ok "T30j pending-full softens ONLY the test row; another red required row is still reported" || no "T30j" "out=[$out]"
rm -f "$STUB_VLOG"
out="$(PATH="$STUB:$PATH" timeout 90 bash "$SUT" 7778 --interval 10 --max-polls 1 --repo acme/widgets 2>&1)"
[[ "$(cat "$STUB_VLOG")" == "verdict 7778 --repo acme/widgets" ]] && ok "T30k --repo is forwarded to the resolver" || no "T30k --repo forwarding" "log=[$(cat "$STUB_VLOG")]"
unset CI_HEAD_VERDICT_BIN STUB_VLOG STUB_VSTATE

# ── W: the required-set read on the BLOCKED exit (#11544, monitor half) ──────────────────────────────
# A green, BLOCKED, armed, positively not-queued PR whose verdict is full-decided has been held for a context the
# check list does not show. After a hold of MONITOR_REQUIRED_DWELL_S the watch runs `required` once, under a
# timeout, and PRINTS the RECOVERY hints and the SOLEUR_CI_REQUIRED_SET marker after the unchanged BLOCKED line. It reads the
# marker, never the exit code, and never runs a hint. The resolver stub below replays the REAL contract of the
# `required` subcommand (hints first, marker as the LAST stdout line, exit 0 for decided states, 3 for state=error, 2 and
# no marker for usage); a stub that echoed what the monitor expects would grade the monitor against itself.
export CI_HEAD_VERDICT_BIN="$STUB/req.sh" MONITOR_REQUIRED_DWELL_S=0
cat > "$STUB/req.sh" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$d/req-calls"
case "$1" in
  verdict)
    [[ -f "$d/req-verdict-fail" ]] && { printf 'SOLEUR_CI_HEAD_VERDICT state=error pr=7778 sha=0000000000000000000000000000000000000000 run=none reason=api-error\n'; exit 3; }
    printf 'SOLEUR_CI_HEAD_VERDICT state=%s pr=7778 sha=0000000000000000000000000000000000000000 run=none reason=stub\n' "$(cat "$d/req-verdict" 2>/dev/null || echo full-decided)" ;;
  required)
    [[ -x "$d/req-pre" ]] && "$d/req-pre"
    cat "$d/req-body" 2>/dev/null
    exit "$(cat "$d/req-rc" 2>/dev/null || echo 0)" ;;
  *) echo "stub-miss: $*" >&2; exit 64 ;;
esac
EOF
chmod +x "$STUB/req.sh"
M_ABS='SOLEUR_CI_REQUIRED_SET state=absent pr=7778 sha=0123456789abcdef0123456789abcdef01234567 required=3 reason=context-absent absent=["cla-evidence"] pending=[] failed=[]'
M_PEND='SOLEUR_CI_REQUIRED_SET state=pending pr=7778 sha=0123456789abcdef0123456789abcdef01234567 required=3 reason=context-pending absent=[] pending=["cla-evidence"] failed=[]'
M_ERR='SOLEUR_CI_REQUIRED_SET state=error pr=7778 sha=- required=- reason=api-error absent=- pending=- failed=-'
M_DECOY='SOLEUR_CI_REQUIRED_SET state=complete pr=7778 sha=0123456789abcdef0123456789abcdef01234567 required=3 reason=decoy absent=[] pending=[] failed=[]'
R_HINT='RECOVERY rerun run=4242 basis=workflow ctx="cla-evidence" wf="CLA": gh run rerun 4242'
cnt() { local c; c="$(grep -c -- "$1" "$2" 2>/dev/null)" || true; printf '%s' "${c:-0}"; }   # lines of file $2 matching $1; 0 for a missing file
mkgate() {  # [view-tuple] [gql-seq]: a queue-aware gh stub that ALSO logs every argv (mkqstub rewrites $STUB/gh on every call)
  mkqstub "${1:-OPEN|BLOCKED|true}" "$GREEN_CHECKS" "${2:-not_queued}"
  mv "$STUB/gh" "$STUB/gh.real"
  cat > "$STUB/gh" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" >> "$d/gh-argv"
exec "$d/gh.real" "$@"
EOF
  chmod +x "$STUB/gh"
  rm -f "$STUB/gh-argv" "$STUB/req-calls" "$STUB/req-pre" "$STUB/req-rc" "$STUB/req-verdict-fail" "$STUB/targv"
  printf 'full-decided' > "$STUB/req-verdict"
  printf '%s\n%s\n' "$R_HINT" "$M_ABS" > "$STUB/req-body"
}
BLK='CHECKS GREEN BUT BLOCKED — PR #7778 is held by branch protection outside the check list'

# W1 the happy path: the unchanged BLOCKED line, then the read note, the hint, and the marker as the LAST line.
mkgate
out="$(run 7778 --interval 10 --max-polls 3 --repo acme/widgets)"; rc=$?
_after="${out#*"$BLK"}"; _last="${out##*$'\n'}"
if [[ "$rc" -eq 1 && "$(cnt "$BLK" <(printf '%s\n' "$out"))" -eq 1 && "$out" != *"TIMEOUT"* \
      && "$_after" == *"REQUIRED-SET READ"*"$R_HINT"*"$M_ABS"* && "$_last" == "$M_ABS" \
      && "$(cnt '^required 7778 --repo acme/widgets$' "$STUB/req-calls")" -eq 1 ]]; then
  ok "W1 green + BLOCKED + armed + not queued + full-decided: BLOCKED line, read note, hint, marker LAST; one required call with --repo"
else no "W1 happy path" "rc=$rc calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi

# W2 the hold: dwell 10 at a 10 s interval. Poll 1 prints ONE HOLDING line and no terminal; the terminal lands on poll 2.
mkgate
_s0=$SECONDS
out="$(MONITOR_REQUIRED_DWELL_S=10 run 7778 --interval 10 --max-polls 3)"; rc=$?
_el=$(( SECONDS - _s0 ))
# poll 2 prints no poll line of its own (nothing changed), so the hold is read off the clock: poll 1 at t=0, the terminal at t>=10, never poll 3
if [[ "$rc" -eq 1 && "$(cnt 'HOLDING' <(printf '%s\n' "$out"))" -eq 1 && "$(cnt "$BLK" <(printf '%s\n' "$out"))" -eq 1 \
      && "$(cnt '^required 7778$' "$STUB/req-calls")" -eq 1 && "$_el" -ge 10 && "$_el" -lt 20 && "$out" != *"TIMEOUT"* && "$out" == *"$M_ABS" ]]; then
  ok "W2 the hold: one HOLDING line, the terminal after the 10 s dwell and before a third poll (${_el}s), exactly one required call"
else no "W2 hold" "rc=$rc elapsed=${_el}s calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi

# W3 gate: auto-merge off. Today's terminal, and the resolver is never asked anything.
mkgate 'OPEN|BLOCKED|false'
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"$BLK"* && "$out" != *"REQUIRED-SET READ"* && ! -e "$STUB/req-calls" ]]; then
  ok "W3 gate: auto-merge off keeps today's terminal and makes no resolver call at all"
else no "W3 auto-merge off" "rc=$rc calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi

# W4 gate: an UNKNOWN queue read on the FIRST sighting is never read as "not queued".
mkgate 'OPEN|BLOCKED|true' fail
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"$BLK"* && "$out" != *"HOLDING"* && "$out" != *"REQUIRED-SET READ"* && "$(cnt '^required' "$STUB/req-calls")" -eq 0 ]]; then
  ok "W4 gate: an unknown queue read on the first sighting keeps today's immediate terminal, no hold, no required call"
else no "W4 queue unknown" "rc=$rc calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi

# W5 gate: a verdict other than full-decided (n/a, pending-full, an unanswering resolver) never reads the set.
for _v in n/a pending-full ERROR; do
  mkgate
  if [[ "$_v" == ERROR ]]; then : > "$STUB/req-verdict-fail"; else printf '%s' "$_v" > "$STUB/req-verdict"; fi
  out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
  if [[ "$rc" -eq 1 && "$out" == *"$BLK"* && "$out" != *"HOLDING"* && "$out" != *"REQUIRED-SET READ"* && "$(cnt '^required' "$STUB/req-calls")" -eq 0 && "$(cnt '^verdict' "$STUB/req-calls")" -ge 1 ]]; then
    ok "W5 gate: verdict '${_v}' keeps today's terminal and never calls required (the verdict WAS asked: positive control)"
  else no "W5 verdict ${_v}" "rc=$rc calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi
done

# W6 the marker is read, never the exit code: absent/0, pending/0, error/3 all print their own marker LAST; the watch stays rc 1.
for _row in "absent|0|$M_ABS" "pending|0|$M_PEND" "error|3|$M_ERR"; do
  IFS='|' read -r _st _xc _mk <<<"$_row"
  mkgate; printf '%s\n' "$_mk" > "$STUB/req-body"; printf '%s' "$_xc" > "$STUB/req-rc"
  out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
  _last="${out##*$'\n'}"
  if [[ "$rc" -eq 1 && "$_last" == "$_mk" ]]; then ok "W6 state=${_st} (resolver exit ${_xc}): its own marker is printed verbatim as the last line, the watch exit stays 1"
  else no "W6 state=${_st}" "rc=$rc last=[$_last] out=[$out]"; fi
done

# W7 a read with no marker prints ONE degraded line and never forges a marker; and a hung read is bounded.
mkgate; : > "$STUB/req-body"; printf '2' > "$STUB/req-rc"
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"REQUIRED-SET READ — no marker (exit 2)"* && "$(cnt '^SOLEUR_CI_REQUIRED_SET' <(printf '%s\n' "$out"))" -eq 0 ]]; then
  ok "W7a no marker (usage exit 2): one degraded line, zero marker-shaped lines"
else no "W7a no marker" "rc=$rc out=[$out]"; fi
if command -v setsid >/dev/null 2>&1; then
  mkgate
  # The holder INHERITS the stub's stdout (the read's capture): a `$(...)` capture would block until it exits. A holder that
  # redirects its own stdout to /dev/null holds nothing, which would make this row vacuous.
  printf '#!/usr/bin/env bash\nsetsid sleep 8 &\nsleep 30\n' > "$STUB/req-pre"; chmod +x "$STUB/req-pre"
  _s0=$SECONDS
  out="$(MONITOR_REQUIRED_TIMEOUT_S=1 run 7778 --interval 10 --max-polls 3)"; rc=$?
  _el=$(( SECONDS - _s0 ))
  if [[ "$rc" -eq 1 && "$_el" -lt 5 && "$out" == *"timed out after 1s"* && "$(cnt '^SOLEUR_CI_REQUIRED_SET' <(printf '%s\n' "$out"))" -eq 0 ]]; then
    ok "W7b a hung read is cut at the timeout even with a detached descendant holding stdout (${_el}s, rc 1, degraded line names the timeout)"
  else no "W7b timeout bound" "rc=$rc elapsed=${_el}s out=[$out]"; fi
  rm -f "$STUB/req-pre"
else ok "W7b skipped: setsid is not installed here (counted so the assertion floor stays exact)"; fi

# W8 the call is shaped `timeout -k 5 120 bash <resolver> required <PR>`; an absent timeout binary skips the read (never unbounded).
mkgate
cat > "$STUB/tbin" <<'EOF'
#!/usr/bin/env bash
d="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$*" > "$d/targv"
shift 3
exec "$@"
EOF
chmod +x "$STUB/tbin"
out="$(MONITOR_REQUIRED_TIMEOUT_BIN="$STUB/tbin" run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$(cat "$STUB/targv" 2>/dev/null)" == "-k 5 120 bash $STUB/req.sh required 7778" && "$out" == *"$M_ABS" ]]; then
  ok "W8a the read runs as: timeout -k 5 120 bash <resolver> required <PR>"
else no "W8a timeout argv" "rc=$rc argv=[$(cat "$STUB/targv" 2>/dev/null)] out=[$out]"; fi
mkgate
out="$(MONITOR_REQUIRED_TIMEOUT_BIN="$STUB/no-such-timeout" run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$out" == *"skipped: no timeout binary"* && "$(cnt '^required' "$STUB/req-calls")" -eq 0 ]]; then
  ok "W8b no timeout binary: the read is skipped with one degraded line, never made unbounded"
else no "W8b absent timeout binary" "rc=$rc out=[$out]"; fi

# W9 print-only: a hint carrying a command-substitution payload and a `; touch` payload is PRINTED and never executed.
mkgate
printf '%s\n' "RECOVERY rerun run=4242 basis=workflow ctx=\"x\" wf=\"\$(touch $STUB/SENT)\": gh run rerun 4242" \
              "RECOVERY rerun run=4243 basis=workflow ctx=\"y\" wf=\"z; touch $STUB/SENT2\": gh run rerun 4243" "$M_ABS" > "$STUB/req-body"
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && ! -e "$STUB/SENT" && ! -e "$STUB/SENT2" && "$(cnt '^run ' "$STUB/gh-argv")" -eq 0 && "$(cnt '^pr view' "$STUB/gh-argv")" -ge 1 \
      && "$out" == *"gh run rerun 4242"* && "$out" == *"gh run rerun 4243"* ]]; then
  ok "W9 print-only: both payload hints are printed (control) and neither ran; the gh log has no run subcommand"
else no "W9 print-only" "rc=$rc SENT=$(ls "$STUB"/SENT* 2>/dev/null) gh-run=$(cnt '^run ' "$STUB/gh-argv") out=[$out]"; fi

# W10 filter, caps and marker choice: noise dropped, a decoy marker before the real one ignored, 2 pointers kept, candidates cut at 20.
mkgate
{ echo "noise line one"; echo "WARNING: stray"; printf '%s\n' "$M_DECOY"
  echo 'RECOVERY pointer reason=stale-row ctx="test": see the doc'; echo 'RECOVERY pointer failed=["a"]: read the failing checks'
  for _i in $(seq 1 30); do printf 'RECOVERY rerun run=%s basis=candidate ctx="c" wf="w%s"\n' "$_i" "$_i"; done
  printf '%s\n' "$M_ABS"; } > "$STUB/req-body"
out="$(run 7778 --interval 10 --max-polls 3)"; rc=$?
_cands="$(grep -c 'basis=candidate' <<<"$out")" || true
_last="${out##*$'\n'}"
if [[ "$rc" -eq 1 && "$out" != *"noise line one"* && "$out" != *"WARNING: stray"* && "$out" != *"reason=decoy"* \
      && "$out" == *"reason=stale-row"* && "$out" == *'failed=["a"]'* && "${_cands:-0}" -eq 20 \
      && "$out" == *"10 more candidate lines not shown"* && "$_last" == "$M_ABS" ]]; then
  ok "W10 noise and the decoy marker dropped, both pointer lines kept, exactly 20 candidates plus a count of the other 10, the REAL marker last"
else no "W10 filter and caps" "rc=$rc candidates=${_cands:-?} last=[$_last] out=[${out:0:1500}]"; fi

# W11 a poll budget shorter than the hold: today's timing and exit code are kept (rc 1, never a TIMEOUT), with one note.
unset MONITOR_REQUIRED_DWELL_S   # the shipped default (600) is the subject of this row
mkgate
out="$(run 7778 --interval 10 --max-polls 1)"; rc=$?
export MONITOR_REQUIRED_DWELL_S=0
if [[ "$rc" -eq 1 && "$out" == *"$BLK"* && "$out" == *"REQUIRED-SET READ — not due"* && "$out" != *"TIMEOUT"* && "$out" != *"HOLDING"* && "$(cnt '^required' "$STUB/req-calls")" -eq 0 ]]; then
  ok "W11 default dwell with a 1-poll budget: the BLOCKED ending with one 'not due' note, rc 1, no TIMEOUT, no read (pins the default dwell as non-zero)"
else no "W11 budget shorter than the hold" "rc=$rc out=[$out]"; fi

# W12 (a) an unknown queue read in the middle of a hold is NOT a positive answer: the watch ends with today's BLOCKED ending and no read
# (the hold continues only across polls that each prove the gates); (b) the production default resolver path.
# PR_QUEUE_ATTEMPTS=1: the queue read retries a failed call once by default, and the retry would consume the next sequence item and
# answer "not queued", so poll 2 would never be unknown. The gql call count is the positive control that poll 2 really made a failing read.
mkgate 'OPEN|BLOCKED|true' 'not_queued,fail,not_queued'
_s0=$SECONDS
out="$(PR_QUEUE_ATTEMPTS=1 MONITOR_REQUIRED_DWELL_S=20 run 7778 --interval 10 --max-polls 5)"; rc=$?
_el=$(( SECONDS - _s0 ))
if [[ "$rc" -eq 1 && "$(cnt 'HOLDING' <(printf '%s\n' "$out"))" -eq 1 && "$(cnt "$BLK" <(printf '%s\n' "$out"))" -eq 1 && "$(cnt '^required' "$STUB/req-calls")" -eq 0 \
      && "$(cnt '^api graphql' "$STUB/gql-calls")" -eq 2 && "$_el" -ge 10 && "$_el" -lt 20 && "$out" != *"REQUIRED-SET READ"* ]]; then
  ok "W12a an unknown queue read mid-hold ends the watch with today's BLOCKED ending: one HOLDING line, no required call, no read note"
else no "W12a unknown mid-hold" "rc=$rc elapsed=${_el}s calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi
_sd="$STUB/prod"; mkdir -p "$_sd"
for _f in "$(dirname "$SUT")"/*; do [[ -f "$_f" && "$(basename "$_f")" != ci-head-verdict.sh ]] && ln -s "$_f" "$_sd/$(basename "$_f")"; done
ln -s "$(dirname "$SUT")/lib" "$_sd/lib"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "$STUB/req.sh" > "$_sd/ci-head-verdict.sh"; chmod +x "$_sd/ci-head-verdict.sh"
mkgate; rm -f "$STUB/req-calls"
out="$(unset CI_HEAD_VERDICT_BIN; PATH="$STUB:$PATH" timeout 90 bash "$_sd/monitor-pr-checks.sh" 7778 --interval 10 --max-polls 3)"; rc=$?
if [[ "$rc" -eq 1 && "$(cat "$STUB/req-calls" 2>/dev/null)" == $'verdict 7778\nrequired 7778' && "$out" == *"$M_ABS" ]]; then
  ok "W12b the production default: with the seam UNSET the resolver beside the script receives 'verdict 7778' then 'required 7778'"
else no "W12b default resolver path" "rc=$rc calls=[$(cat "$STUB/req-calls" 2>/dev/null)] out=[$out]"; fi

# W13 the numeric seams: 0 for the timeout (GNU timeout 0 means no limit), a leading-zero dwell (octal in $(( ))) and non-numerics exit 3.
for _row in MONITOR_REQUIRED_TIMEOUT_S=0 MONITOR_REQUIRED_DWELL_S=08 MONITOR_REQUIRED_DWELL_S=abc MONITOR_REQUIRED_TIMEOUT_S=1x; do
  out="$(env "$_row" PATH="$STUB:$PATH" timeout 30 bash "$SUT" 7778 --interval 10 --max-polls 1 2>&1)"; rc=$?
  if [[ "$rc" -eq 3 && "$out" == *"${_row%%=*}"* ]]; then ok "W13 ${_row} is rejected with exit 3 naming the variable"
  else no "W13 ${_row}" "rc=$rc out=[$out]"; fi
done
mkgate
out="$(MONITOR_REQUIRED_DWELL_S=0 MONITOR_REQUIRED_TIMEOUT_S=1 run 7778 --interval 10 --max-polls 3)"; rc=$?
[[ "$rc" -eq 1 && "$out" == *"$M_ABS" ]] && ok "W13 control: dwell 0 and timeout 1 are accepted and the read happens" || no "W13 control" "rc=$rc out=[$out]"

# W14 coupling to the real resolver: the monitor's marker prefix and its candidate-line shape are the RESOLVER's, and both suites run
# against stubs, so a rename on either side would otherwise leave the monitor printing only degraded lines with everything green.
_rsv="$(dirname "$SUT")/ci-head-verdict.sh"
_mk="$(sed -n 's/^readonly REQUIRED_MARKER="\(.*\)"$/\1/p' "$_rsv")"
if [[ -n "$_mk" && "$(cnt "'^${_mk} '" "$SUT")" -ge 1 && "$(cnt 'RECOVERY rerun run=%s basis=candidate ' "$_rsv")" -ge 1 \
      && "$(cnt 'basis=candidate ' "$SUT")" -ge 1 ]]; then
  ok "W14 the monitor's marker prefix (${_mk}) and basis=candidate line shape match the resolver's own emitters"
else no "W14 resolver coupling" "marker=[${_mk}] monitor-prefix=$(cnt "'^${_mk} '" "$SUT") resolver-candidate=$(cnt 'RECOVERY rerun run=%s basis=candidate ' "$_rsv")"; fi
unset CI_HEAD_VERDICT_BIN MONITOR_REQUIRED_DWELL_S

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
if [[ "$_ran" -lt 96 ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 96.\n' "$_ran" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 96)\n' "$_ran"
[[ "$fail_n" -eq 0 ]] || exit 1
