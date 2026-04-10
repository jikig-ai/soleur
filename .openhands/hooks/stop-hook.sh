#!/usr/bin/env bash
# Ralph Loop Stop Hook (OpenHands port).
# Prevents session exit when a ralph-loop is active.
# OpenHands port of plugins/soleur/hooks/stop-hook.sh.
#
# OpenHands protocol: exit 2 + JSON {"decision":"deny","reason":"..."} to block stop.
# Input: HookEvent JSON on stdin with working_dir and metadata.reason.
#
# Key difference from Claude Code version:
# - Claude Code passes last_assistant_message in stdin JSON.
# - OpenHands passes metadata.reason (the agent's stop reason).
# - Stuck/repetition/similarity detection operates on metadata.reason content.

set -euo pipefail

# Source shared helper for repo root resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESOLVE_HELPER="${SCRIPT_DIR}/../../plugins/soleur/scripts/resolve-git-root.sh"
if [[ -f "$RESOLVE_HELPER" ]]; then
  source "$RESOLVE_HELPER" || { exit 0; }
  PROJECT_ROOT="$GIT_COMMON_ROOT"
else
  # Fallback: use OPENHANDS_PROJECT_DIR or working_dir from input
  PROJECT_ROOT="${OPENHANDS_PROJECT_DIR:-$(pwd)}"
fi

_RALPH_LOOP_PID="${RALPH_LOOP_PID:-$PPID}"
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.${_RALPH_LOOP_PID}.local.md"

# --- Legacy Cleanup ---
LEGACY_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"
if [[ -f "$LEGACY_FILE" ]]; then
  echo "Ralph loop: removing legacy state file (no session isolation)." >&2
  rm -f "$LEGACY_FILE"
fi

# --- TTL Check: Auto-remove stale state files ---
TTL_HOURS=1
NOW_EPOCH=$(date +%s)
for state_file in "${PROJECT_ROOT}/.claude"/ralph-loop.*.local.md; do
  [[ -f "$state_file" ]] || continue
  OWNER_PID=$(basename "$state_file" | sed 's/^ralph-loop\.\([0-9]*\)\.local\.md$/\1/')
  if [[ "$OWNER_PID" =~ ^[0-9]+$ ]] && ! kill -0 "$OWNER_PID" 2>/dev/null; then
    echo "Ralph loop: owner process $OWNER_PID is dead ($(basename "$state_file")). Auto-removing." >&2
    rm -f "$state_file"
    continue
  fi
  STARTED_AT=$(awk '/^---$/{c++; next} c==1' "$state_file" 2>/dev/null | grep '^started_at:' | sed 's/started_at: *//' | sed 's/^"\(.*\)"$/\1/' || true)
  if [[ -n "$STARTED_AT" ]]; then
    STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || true)
    if [[ -n "$STARTED_EPOCH" ]] && [[ $((NOW_EPOCH - STARTED_EPOCH)) -gt $((TTL_HOURS * 3600)) ]]; then
      AGE_MINS=$(( (NOW_EPOCH - STARTED_EPOCH) / 60 ))
      echo "Ralph loop: stale state file detected ($(basename "$state_file"), started ${AGE_MINS}m ago). Auto-removing." >&2
      rm -f "$state_file"
    fi
  fi
done

# Check if ralph-loop is active for THIS session
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  exit 0
fi

# Read hook input from stdin
HOOK_INPUT=$(cat)

[[ -f "$RALPH_STATE_FILE" ]] || exit 0

# Parse markdown frontmatter
FRONTMATTER=$(awk '/^---$/{c++; next} c==1' "$RALPH_STATE_FILE" 2>/dev/null)
if [[ -z "$FRONTMATTER" ]]; then
  exit 0
fi

ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//' || true)
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//' || true)
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/' || true)

STUCK_COUNT=$(echo "$FRONTMATTER" | grep '^stuck_count:' | sed 's/stuck_count: *//' || true)
STUCK_THRESHOLD=$(echo "$FRONTMATTER" | grep '^stuck_threshold:' | sed 's/stuck_threshold: *//' || true)
LAST_RESPONSE_HASH=$(echo "$FRONTMATTER" | grep '^last_response_hash:' | sed 's/last_response_hash: *//' || true)
REPEAT_COUNT=$(echo "$FRONTMATTER" | grep '^repeat_count:' | sed 's/repeat_count: *//' || true)
SIMILARITY_COUNT=$(echo "$FRONTMATTER" | grep '^similarity_count:' | sed 's/similarity_count: *//' || true)
LAST_RESPONSE_WORDS=$(echo "$FRONTMATTER" | grep '^last_response_words:' | sed 's/last_response_words: *//' || true)

# Defaults for backward compatibility
[[ "$STUCK_COUNT" =~ ^[0-9]+$ ]] || STUCK_COUNT=0
[[ "$STUCK_THRESHOLD" =~ ^[0-9]+$ ]] || STUCK_THRESHOLD=3
[[ "$REPEAT_COUNT" =~ ^[0-9]+$ ]] || REPEAT_COUNT=0
[[ "$SIMILARITY_COUNT" =~ ^[0-9]+$ ]] || SIMILARITY_COUNT=0

if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Warning: Ralph loop state file corrupted (iteration: '$ITERATION'). Stopping." >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi
if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Warning: Ralph loop state file corrupted (max_iterations: '$MAX_ITERATIONS'). Stopping." >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Ralph loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

HARD_CAP=50
if [[ $ITERATION -ge $HARD_CAP ]]; then
  echo "Ralph loop: Hard safety cap ($HARD_CAP iterations) reached. Auto-removing." >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

# OpenHands passes metadata.reason instead of last_assistant_message.
# Try last_assistant_message first (forward-compat), then metadata.reason.
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // .metadata.reason // ""' 2>/dev/null || true)

# Completion promise check
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")
  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "Ralph loop: Detected <promise>$COMPLETION_PROMISE</promise>" >&2
    rm -f "$RALPH_STATE_FILE"
    exit 0
  fi
fi

# --- Stuck Detection ---
STRIPPED_OUTPUT=$(echo "$LAST_OUTPUT" | tr -d '[:space:]')
RESPONSE_LENGTH=${#STRIPPED_OUTPUT}

IS_IDLE=false
if [[ $RESPONSE_LENGTH -lt 200 ]]; then
  NORMALIZED_OUTPUT=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
  if echo "$NORMALIZED_OUTPUT" | grep -iqE '(all (done|complete|finished)|all (slash )?commands? (are |have been )?(done|complete|finished|already)|nothing (left|pending|remaining|to do|to complete)|no (active|running|pending) (commands?|tasks?|slash commands?)|session (complete|finished|done|already)|already (done|complete|finished))'; then
    IS_IDLE=true
  fi
fi

# Repetition detection
CURRENT_HASH=""
if [[ -n "$STRIPPED_OUTPUT" ]]; then
  CURRENT_HASH=$(echo "$STRIPPED_OUTPUT" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
fi
if [[ -n "$CURRENT_HASH" ]] && [[ "$CURRENT_HASH" == "$LAST_RESPONSE_HASH" ]]; then
  REPEAT_COUNT=$((REPEAT_COUNT + 1))
else
  REPEAT_COUNT=0
fi
LAST_RESPONSE_HASH="$CURRENT_HASH"

if [[ "$IS_IDLE" == "true" ]] || [[ $RESPONSE_LENGTH -lt 150 ]]; then
  STUCK_COUNT=$((STUCK_COUNT + 1))
else
  STUCK_COUNT=0
fi

if [[ $STUCK_THRESHOLD -gt 0 ]] && [[ $STUCK_COUNT -ge $STUCK_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $STUCK_COUNT consecutive empty/idle responses (stuck detection)" >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

REPEAT_THRESHOLD=3
if [[ $REPEAT_COUNT -ge $REPEAT_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $((REPEAT_COUNT + 1)) consecutive identical responses (repetition detection)" >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

# Similarity detection
CURRENT_WORDS=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')
if [[ -n "$LAST_RESPONSE_WORDS" ]] && [[ -n "$CURRENT_WORDS" ]]; then
  PREV_LINES=$(echo "$LAST_RESPONSE_WORDS" | tr ' ' '\n')
  CURR_LINES=$(echo "$CURRENT_WORDS" | tr ' ' '\n')
  PREV_N=$(echo "$PREV_LINES" | wc -l)
  CURR_N=$(echo "$CURR_LINES" | wc -l)
  COMMON=$(comm -12 <(echo "$PREV_LINES") <(echo "$CURR_LINES") | wc -l)
  UNION=$(( PREV_N + CURR_N - COMMON ))
  if [[ $UNION -gt 0 ]]; then
    SIMILARITY=$((COMMON * 100 / UNION))
  else
    SIMILARITY=0
  fi
  if [[ $SIMILARITY -ge 80 ]]; then
    SIMILARITY_COUNT=$((SIMILARITY_COUNT + 1))
  else
    SIMILARITY_COUNT=0
  fi
else
  SIMILARITY_COUNT=0
fi
LAST_RESPONSE_WORDS="$CURRENT_WORDS"

SIMILARITY_THRESHOLD=3
if [[ $SIMILARITY_COUNT -ge $SIMILARITY_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $((SIMILARITY_COUNT + 1)) consecutive similar responses (similarity detection)" >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

# Continue loop
NEXT_ITERATION=$((ITERATION + 1))
[[ -f "$RALPH_STATE_FILE" ]] || exit 0

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE" 2>/dev/null)
if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Warning: No prompt text in state file. Stopping." >&2
  rm -f "$RALPH_STATE_FILE"
  exit 0
fi

# Update state file
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
awk -v iter="$NEXT_ITERATION" -v sc="$STUCK_COUNT" -v lrh="$LAST_RESPONSE_HASH" -v rc="$REPEAT_COUNT" -v simc="$SIMILARITY_COUNT" -v lrw="$LAST_RESPONSE_WORDS" '
  /^---$/ { c++; print; next }
  c==1 && /^iteration:/ { print "iteration: " iter; next }
  c==1 && /^stuck_count:/ { print "stuck_count: " sc; next }
  c==1 && /^last_response_hash:/ { print "last_response_hash: " lrh; next }
  c==1 && /^repeat_count:/ { print "repeat_count: " rc; next }
  c==1 && /^similarity_count:/ { print "similarity_count: " simc; next }
  c==1 && /^last_response_words:/ { print "last_response_words: " lrw; next }
  { print }
' "$RALPH_STATE_FILE" > "$TEMP_FILE" 2>/dev/null || true
if [[ -s "$TEMP_FILE" ]]; then
  mv "$TEMP_FILE" "$RALPH_STATE_FILE"
else
  rm -f "$TEMP_FILE"
  exit 0
fi

# Build block response with prompt injection
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="Ralph iteration $NEXT_ITERATION | To stop: output <promise>$COMPLETION_PROMISE</promise> (ONLY when statement is TRUE - do not lie to exit!)"
else
  SYSTEM_MSG="Ralph iteration $NEXT_ITERATION | No completion promise set - loop runs infinitely"
fi

# Block the stop and feed prompt back via reason field
jq -n \
  --arg reason "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{"decision":"deny","reason":($msg + "\n\n" + $reason)}'
exit 2
