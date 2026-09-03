#!/usr/bin/env bash
# Fixture suite for the monitor-lifetime hook PAIR:
#   monitor-arm-recorder.sh   (PostToolUse on Monitor|TaskStop) — writes the ledger
#   monitor-supersede-guard.sh (PreToolUse on Monitor)          — reads it, reports
#
# Everything resolves from BASH_SOURCE so the suite passes from any cwd. The
# previous version copied a lib with a CWD-relative path guarded by `|| true`,
# so running it from anywhere but the repo root silently broke one case and
# blamed telemetry for it (measured).
set -uo pipefail

HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
GUARD="$HERE/monitor-supersede-guard.sh"
REC="$HERE/monitor-arm-recorder.sh"
PASS=0; FAIL=0; CASES=0
pass() { PASS=$((PASS + 1)); printf '  PASS: %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL: %s\n' "$1"; }
verdict() { CASES=$((CASES + 1)); if [ "$1" = "0" ]; then pass "$2"; else fail "$2"; fi; }

WORK=$(mktemp -d -t monsup-XXXXXX) || exit 1
trap 'rm -rf "$WORK"' EXIT
# Redirect the incident sink at a fixture root so the suite never writes the
# operator's real .claude/.rule-incidents.jsonl (it used to, 4 rows per run).
mkdir -p "$WORK/fakeroot/.claude"
export CLAUDE_PROJECT_DIR="$WORK/fakeroot"
# INCIDENTS_REPO_ROOT too, and it is the load-bearing one: _incidents_repo_root()
# does NOT read CLAUDE_PROJECT_DIR — absent this it resolves BASH_SOURCE-relative
# to the real repo and the suite writes the operator's live incident ledger.
# Measured: 19 rows leaked in before this line existed.
export INCIDENTS_REPO_ROOT="$WORK/fakeroot"
INC="$WORK/fakeroot/.claude/.rule-incidents.jsonl"

TRANSCRIPT="$WORK/transcript.jsonl"
fresh() { LEDGER="$WORK/led-$1.jsonl"; : > "$LEDGER"; export SOLEUR_MONITOR_LEDGER="$LEDGER"
          TRANSCRIPT="$WORK/tr-$1.jsonl"; : > "$TRANSCRIPT"; }

# --- drivers -----------------------------------------------------------------
# RC is set by every guard call: the "never blocks" invariant has TWO channels,
# and `exit 2` is the one the repo documents as blocking with stdout ignored.
RC=0
guard() {  # guard <session> <tool_input> [tool_name]
  local out
  out=$(jq -nc --arg s "$1" --arg t "${3:-Monitor}" --argjson ti "$2" --arg tp "$TRANSCRIPT" \
        '{session_id:$s, tool_name:$t, tool_input:$ti, transcript_path:$tp}' | bash "$GUARD" 2>/dev/null)
  RC=$?
  printf '%s' "$out"
}
record() {  # record <session> <tool> <tool_input> <tool_response>
  jq -nc --arg s "$1" --arg t "$2" --argjson ti "$3" --argjson tr "$4" \
    '{session_id:$s, tool_name:$t, tool_input:$ti, tool_response:$tr}' | bash "$REC" >/dev/null 2>&1
}
complete_task() { printf '{"type":"queue-operation","content":"<task-notification><task-id>%s</task-id><status>completed</status></task-notification>"}\n' "$1" >> "$TRANSCRIPT"; }

reported() { printf '%s' "$1" | grep -q '"additionalContext"'; }
blocked()  { printf '%s' "$1" | grep -q '"permissionDecision"'; }

CI='{"command":"gh pr checks 7753","description":"CI poll","timeout_ms":600000}'
CI2='{"command":"gh pr checks 7753 --json state","description":"CI again","timeout_ms":600000}'
OTHER='{"command":"gh pr checks 9999 --json state","description":"other pr","timeout_ms":600000}'

# --- POSITIVE CONTROL: the helpers can both move -----------------------------
_p=$PASS; _f=$FAIL
pass 'self-check: pass() increments (expected)'
fail 'self-check: fail() increments (EXPECTED, not a defect)'
if [ $((PASS - _p)) -ne 1 ] || [ $((FAIL - _f)) -ne 1 ]; then
  printf '[FATAL] verdict helpers are not counting\n' >&2; exit 1
fi
PASS=$_p; FAIL=$_f

# --- 1-4: the core report -----------------------------------------------------
fresh 1
out=$(guard s1 "$CI"); rc=1; reported "$out" || rc=0
verdict "$rc" 'a first monitor on a target is SILENT'

fresh 2
record s1 Monitor "$CI" '{"taskId":"T1"}'
out=$(guard s1 "$CI2"); rc=1; reported "$out" && rc=0
verdict "$rc" 'a second monitor on the SAME pr is REPORTED (the #7753 case)'

fresh 3
record s1 Monitor "$CI" '{"taskId":"T1"}'
out=$(guard s1 "$OTHER"); rc=1; reported "$out" || rc=0
verdict "$rc" 'a monitor on a DIFFERENT pr is SILENT'

fresh 4
record s1 Monitor "$CI" '{"taskId":"T1"}'
out=$(guard s2 "$CI2"); rc=1; reported "$out" || rc=0
verdict "$rc" 'another session watching the same pr is SILENT (ledger is session-scoped)'

# --- 5-7: LIVENESS IS MEASURED, not inferred ---------------------------------
# This is the redesign. An earlier version inferred liveness from the clock and
# fired mostly on monitors that had already exited.
fresh 5
record s1 Monitor "$CI" '{"taskId":"T1"}'
complete_task T1
out=$(guard s1 "$CI2"); rc=1; reported "$out" || rc=0
verdict "$rc" 'a prior monitor OBSERVED COMPLETE in the transcript is SILENT'

fresh 6
record s1 Monitor "$CI" '{"taskId":"T1"}'
record s1 TaskStop '{"task_id":"T1"}' '{}'
out=$(guard s1 "$CI2"); rc=1; reported "$out" || rc=0
verdict "$rc" 'a prior monitor STOPPED by task id is SILENT'

# The contamination control. The transcript also holds the AGENT OWN command
# text, so a naive grep reports a live monitor as finished the moment the agent
# greps for its id. Verified: without the `.type != "assistant"` filter this
# reads DEAD. Same defect class as the pgrep self-match.
fresh 7
record s1 Monitor "$CI" '{"taskId":"T1"}'
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"<task-id>T1</task-id> <status>completed</status>"}]}}\n' >> "$TRANSCRIPT"
out=$(guard s1 "$CI2"); rc=1; reported "$out" && rc=0
verdict "$rc" 'the agent OWN transcript text does not fake a completion'

# --- 8-9: the undercount the old design shipped ------------------------------
# The founding incident was THREE monitors. The previous read took `last` and
# said "two watchers", telling the agent to stop "the prior one" and leaving two.
fresh 8
record s1 Monitor "$CI" '{"taskId":"T1"}'
record s1 Monitor '{"command":"gh pr view 7753","description":"merge","timeout_ms":600000}' '{"taskId":"T2"}'
out=$(guard s1 "$CI2")
rc=1; printf '%s' "$out" | grep -q 'T1' && printf '%s' "$out" | grep -q 'T2' && rc=0
verdict "$rc" 'ALL still-live arms are named, not just the most recent'

fresh 9
record s1 Monitor "$CI" '{"taskId":"T1"}'
record s1 Monitor '{"command":"gh pr view 7753","description":"merge","timeout_ms":600000}' '{"taskId":"T2"}'
record s1 TaskStop '{"task_id":"T1"}' '{}'
out=$(guard s1 "$CI2")
rc=1; printf '%s' "$out" | grep -q 'T2' && ! printf '%s' "$out" | grep -q 'T1' && rc=0
verdict "$rc" 'stopping ONE arm clears only that arm (the stop is keyed by task id)'

# --- 10: complying must not blind the session --------------------------------
# The previous stop record was session-wide and cleared EVERY signature, so an
# agent that did the right thing got a dead gate for the rest of the session.
fresh 10
record s1 Monitor "$CI" '{"taskId":"T1"}'
record s1 TaskStop '{"task_id":"T1"}' '{}'
record s1 Monitor '{"command":"gh run list --workflow ci.yml","description":"wf","timeout_ms":600000}' '{"taskId":"T9"}'
out=$(guard s1 '{"command":"gh run list --workflow ci.yml --json x","description":"wf2","timeout_ms":600000}')
rc=1; reported "$out" && rc=0
verdict "$rc" 'a TaskStop on one target does NOT blind the gate on other targets'

# --- 11-14: ledger robustness (the silent-disable class) ---------------------
# `fromjson?` alone was the previous guard. It drops UNPARSEABLE lines, which is
# the half case 16 used to test. A line that PARSES to the wrong TYPE went
# through and killed pass 2 with "Cannot index number with string" — disarming
# the gate permanently and silently. Each of these must cost one record, no more.
i=11
for badline in 'CORRUPT NOT JSON' '12345' '"hello"' '[1,2,3]'; do
  fresh "$i"
  record s1 Monitor "$CI" '{"taskId":"T1"}'
  printf '%s\n' "$badline" >> "$LEDGER"
  out=$(guard s1 "$CI2"); rc=1; reported "$out" && rc=0
  verdict "$rc" "a ledger line [$badline] costs one record, not the gate"
  i=$((i + 1))
done

# --- 15: a string ts must not poison the comparison --------------------------
fresh 15
record s1 Monitor "$CI" '{"taskId":"T1"}'
printf '{"event":"stop","session":"s1","task":"zz","ts":"not-a-number"}\n' >> "$LEDGER"
out=$(guard s1 "$CI2"); rc=1; reported "$out" && rc=0
verdict "$rc" 'a string ts is dropped rather than poisoning the read'

# --- 16-17: THE INVARIANT — this hook never blocks, on EITHER channel --------
# `permissionDecision` is one blocking channel. `exit 2` is the other, and the
# repo documents it as "tool prevented, stdout ignored entirely". The previous
# suite asserted only the first and never captured an exit code at all, so
# swapping the final `exit 0` for `exit 2` left it green.
fresh 16
rc=0
record s1 Monitor "$CI" '{"taskId":"T1"}'
for probe in "$CI2" "$OTHER" '{"command":"tail -f /var/tmp/x.log","description":"p","timeout_ms":600000}'; do
  out=$(guard s1 "$probe")
  blocked "$out" && rc=1
done
verdict "$rc" 'no input shape produces a permissionDecision'

fresh 17
rc=0
record s1 Monitor "$CI" '{"taskId":"T1"}'
guard s1 "$CI2" >/dev/null;             [ "$RC" -eq 0 ] || rc=1   # reporting path
guard s1 "$OTHER" >/dev/null;           [ "$RC" -eq 0 ] || rc=1   # silent path
guard s1 '{"command":"x"}' >/dev/null;  [ "$RC" -eq 0 ] || rc=1   # no-signature path
if ! printf 'not json' | bash "$GUARD" >/dev/null 2>&1; then rc=1; fi
verdict "$rc" 'every path exits 0 — the hook cannot block via exit 2 either'

# --- 18-19: model-controlled input must not abort the hook -------------------
# A non-numeric timeout_ms used to hit `$(( TIMEOUT_MS / 1000 ))` under `set -u`,
# abort before the arm was written, and leave the session blind to that
# signature. That is a fourth instance of the silent-disable class this pair
# exists to remove, and no case noticed it.
fresh 18
record s1 Monitor '{"command":"gh pr checks 7753","description":"d","timeout_ms":"abc"}' '{"taskId":"T1"}'
rc=1; [ -s "$LEDGER" ] && grep -q '"task":"T1"' "$LEDGER" && rc=0
verdict "$rc" 'a non-numeric timeout_ms still records the arm (no set -u abort)'

fresh 19
record s1 Monitor '{"command":["not","a","string"],"description":"d","timeout_ms":600000}' '{"taskId":"T1"}'
out=$(guard s1 '{"command":["not","a","string"],"description":"e","timeout_ms":600000}')
rc=1; { ! reported "$out"; } && [ "$RC" -eq 0 ] && rc=0
verdict "$rc" 'a non-string command yields no signature and no crash (ADR-156/AP-020)'

# --- 20-23: signature scheme -------------------------------------------------
fresh 20
record s1 Monitor '{"ws":{"url":"wss://e.example.com/s"},"description":"w","timeout_ms":600000}' '{"taskId":"T1"}'
out=$(guard s1 '{"ws":{"url":"wss://e.example.com/s"},"description":"w2","timeout_ms":600000}')
rc=1; reported "$out" && rc=0
verdict "$rc" 'two monitors on the same ws:// url are REPORTED'

fresh 21
record s1 Monitor '{"ws":{"url":"wss://a.example.com/x"},"description":"a","timeout_ms":600000}' '{"taskId":"T1"}'
out=$(guard s1 '{"ws":{"url":"wss://b.example.com/y"},"description":"b","timeout_ms":600000}')
rc=1; reported "$out" || rc=0
verdict "$rc" 'two DIFFERENT ws:// urls do not collide'

# A ws url carries a signed token in its query string in practice. It must not
# reach the ledger: that file is plaintext, unrotated-by-default and long-lived.
fresh 22
record s1 Monitor '{"ws":{"url":"wss://e.example.com/s?token=sk-live-SECRET"},"description":"w","timeout_ms":600000}' '{"taskId":"T1"}'
rc=1; ! grep -q 'sk-live-SECRET' "$LEDGER" && grep -q 'ws:wss://e.example.com/s' "$LEDGER" && rc=0
verdict "$rc" 'a ws:// query string is stripped before the signature is stored'

# `--branch main` and `--branch feat-x` on one workflow are different targets and
# collided before the branch was folded into the signature (measured).
fresh 23
record s1 Monitor '{"command":"gh run list --workflow ci.yml --branch main","description":"m","timeout_ms":600000}' '{"taskId":"T1"}'
out=$(guard s1 '{"command":"gh run list --workflow ci.yml --branch feat-x","description":"f","timeout_ms":600000}')
rc=1; reported "$out" || rc=0
verdict "$rc" 'the same workflow on DIFFERENT branches does not collide'

# --- 24: ship Phase 7 is ONE signature, and that report is accepted ----------
# The previous case here claimed it was "verified against ship/SKILL.md" and
# constructed three distinct-signature arms. It was invented: Phase 7 is a single
# loop calling `gh pr view <n>` AND `gh pr checks <n>` on one number, so its
# retry path re-arms the SAME signature. Under a deny that was a merge blocker.
# Under a report it is a paragraph, and this pins that we accept it knowingly.
fresh 24
record s1 Monitor '{"command":"while true; do gh pr view 7753 --json state; gh pr checks 7753; sleep 30; done","description":"merge wait","timeout_ms":1800000}' '{"taskId":"T1"}'
out=$(guard s1 '{"command":"while true; do gh pr view 7753 --json state; sleep 30; done","description":"re-poll after fix","timeout_ms":1800000}')
rc=1; reported "$out" && rc=0
verdict "$rc" "ship Phase 7's re-poll IS reported — accepted, since it no longer blocks"

# --- 25: telemetry lands as a row the aggregator can key --------------------
fresh 25
: > "$INC" 2>/dev/null || true
record s1 Monitor "$CI" '{"taskId":"T1"}'
guard s1 "$CI2" >/dev/null
rc=1
[ -r "$INC" ] && jq -e 'select(.rule_id == "monitor-supersede" and .event_type == "warn")' "$INC" >/dev/null 2>&1 && rc=0
verdict "$rc" 'the firing writes a row keyed rule_id=monitor-supersede, event_type=warn'

# The full monitor command used to ride along as the incident command_snippet,
# carrying any credential in it into a second plaintext sink.
fresh 26
: > "$INC" 2>/dev/null || true
record s1 Monitor '{"command":"gh pr checks 7753 -H \"Authorization: Bearer ghp_SECRET\"","description":"d","timeout_ms":600000}' '{"taskId":"T1"}'
guard s1 '{"command":"gh pr checks 7753 -H \"Authorization: Bearer ghp_SECRET\"","description":"e","timeout_ms":600000}' >/dev/null
rc=0; grep -q 'ghp_SECRET' "$INC" 2>/dev/null && rc=1
verdict "$rc" 'the monitor command is NOT copied into the incident ledger'

# --- 27: the recorder is the only writer ------------------------------------
# Both hooks share a signature lib; only the PostToolUse one may append. If the
# PreToolUse guard also wrote, every arm would be double-counted.
fresh 27
guard s1 "$CI" >/dev/null
guard s1 "$CI2" >/dev/null
rc=1; [ ! -s "$LEDGER" ] && rc=0
verdict "$rc" 'the PreToolUse guard never writes the ledger'

# --- 28: works from any cwd --------------------------------------------------
fresh 28
record s1 Monitor "$CI" '{"taskId":"T1"}'
out=$(cd / && jq -nc --arg tp "$TRANSCRIPT" --argjson ti "$CI2" \
      '{session_id:"s1",tool_name:"Monitor",tool_input:$ti,transcript_path:$tp}' | bash "$GUARD" 2>/dev/null)
rc=1; printf '%s' "$out" | grep -q additionalContext && rc=0
verdict "$rc" 'the hook works when invoked from an unrelated cwd'

# --- 29: both delivery channels are emitted ---------------------------------
# Upstream documents systemMessage as model-visible; this repo documents
# additionalContext as the model channel and systemMessage as operator-visible.
# The sources disagree, so emit both rather than pick.
fresh 29
record s1 Monitor "$CI" '{"taskId":"T1"}'
out=$(guard s1 "$CI2")
rc=1; printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext and .systemMessage and (.hookSpecificOutput.hookEventName == "PreToolUse")' >/dev/null 2>&1 && rc=0
verdict "$rc" 'the notice is emitted on BOTH channels, with hookEventName paired'

# --- 30: a missing transcript degrades to reporting, not to silence ----------
fresh 30
record s1 Monitor "$CI" '{"taskId":"T1"}'
TRANSCRIPT="$WORK/does-not-exist.jsonl"
out=$(guard s1 "$CI2"); rc=1; reported "$out" && rc=0
verdict "$rc" 'an unreadable transcript degrades to REPORTING (never silently drops)'

printf '\n'
# Floor. `-lt` (not `-ne`) so the suite grows without churn AND so
# scripts/guard-vacuity-floor.test.sh can recognise the shape at all: its sweep
# matches -lt/-le/-ge only, and the previous -ne floor was invisible to it.
MIN_CASES=30
if [ "$CASES" -lt "$MIN_CASES" ]; then
  printf '[FATAL] vacuity floor: %d cases executed, expected at least %d\n' "$CASES" "$MIN_CASES" >&2
  exit 1
fi
if [ $((PASS + FAIL)) -ne "$CASES" ]; then
  printf '[FATAL] accounting: PASS+FAIL=%d but CASES=%d\n' "$((PASS + FAIL))" "$CASES" >&2
  exit 1
fi
if [ "$FAIL" -gt 0 ]; then printf 'FAILED: %d/%d\n' "$FAIL" "$CASES"; exit 1; fi
printf 'OK: %d/%d\n' "$PASS" "$CASES"
