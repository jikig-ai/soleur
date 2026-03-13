#!/usr/bin/env bash

# Ralph Loop Stop Hook
# Prevents session exit when a ralph-loop is active.
# Feeds Claude's output back as input to continue the loop.
#
# Ported from the ralph-loop plugin (Anthropic, Apache 2.0).
# Original: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop

set -euo pipefail

# Resolve project root (worktree-safe: CWD may be .worktrees/feat-* instead of repo root)
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."
RALPH_STATE_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"

# Check if ralph-loop is active BEFORE reading stdin
if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop - allow exit
  exit 0
fi

# --- TTL Check: Auto-remove stale state files from crashed sessions ---
# When a session crashes or context is exhausted, the state file persists and
# traps all subsequent sessions in an infinite loop. The started_at timestamp
# lets us detect orphaned state files and clean them up automatically.
TTL_HOURS=1
STARTED_AT=$(awk '/^---$/{c++; next} c==1' "$RALPH_STATE_FILE" | grep '^started_at:' | sed 's/started_at: *//' | sed 's/^"\(.*\)"$/\1/' || true)
if [[ -n "$STARTED_AT" ]]; then
  STARTED_EPOCH=$(date -d "$STARTED_AT" +%s 2>/dev/null || true)
  NOW_EPOCH=$(date +%s)
  if [[ -n "$STARTED_EPOCH" ]] && [[ $((NOW_EPOCH - STARTED_EPOCH)) -gt $((TTL_HOURS * 3600)) ]]; then
    AGE_MINS=$(( (NOW_EPOCH - STARTED_EPOCH) / 60 ))
    echo "Ralph loop: stale state file detected (started ${AGE_MINS}m ago, TTL=${TTL_HOURS}h). Auto-removing." >&2
    rm "$RALPH_STATE_FILE"
    exit 0
  fi
fi

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)

# Parse markdown frontmatter (YAML between first and second --- only)
FRONTMATTER=$(awk '/^---$/{c++; next} c==1' "$RALPH_STATE_FILE")
ITERATION=$(echo "$FRONTMATTER" | grep '^iteration:' | sed 's/iteration: *//')
MAX_ITERATIONS=$(echo "$FRONTMATTER" | grep '^max_iterations:' | sed 's/max_iterations: *//')
# Extract completion_promise and strip surrounding quotes if present
COMPLETION_PROMISE=$(echo "$FRONTMATTER" | grep '^completion_promise:' | sed 's/completion_promise: *//' | sed 's/^"\(.*\)"$/\1/')

# --- Stuck Detection ---
# Parse stuck detection fields from frontmatter
# CRITICAL: || true guards prevent grep exit 1 from aborting under set -euo pipefail
# when fields are missing (pre-existing state files without stuck_count/stuck_threshold)
STUCK_COUNT=$(echo "$FRONTMATTER" | grep '^stuck_count:' | sed 's/stuck_count: *//' || true)
STUCK_THRESHOLD=$(echo "$FRONTMATTER" | grep '^stuck_threshold:' | sed 's/stuck_threshold: *//' || true)
LAST_RESPONSE_HASH=$(echo "$FRONTMATTER" | grep '^last_response_hash:' | sed 's/last_response_hash: *//' || true)
REPEAT_COUNT=$(echo "$FRONTMATTER" | grep '^repeat_count:' | sed 's/repeat_count: *//' || true)

# Default values for backward compatibility with pre-existing state files
if [[ ! "$STUCK_COUNT" =~ ^[0-9]+$ ]]; then
  STUCK_COUNT=0
fi
if [[ ! "$STUCK_THRESHOLD" =~ ^[0-9]+$ ]]; then
  STUCK_THRESHOLD=3
fi
if [[ ! "$REPEAT_COUNT" =~ ^[0-9]+$ ]]; then
  REPEAT_COUNT=0
fi

# Validate numeric fields before arithmetic operations
if [[ ! "$ITERATION" =~ ^[0-9]+$ ]]; then
  echo "Warning: Ralph loop state file corrupted (iteration: '$ITERATION'). Stopping." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

if [[ ! "$MAX_ITERATIONS" =~ ^[0-9]+$ ]]; then
  echo "Warning: Ralph loop state file corrupted (max_iterations: '$MAX_ITERATIONS'). Stopping." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Check if max iterations reached
if [[ $MAX_ITERATIONS -gt 0 ]] && [[ $ITERATION -ge $MAX_ITERATIONS ]]; then
  echo "Ralph loop: Max iterations ($MAX_ITERATIONS) reached." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# --- Hard Safety Valve ---
# Even with max_iterations=0 (unlimited), cap at 50 to prevent runaway loops
# from trapping sessions indefinitely (e.g., after context compaction).
HARD_CAP=50
if [[ $ITERATION -ge $HARD_CAP ]]; then
  echo "Ralph loop: Hard safety cap ($HARD_CAP iterations) reached. Auto-removing." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Extract last assistant message directly from hook input (stop hook API)
LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')

# Empty LAST_OUTPUT is valid for tool-use-only responses -- do not terminate
# The stuck detection counter below handles repeated empty outputs

# Check for completion promise (only if set)
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  # Extract text from <promise> tags using Perl for multiline support
  PROMISE_TEXT=$(echo "$LAST_OUTPUT" | perl -0777 -pe 's/.*?<promise>(.*?)<\/promise>.*/$1/s; s/^\s+|\s+$//g; s/\s+/ /g' 2>/dev/null || echo "")

  # Use = for literal string comparison (not glob pattern matching)
  if [[ -n "$PROMISE_TEXT" ]] && [[ "$PROMISE_TEXT" = "$COMPLETION_PROMISE" ]]; then
    echo "Ralph loop: Detected <promise>$COMPLETION_PROMISE</promise>" >&2
    rm "$RALPH_STATE_FILE"
    exit 0
  fi
fi

# --- Stuck Detection: Measure and Update ---
# Measure response substantiveness (strip whitespace, check length)
# Note: LAST_OUTPUT may be empty for tool-use-only responses (jq text extraction
# yields nothing when all content blocks are type "tool_use"). This is fine --
# empty string has length 0, which counts as minimal.
STRIPPED_OUTPUT=$(echo "$LAST_OUTPUT" | tr -d '[:space:]')
RESPONSE_LENGTH=${#STRIPPED_OUTPUT}

# --- Idle Pattern Detection ---
# Responses that say "nothing to do" in >20 chars fool the length check.
# Only apply to short-ish responses (< 200 chars stripped) to avoid false positives
# on substantive responses that contain idle phrases as substrings.
# Verified: the `if` statement absorbs grep exit 1 under set -euo pipefail.
IS_IDLE=false
if [[ $RESPONSE_LENGTH -lt 200 ]]; then
  NORMALIZED_OUTPUT=$(echo "$LAST_OUTPUT" | tr '[:upper:]' '[:lower:]' | tr -s '[:space:]' ' ' | sed 's/^ *//;s/ *$//')
  if echo "$NORMALIZED_OUTPUT" | grep -iqE '(all (done|complete|finished)|all (slash )?commands? (are |have been )?(done|complete|finished|already)|nothing (left|pending|remaining|to do|to complete|to run)|no (active|running|pending) (commands?|tasks?|slash commands?)|session (complete|finished|done|already)|already (done|complete|finished))'; then
    IS_IDLE=true
  fi
fi

# --- Repetition Detection ---
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

# Update stuck counter: idle patterns OR short responses increment, substantive resets
# Three tiers:
#   < 20 chars: definitely minimal (existing behavior)
#   20-199 chars + idle pattern: semantically idle (new)
#   >= 200 chars: always substantive (long enough to contain real work)
if [[ "$IS_IDLE" == "true" ]] || [[ $RESPONSE_LENGTH -lt 20 ]]; then
  STUCK_COUNT=$((STUCK_COUNT + 1))
else
  STUCK_COUNT=0
fi

# Check stuck threshold (0 = disabled)
if [[ $STUCK_THRESHOLD -gt 0 ]] && [[ $STUCK_COUNT -ge $STUCK_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $STUCK_COUNT consecutive empty/idle responses (stuck detection)" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Check repetition threshold (3 identical consecutive responses)
REPEAT_THRESHOLD=3
if [[ $REPEAT_COUNT -ge $REPEAT_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $((REPEAT_COUNT + 1)) consecutive identical responses (repetition detection)" >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Not complete - continue loop with SAME PROMPT
NEXT_ITERATION=$((ITERATION + 1))

# Extract prompt (everything after the closing ---)
PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$RALPH_STATE_FILE")

if [[ -z "$PROMPT_TEXT" ]]; then
  echo "Warning: No prompt text in state file. Stopping." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Update iteration and stuck_count in first frontmatter block only (awk scoped to c==1)
# Note: on legacy state files without stuck_count field, the awk match is a no-op for that line.
# The counter will not persist across iterations. Acceptable because legacy files are only
# created by pre-stuck-detection versions of setup-ralph-loop.sh; all new loops include the field.
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
awk -v iter="$NEXT_ITERATION" -v sc="$STUCK_COUNT" -v lrh="$LAST_RESPONSE_HASH" -v rc="$REPEAT_COUNT" '
  /^---$/ { c++; print; next }
  c==1 && /^iteration:/ { print "iteration: " iter; next }
  c==1 && /^stuck_count:/ { print "stuck_count: " sc; next }
  c==1 && /^last_response_hash:/ { print "last_response_hash: " lrh; next }
  c==1 && /^repeat_count:/ { print "repeat_count: " rc; next }
  { print }
' "$RALPH_STATE_FILE" > "$TEMP_FILE"
mv "$TEMP_FILE" "$RALPH_STATE_FILE"

# Build system message with iteration count and completion promise info
if [[ "$COMPLETION_PROMISE" != "null" ]] && [[ -n "$COMPLETION_PROMISE" ]]; then
  SYSTEM_MSG="Ralph iteration $NEXT_ITERATION | To stop: output <promise>$COMPLETION_PROMISE</promise> (ONLY when statement is TRUE - do not lie to exit!)"
else
  SYSTEM_MSG="Ralph iteration $NEXT_ITERATION | No completion promise set - loop runs infinitely"
fi

# Output JSON to block the stop and feed prompt back
jq -n \
  --arg prompt "$PROMPT_TEXT" \
  --arg msg "$SYSTEM_MSG" \
  '{
    "decision": "block",
    "reason": $prompt,
    "systemMessage": $msg
  }'

exit 0
