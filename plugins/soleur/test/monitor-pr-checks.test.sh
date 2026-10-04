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
# | dequeued (disarmed) | removed (a current RemovedFromMergeQueueEvent, auto-merge armed) | removed_disarmed |
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
      not_queued) pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[]},'"$c"'}' ;;
      dequeued)   pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[]},'"$c"'}' ;;
      removed)    pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":{"enabledAt":"2026-10-04T00:00:00Z"},"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},'"$c"'}' ;;
      removed_disarmed) pr='{"isInMergeQueue":false,"mergeQueueEntry":null,"state":"OPEN","autoMergeRequest":null,"timelineItems":{"nodes":[{"reason":"checks_timed_out","createdAt":"2026-10-04T01:00:00Z"}]},'"$c"'}' ;;
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
if [[ "$_ran" -lt 51 ]]; then
  printf '  FAIL ANTI-VACUITY: only %s assertions ran, floor is 51.\n' "$_ran" >&2
  exit 1
fi
printf '  ok   anti-vacuity floor: %s assertions ran (floor 51)\n' "$_ran"
[[ "$fail_n" -eq 0 ]] || exit 1
