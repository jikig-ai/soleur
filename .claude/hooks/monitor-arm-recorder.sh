#!/usr/bin/env bash
# PostToolUse hook on Monitor|TaskStop. Writes the ledger that
# monitor-supersede-guard.sh (PreToolUse) reads. Writer and reader are split so
# each has one job; the signature they share lives in lib/monitor-sig.sh.
#
# WHY PostToolUse rather than PreToolUse, which is where this started:
# the task id does not EXIST at PreToolUse — it is minted by the call. Recording
# after the call buys two things the earlier design could not have:
#   1. the id, which makes the report's remedy executable (`TaskStop bh03uoznb`
#      instead of "the prior one", which an agent cannot act on unambiguously);
#   2. exact per-task stop records, so complying with a report no longer blinds
#      the session. The PreToolUse version wrote a session-wide stop row that
#      cleared EVERY signature, meaning the agent that did the right thing got a
#      dead gate for its trouble.
# It also means only monitors that actually started are recorded.
#
# Hook stdin: JSON payload (session_id, tool_name, tool_input, tool_response).
# Hook stdout: nothing, ever. This hook only writes.
# Hook exit code: 0 always. Fail-open on every path.
set -uo pipefail

_HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd -P)" || exit 0
# BASH_SOURCE-relative, not $PROJECT_DIR-relative: the lib travels with the hook,
# so the hook works from any cwd (its suite previously only passed from the repo
# root, measured).
[ -f "$_HOOK_DIR/lib/monitor-sig.sh" ] || exit 0
# shellcheck source=/dev/null
. "$_HOOK_DIR/lib/monitor-sig.sh" || exit 0
if [ -f "$_HOOK_DIR/lib/log-rotation.sh" ]; then
  # shellcheck source=/dev/null
  . "$_HOOK_DIR/lib/log-rotation.sh" || true
fi
export SOLEUR_HOOK_NAME="monitor-arm-recorder"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LEDGER="${SOLEUR_MONITOR_LEDGER:-$PROJECT_DIR/.claude/.monitor-arms.jsonl}"

INPUT="$(cat 2>/dev/null || true)"
[ -n "$INPUT" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null) || exit 0
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null) || exit 0
NOW=$(date +%s 2>/dev/null) || exit 0
case "$NOW" in ''|*[!0-9]*) exit 0 ;; esac

mkdir -p "$(dirname "$LEDGER")" 2>/dev/null || exit 0
# Rotate before appending. Every other .claude/*.jsonl sink does; this one did
# not, and grew without bound while the read path parsed all of it every call.
if declare -F rotate_if_needed >/dev/null 2>&1; then
  rotate_if_needed "$LEDGER" 2>/dev/null || true
fi

if [ "$TOOL" = "TaskStop" ]; then
  TID=$(printf '%s' "$INPUT" | jq -r 'if ((.tool_input.task_id? // null)|type)=="string" then .tool_input.task_id else "" end' 2>/dev/null) || TID=""
  [ -n "$TID" ] || exit 0
  # jq, not printf: a printf-built record is malformable by a quote in either
  # field, and jq's last-key-wins would let a crafted session id forge an arm.
  jq -nc --arg s "$SESSION" --arg t "$TID" --argjson ts "$NOW" \
    '{event:"stop", session:$s, task:$t, ts:$ts}' >> "$LEDGER" 2>/dev/null || true
  exit 0
fi

[ "$TOOL" = "Monitor" ] || exit 0

SIG="$(monitor_sig "$INPUT")"
[ -n "$SIG" ] || exit 0

TASK=$(printf '%s' "$INPUT" | jq -r '(.tool_response.taskId? // .tool_response.task_id? // "") | if type=="string" then . else "" end' 2>/dev/null) || TASK=""
DESC=$(printf '%s' "$INPUT" | jq -r 'if ((.tool_input.description? // null)|type)=="string" then .tool_input.description else "" end' 2>/dev/null | tr -d '\n\t' | cut -c1-200) || DESC=""
TIMEOUT_MS=$(printf '%s' "$INPUT" | jq -r '.tool_input.timeout_ms // 300000' 2>/dev/null) || TIMEOUT_MS=300000
PERSISTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.persistent // false' 2>/dev/null) || PERSISTENT=false
case "$TIMEOUT_MS" in ''|*[!0-9]*) TIMEOUT_MS=300000 ;; esac
[ "$PERSISTENT" = "true" ] && TIMEOUT_MS=3600000
WINDOW_S=$(( TIMEOUT_MS / 1000 ))

jq -nc --arg s "$SESSION" --arg sig "$SIG" --arg d "$DESC" --arg t "$TASK" \
       --argjson ts "$NOW" --argjson w "$WINDOW_S" \
  '{event:"arm", session:$s, sig:$sig, desc:$d, task:$t, ts:$ts, window:$w}' \
  >> "$LEDGER" 2>/dev/null || true
exit 0
