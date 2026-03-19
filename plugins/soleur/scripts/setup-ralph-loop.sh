#!/usr/bin/env bash

# Ralph Loop Setup Script
# Creates state file for in-session Ralph loop.
#
# Ported from the ralph-loop plugin (Anthropic, Apache 2.0).
# Original: https://github.com/anthropics/claude-plugins-official/tree/main/plugins/ralph-loop

set -euo pipefail

# Source shared helper for repo root resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/resolve-git-root.sh" || {
  echo "Error: Not inside a git repository." >&2
  exit 1
}
PROJECT_ROOT="$GIT_COMMON_ROOT"

# Session identifier: PPID by default, overridable via RALPH_LOOP_PID for testing
_RALPH_LOOP_PID="${RALPH_LOOP_PID:-$PPID}"

# Parse arguments
PROMPT_PARTS=()
MAX_ITERATIONS=25
COMPLETION_PROMISE="null"
STUCK_THRESHOLD=3

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help)
      cat << 'HELP_EOF'
Ralph Loop - Interactive self-referential development loop

USAGE:
  /soleur:ralph-loop [PROMPT...] [OPTIONS]

ARGUMENTS:
  PROMPT...    Initial prompt to start the loop (can be multiple words without quotes)

OPTIONS:
  --max-iterations <n>           Maximum iterations before auto-stop (default: 25, 0 for unlimited)
  --completion-promise '<text>'  Promise phrase (USE QUOTES for multi-word)
  --stuck-threshold <n>          Consecutive empty responses before auto-stop (default: 3, 0 to disable)
  -h, --help                     Show this help message

DESCRIPTION:
  Starts a Ralph Loop in your CURRENT session. The stop hook prevents
  exit and feeds your output back as input until completion or iteration limit.

  To signal completion, output: <promise>YOUR_PHRASE</promise>

  Stuck detection: The loop auto-terminates when responses are idle:
  - Short responses (< 150 chars): counted as minimal
  - Idle patterns (< 200 chars): responses matching "all done", "nothing
    left to do", etc. are counted as semantically idle
  - Repetition: 3 consecutive identical responses trigger termination
  - Similarity: 3 consecutive responses sharing >=80% words trigger
    termination (catches minor variations of the same response)
  Set --stuck-threshold 0 to disable length/idle detection (repetition
  and similarity detection remain active).

EXAMPLES:
  /soleur:ralph-loop Build a todo API --completion-promise 'DONE' --max-iterations 20
  /soleur:ralph-loop --max-iterations 10 Fix the auth bug
  /soleur:ralph-loop Refactor cache layer  (default: 25 iterations)
  /soleur:ralph-loop --completion-promise 'TASK COMPLETE' Create a REST API

STOPPING:
  By reaching --max-iterations, detecting --completion-promise,
  stuck detection (N consecutive empty/idle responses), or repetition
  detection (3 identical responses). Or manually remove the state file:
  rm .claude/ralph-loop.*.local.md

MONITORING:
  # View current iteration:
  grep '^iteration:' .claude/ralph-loop.*.local.md

  # View full state:
  head -10 .claude/ralph-loop.*.local.md
HELP_EOF
      exit 0
      ;;
    --max-iterations)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --max-iterations requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --max-iterations must be a positive integer or 0, got: $2" >&2
        exit 1
      fi
      MAX_ITERATIONS="$2"
      shift 2
      ;;
    --completion-promise)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --completion-promise requires a text argument" >&2
        exit 1
      fi
      COMPLETION_PROMISE="$2"
      shift 2
      ;;
    --stuck-threshold)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --stuck-threshold requires a number argument" >&2
        exit 1
      fi
      if ! [[ "$2" =~ ^[0-9]+$ ]]; then
        echo "Error: --stuck-threshold must be a non-negative integer, got: $2" >&2
        exit 1
      fi
      STUCK_THRESHOLD="$2"
      shift 2
      ;;
    *)
      PROMPT_PARTS+=("$1")
      shift
      ;;
  esac
done

# Join all prompt parts with spaces
PROMPT="${PROMPT_PARTS[*]}"

# Validate prompt is non-empty
if [[ -z "$PROMPT" ]]; then
  echo "Error: No prompt provided" >&2
  echo "" >&2
  echo "Examples:" >&2
  echo "  /soleur:ralph-loop Build a REST API for todos" >&2
  echo "  /soleur:ralph-loop Fix the auth bug --max-iterations 20" >&2
  echo "  /soleur:ralph-loop --completion-promise 'DONE' Refactor code" >&2
  exit 1
fi

# Create state file for stop hook (markdown with YAML frontmatter)
mkdir -p "${PROJECT_ROOT}/.claude"

# Remove legacy state files (pre-PID naming) that collide across sessions
LEGACY_FILE="${PROJECT_ROOT}/.claude/ralph-loop.local.md"
if [[ -f "$LEGACY_FILE" ]]; then
  echo "Removing legacy ralph-loop state file (no session isolation)." >&2
  rm -f "$LEGACY_FILE"
fi

# Check for other sessions' active loops
for existing in "${PROJECT_ROOT}/.claude"/ralph-loop.*.local.md; do
  [[ -f "$existing" ]] || continue
  EXISTING_PID=$(basename "$existing" | sed 's/^ralph-loop\.\([0-9]*\)\.local\.md$/\1/')
  if [[ "$EXISTING_PID" =~ ^[0-9]+$ ]] && [[ "$EXISTING_PID" != "$_RALPH_LOOP_PID" ]]; then
    if kill -0 "$EXISTING_PID" 2>/dev/null; then
      echo "Warning: Another session (PID $EXISTING_PID) has an active ralph loop." >&2
      echo "  File: $existing" >&2
      echo "  Remove it to start a new loop: rm $existing" >&2
      exit 1
    else
      echo "Removing orphaned state file from dead session (PID $EXISTING_PID)." >&2
      rm -f "$existing"
    fi
  fi
done

# Quote completion promise for YAML if it contains special chars or is not null
if [[ -n "$COMPLETION_PROMISE" ]] && [[ "$COMPLETION_PROMISE" != "null" ]]; then
  COMPLETION_PROMISE_YAML="\"$COMPLETION_PROMISE\""
else
  COMPLETION_PROMISE_YAML="null"
fi

cat > "${PROJECT_ROOT}/.claude/ralph-loop.${_RALPH_LOOP_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: $COMPLETION_PROMISE_YAML
stuck_count: 0
stuck_threshold: $STUCK_THRESHOLD
last_response_hash:
repeat_count: 0
similarity_count: 0
last_response_words:
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF

# Output setup message
cat <<EOF
Ralph loop activated in this session!

Iteration: 1
Max iterations: $(if [[ $MAX_ITERATIONS -gt 0 ]]; then echo $MAX_ITERATIONS; else echo "unlimited"; fi)
Completion promise: $(if [[ "$COMPLETION_PROMISE" != "null" ]]; then echo "${COMPLETION_PROMISE//\"/} (ONLY output when TRUE - do not lie!)"; else echo "none (runs forever)"; fi)

The stop hook is now active. When you try to exit, the SAME PROMPT will be
fed back to you. You'll see your previous work in files, creating a
self-referential loop where you iteratively improve on the same task.

To monitor: head -10 .claude/ralph-loop.${_RALPH_LOOP_PID}.local.md
To cancel: rm .claude/ralph-loop.${_RALPH_LOOP_PID}.local.md

NOTE: Default cap is 25 iterations. Pass --max-iterations 0 to run
without a cap (not recommended -- stale state files trap future sessions).
EOF

# Output the initial prompt
if [[ -n "$PROMPT" ]]; then
  echo ""
  echo "$PROMPT"
fi

# Display completion promise requirements if set
if [[ "$COMPLETION_PROMISE" != "null" ]]; then
  echo ""
  echo "==================================================================="
  echo "CRITICAL - Ralph Loop Completion Promise"
  echo "==================================================================="
  echo ""
  echo "To complete this loop, output this EXACT text:"
  echo "  <promise>$COMPLETION_PROMISE</promise>"
  echo ""
  echo "STRICT REQUIREMENTS (DO NOT VIOLATE):"
  echo "  - Use <promise> XML tags EXACTLY as shown above"
  echo "  - The statement MUST be completely and unequivocally TRUE"
  echo "  - Do NOT output false statements to exit the loop"
  echo "  - Do NOT lie even if you think you should exit"
  echo ""
  echo "IMPORTANT - Do not circumvent the loop:"
  echo "  Even if you believe you're stuck, the task is impossible,"
  echo "  or you've been running too long - you MUST NOT output a"
  echo "  false promise statement. The loop is designed to continue"
  echo "  until the promise is GENUINELY TRUE. Trust the process."
  echo ""
  echo "  If the loop should stop, the promise statement will become"
  echo "  true naturally. Do not force it by lying."
  echo "==================================================================="
fi
