#!/usr/bin/env bash

# Ralph Loop Stop Hook
# Prevents session exit when a ralph-loop is active.
# Feeds Claude's output back as input to continue the loop.
#
# Ported from the ralph-loop plugin (Anthropic, Apache 2.0).
# Original: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop

set -euo pipefail

# Read hook input from stdin (advanced stop hook API)
HOOK_INPUT=$(cat)

# Check if ralph-loop is active
RALPH_STATE_FILE=".claude/ralph-loop.local.md"

if [[ ! -f "$RALPH_STATE_FILE" ]]; then
  # No active loop - allow exit
  exit 0
fi

# Parse markdown frontmatter (YAML between ---) and extract values
FRONTMATTER=$(sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$RALPH_STATE_FILE")
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

# Default values for backward compatibility with pre-existing state files
if [[ ! "$STUCK_COUNT" =~ ^[0-9]+$ ]]; then
  STUCK_COUNT=0
fi
if [[ ! "$STUCK_THRESHOLD" =~ ^[0-9]+$ ]]; then
  STUCK_THRESHOLD=3
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

# Get transcript path from hook input
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')

if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  echo "Warning: Ralph loop transcript not found ($TRANSCRIPT_PATH). Stopping." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

# Read last assistant message from transcript (JSONL format)
if ! grep -q '"role":"assistant"' "$TRANSCRIPT_PATH"; then
  echo "Warning: No assistant messages in transcript. Stopping." >&2
  rm "$RALPH_STATE_FILE"
  exit 0
fi

LAST_LINE=$(grep '"role":"assistant"' "$TRANSCRIPT_PATH" | tail -1)

# Parse JSON to extract text content
LAST_OUTPUT=$(echo "$LAST_LINE" | jq -r '
  .message.content |
  map(select(.type == "text")) |
  map(.text) |
  join("\n")
' 2>/dev/null) || true

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

# Update stuck counter
if [[ $RESPONSE_LENGTH -lt 20 ]]; then
  STUCK_COUNT=$((STUCK_COUNT + 1))
else
  STUCK_COUNT=0
fi

# Check stuck threshold (0 = disabled)
if [[ $STUCK_THRESHOLD -gt 0 ]] && [[ $STUCK_COUNT -ge $STUCK_THRESHOLD ]]; then
  echo "Ralph loop: terminated after $STUCK_COUNT consecutive empty responses (stuck detection)" >&2
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

# Update iteration and stuck_count in frontmatter (single sed pass, portable across macOS and Linux)
# Note: on legacy state files without stuck_count field, the sed is a no-op for that line.
# The counter will not persist across iterations. Acceptable because legacy files are only
# created by pre-stuck-detection versions of setup-ralph-loop.sh; all new loops include the field.
TEMP_FILE="${RALPH_STATE_FILE}.tmp.$$"
sed -e "s/^iteration: .*/iteration: $NEXT_ITERATION/" \
    -e "s/^stuck_count: .*/stuck_count: $STUCK_COUNT/" \
    "$RALPH_STATE_FILE" > "$TEMP_FILE"
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
