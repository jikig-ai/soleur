#!/usr/bin/env bash
# PreToolUse hook on Monitor.
# REPORTS — never blocks — arming a Monitor on a target this session is still
# watching, and names the task ids to stop.
#
# Source rule: hr-monitor-not-run-in-background-for-polling (AGENTS.rules.md)
# governs WHICH tool polls. This governs the tool's LIFETIME, which nothing
# enforced: a monitor is a resource, and re-scoping what you watch means
# stopping the old watcher, not layering a new one beside it.
#
# Why: 2026-09-02 — one session ran THREE monitors against `gh pr checks 7753`
# at once. Each re-scope (CI -> infra+CI -> CI) armed a new monitor and left the
# previous running; none self-terminated, because each exits only when the polled
# state goes terminal. The operator noticed; no gate did. (First-person account —
# no ledger entry corroborates it, necessarily, since this is the hook that would
# have recorded one.)
#
# LIVENESS IS MEASURED, NOT INFERRED — and this is the part to re-read before
# changing anything. An earlier revision asserted a hook "cannot observe a monitor
# finishing" and inferred liveness from the clock instead. That was false, and it
# was asserted after testing two of three routes:
#
#   1. Clock inference — "still inside its declared timeout_ms". Rejected: a
#      monitor usually ends by early exit or harness reap long before its window,
#      so this degrades into "armed recently" and fires mostly on dead monitors.
#   2. Process table — `pgrep -f <signature>`. Rejected, and instructively: the
#      agent's own Bash commands carry the PR number, so the probe matches the
#      shell asking the question. A control probe for a signature with NO monitor
#      matched its own shell.
#   3. The transcript. `transcript_path` is in the hook payload; a Monitor's
#      PostToolUse response carries `toolUseResult.taskId`; and a task's end is
#      recorded as a `<status>completed</status>` task-notification keyed to that
#      id. THIS ONE WORKS, and is what the hook uses.
#
# Route 3 has the same contamination trap as route 2 and it must be filtered
# structurally: the transcript also contains the AGENT'S OWN command text, so a
# naive `grep -F "<task-id>X</task-id>" | grep completed` reports a live monitor
# as finished the moment the agent greps for it. Verified — the filter below
# excludes `.type == "assistant"` records for exactly this reason, and a live
# task read as DEAD without it.
#
# WHY THIS STILL DOES NOT DENY, given liveness now works: the transcript's record
# shape is an undocumented harness internal with no compatibility contract. If it
# changes, every task reads NOT-DEAD — which for a report means extra noise, and
# for a deny would mean blocking every re-arm in the repo. Fail-open is only
# available at the report tier. The cost asymmetry says the same thing: a false
# notice costs a paragraph, a false deny cost a ship run.
#
# Detection (anything missing falls through to silence):
#   tool_name == Monitor
#   AND a signature is extractable (lib/monitor-sig.sh; its misses are listed there)
#   AND this session has arms on that signature
#   AND those arms are neither stopped (exact, by task id) nor observed complete
#
# Hook stdin: JSON payload with session_id + tool_name + tool_input.
# Hook stdout: JSON {hookSpecificOutput:{additionalContext}, systemMessage} when
#   reporting; silent otherwise. BOTH fields deliberately: `additionalContext` is
#   the channel this repo has verified reaches the model (phase-surface-hint.sh),
#   while `systemMessage` is documented upstream as model-visible and in-repo as
#   operator-visible. The two sources disagree; emitting both is correct under
#   either reading and costs three lines. stderr is NOT a channel here — Claude
#   Code discards a PreToolUse hook's stderr on exit 0.
# Hook exit code: 0 always.
set -uo pipefail

_HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || exit 0
[ -f "$_HOOK_DIR/lib/monitor-sig.sh" ] || exit 0
# shellcheck source=/dev/null
. "$_HOOK_DIR/lib/monitor-sig.sh" || exit 0
export SOLEUR_HOOK_NAME="monitor-supersede-guard"
# Sourced INSIDE emit(), not at the top: measured, the top-level source costs 8
# processes and ~19ms on every invocation, and emit() is reached on the
# reporting path only — well under 1% of calls.
emit() {
  if [ -f "$_HOOK_DIR/lib/incidents.sh" ]; then
    # shellcheck source=/dev/null
    . "$_HOOK_DIR/lib/incidents.sh" || return 0
  fi
  if command -v emit_incident >/dev/null 2>&1; then emit_incident "$@" || true; fi
}

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="${SOLEUR_MONITOR_LEDGER:-$PROJECT_DIR/.claude/.monitor-arms.jsonl}"

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
[ "$TOOL" = "Monitor" ] || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || exit 0
TRANSCRIPT=$(printf '%s' "$INPUT" | jq -r 'if ((.transcript_path? // null)|type)=="string" then .transcript_path else "" end' 2>/dev/null) || TRANSCRIPT=""
NOW=$(date +%s 2>/dev/null) || exit 0
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

SIG="$(monitor_sig "$INPUT")"
[ -n "$SIG" ] || exit 0
[ -r "$LEDGER" ] || exit 0

# ---- read the ledger -------------------------------------------------------
# `fromjson? | objects | select((.ts|type)=="number")` — all three filters are
# load-bearing and each was measured. `fromjson?` drops unparseable lines; that
# alone was the previous version, and it let a bare `12345` through pass 1 to
# kill pass 2 with "Cannot index number with string", disarming the gate
# PERMANENTLY and silently. `objects` drops scalars and arrays; the ts type test
# drops a string timestamp, which otherwise poisons `max` and makes every
# comparison false. Each malformed row now costs one record, which is what the
# comment here used to claim without covering.
# `tail -n 2000` is what removes the growth term: measured, an uncapped read is
# linear in file size (12s and 841MB RSS at 1M lines) while a capped one is flat
# at ~20ms from 10k lines to 1M. Rotation alone would still leave ~370ms at the
# 5MB threshold. Sound, not just faster: the query is session-scoped, a monitor
# cannot outlive its session, and the busiest observed session wrote 34 rows — so
# 2000 is ~60x the worst case, and any stop that clears an in-window arm is
# physically later than it in an append-only file, hence also inside the tail.
ROWS=$(tail -n 2000 "$LEDGER" 2>/dev/null | jq -R 'fromjson? | objects | select((.ts? | type) == "number")' 2>/dev/null) || exit 0
[ -n "$ROWS" ] || exit 0

STOPPED=$(printf '%s' "$ROWS" | jq -s -r --arg s "$SESSION" \
  '[ .[] | select(.event=="stop" and .session==$s) | (.task? // "") | select(. != "") ] | unique | join(" ")' 2>/dev/null) || STOPPED=""

CANDIDATES=$(printf '%s' "$ROWS" | jq -s -r --arg s "$SESSION" --arg sig "$SIG" --argjson now "$NOW" '
  [ .[]
    | select(.event=="arm" and .session==$s and .sig==$sig)
    # An arm with no task id predates the recorder or lost its response; fall
    # back to the old recency test for those rather than dropping them.
    | select((.task? // "") != "" or (.ts + (.window // 300) > $now))
  ] | .[] | "\(.ts)\t\(.task // "")\t\(.desc // "")"' 2>/dev/null) || exit 0
[ -n "$CANDIDATES" ] || exit 0

# ---- liveness: is this task OBSERVED complete? -----------------------------
task_is_complete() {   # $1 = task id; rc 0 => observed complete
  [ -n "${1:-}" ] || return 1
  [ -n "$TRANSCRIPT" ] && [ -r "$TRANSCRIPT" ] || return 1
  grep -F "<task-id>$1</task-id>" "$TRANSCRIPT" 2>/dev/null \
    | jq -r 'select((.type? // "") != "assistant")
             | (.content // (.message.content | if type=="string" then . else ([.[]? | .text? // empty] | join(" ")) end) // "")
             | tostring' 2>/dev/null \
    | grep -q '<status>completed</status>'
}

LIVE_N=0
LIVE_LIST=""
while IFS=$'\t' read -r a_ts a_task a_desc; do
  [ -n "${a_ts:-}" ] || continue
  case " $STOPPED " in *" $a_task "*) continue ;; esac
  task_is_complete "$a_task" && continue
  age=$(( NOW - a_ts ))
  LIVE_N=$(( LIVE_N + 1 ))
  LIVE_LIST="${LIVE_LIST}  - ${a_task:-(no task id)} — \"${a_desc}\" (armed ${age}s ago)"$'\n'
done <<EOF
$CANDIDATES
EOF

[ "$LIVE_N" -gt 0 ] || exit 0

emit monitor-supersede warn "still-live monitor on $SIG" "$SIG" 2>/dev/null || true

MSG="monitor-supersede: this session has ${LIVE_N} monitor(s) still watching ${SIG}:
${LIVE_LIST}Arming another means duplicate work on one target — for a poll loop, duplicate
requests every interval; for a ws:// stream, a second subscription — and two
reports of the same result. TaskStop the one(s) above you are replacing.
(Liveness is read from the transcript: stopped and completed monitors are
already excluded, so every task listed was still running when this was written.)"

jq -n --arg m "$MSG" '{
  hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext: $m },
  systemMessage: $m
}' 2>/dev/null || true
exit 0
