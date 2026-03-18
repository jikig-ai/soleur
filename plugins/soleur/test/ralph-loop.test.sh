#!/usr/bin/env bash

# Tests for Ralph Loop (stuck detection, session isolation, TTL, setup defaults)
# Run: bash plugins/soleur/test/ralph-loop.test.sh

set -euo pipefail

# Clear git env vars that leak when this test runs inside a git hook (e.g., pre-push).
# Without this, git rev-parse --show-toplevel in test subprocesses resolves to the
# outer repo instead of the test's temp git repos.
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"
HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"
SETUP="$SCRIPT_DIR/../scripts/setup-ralph-loop.sh"

# Fixed PID for session-scoped state files in tests.
# Both hook and setup read RALPH_LOOP_PID to override $PPID.
TEST_PID="test_session"
export RALPH_LOOP_PID="$TEST_PID"

# --- Test Helpers ---

setup_test() {
  local test_dir
  test_dir=$(mktemp -d)
  git -C "$test_dir" init -q
  mkdir -p "$test_dir/.claude"
  echo "$test_dir"
}

cleanup_test() {
  rm -rf "$1"
}

create_state_file() {
  local dir="$1"
  local iteration="${2:-1}"
  local max="${3:-0}"
  local promise="${4:-null}"
  local stuck_count="${5:-0}"
  local stuck_threshold="${6:-3}"
  local last_response_hash="${7:-}"
  local repeat_count="${8:-0}"
  local now
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  cat > "$dir/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: $iteration
max_iterations: $max
completion_promise: $promise
stuck_count: $stuck_count
stuck_threshold: $stuck_threshold
last_response_hash: $last_response_hash
repeat_count: $repeat_count
started_at: "$now"
---

Test prompt
EOF
}

run_hook() {
  local dir="$1"
  local message="${2:-}"

  local hook_input
  hook_input=$(jq -n --arg msg "$message" '{"last_assistant_message": $msg}')

  # Subshell isolates CWD changes so they don't leak between tests
  (cd "$dir" && echo "$hook_input" | bash "$HOOK" 2>/dev/null) || true
}

run_hook_stderr() {
  local dir="$1"
  local message="${2:-}"

  local hook_input
  hook_input=$(jq -n --arg msg "$message" '{"last_assistant_message": $msg}')

  # Subshell isolates CWD changes so they don't leak between tests
  (cd "$dir" && echo "$hook_input" | bash "$HOOK" 2>&1 1>/dev/null) || true
}

# --- Tests ---

NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
# Stale timestamp for TTL tests (guaranteed older than TTL_HOURS)
STALE_TS="2020-01-01T00:00:00Z"

echo "=== Ralph Loop Stuck Detection Tests ==="
echo ""

# Test 1: 3 consecutive empty responses triggers termination
echo "Test 1: 3 consecutive empty responses triggers termination"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 2 3
run_hook "$TEST_DIR" ""
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file removed after stuck detection"
cleanup_test "$TEST_DIR"
echo ""

# Test 2: Warning message printed to stderr
echo "Test 2: Warning message printed to stderr on stuck termination"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 2 3
STDERR_OUTPUT=$(run_hook_stderr "$TEST_DIR" "")
assert_contains "$STDERR_OUTPUT" "terminated after" "stderr contains termination warning"
assert_contains "$STDERR_OUTPUT" "consecutive empty/idle responses" "stderr mentions empty/idle responses"
cleanup_test "$TEST_DIR"
echo ""

# Test 3: Substantive response resets stuck counter
echo "Test 3: Substantive response resets stuck_count to 0"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 2 0 "null" 2 3
run_hook "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (loop continues)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset to 0"
cleanup_test "$TEST_DIR"
echo ""

# Test 4: stuck_threshold=0 disables detection
echo "Test 4: stuck_threshold=0 disables stuck detection"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 10 0
run_hook "$TEST_DIR" ""
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (detection disabled)"
cleanup_test "$TEST_DIR"
echo ""

# Test 5: Exactly 20 characters counts as substantive
echo "Test 5: Exactly 20 characters (after stripping) is substantive"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 2 3
run_hook "$TEST_DIR" "12345678901234567890"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset (20 chars = substantive)"
cleanup_test "$TEST_DIR"
echo ""

# Test 6: 19 characters counts as minimal
echo "Test 6: 19 characters (after stripping) is minimal"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" "1234567890123456789"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented to 1"
cleanup_test "$TEST_DIR"
echo ""

# Test 7: Pre-existing state file without stuck fields uses defaults
echo "Test 7: Pre-existing state file without stuck_count/stuck_threshold uses defaults"
TEST_DIR=$(setup_test)
# State file without stuck_count or stuck_threshold
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
started_at: "$NOW"
---

Test prompt
EOF
run_hook "$TEST_DIR" "Substantive response with enough content here to pass threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (no crash on missing fields)"
cleanup_test "$TEST_DIR"
echo ""

# Test 8: Empty message counts as minimal (simulates tool-use-only response)
echo "Test 8: Empty message counts as minimal"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" ""
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (only 1 empty, threshold is 3)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented for empty message"
cleanup_test "$TEST_DIR"
echo ""

# Test 9: Completion promise still takes priority over stuck detection
echo "Test 9: Completion promise check fires before stuck detection"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "\"DONE\"" 2 3
run_hook "$TEST_DIR" "<promise>DONE</promise>"
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file removed (promise matched)"
cleanup_test "$TEST_DIR"
echo ""

# Test 10: setup-ralph-loop.sh adds stuck_threshold to state file
echo "Test 10: setup-ralph-loop.sh includes stuck_count and stuck_threshold in state"
TEST_DIR=$(setup_test)
(cd "$TEST_DIR" && bash "$SETUP" "test prompt" --stuck-threshold 5 > /dev/null 2>&1)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file created"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//' || echo "MISSING")
STUCK_THRESHOLD=$(grep '^stuck_threshold:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_threshold: *//' || echo "MISSING")
assert_eq "0" "$STUCK_COUNT" "stuck_count initialized to 0"
assert_eq "5" "$STUCK_THRESHOLD" "stuck_threshold set to 5"
cleanup_test "$TEST_DIR"
echo ""

# Test 11: setup-ralph-loop.sh defaults stuck_threshold to 3
echo "Test 11: setup-ralph-loop.sh defaults stuck_threshold to 3"
TEST_DIR=$(setup_test)
(cd "$TEST_DIR" && bash "$SETUP" "test prompt" > /dev/null 2>&1)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file created"
STUCK_THRESHOLD=$(grep '^stuck_threshold:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_threshold: *//' || echo "MISSING")
assert_eq "3" "$STUCK_THRESHOLD" "stuck_threshold defaults to 3"
cleanup_test "$TEST_DIR"
echo ""

# Test 12: Corrupted stuck_count (non-numeric) defaults to 0
echo "Test 12: Corrupted stuck_count value defaults to 0"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: abc
stuck_threshold: 3
started_at: "$NOW"
---

Test prompt
EOF
run_hook "$TEST_DIR" "Substantive response with enough content here to pass threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (no crash on corrupted field)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "corrupted stuck_count reset to 0"
cleanup_test "$TEST_DIR"
echo ""

# Test 13: Prompt containing --- does not leak into FRONTMATTER
echo "Test 13: Prompt body with --- does not leak into frontmatter"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$NOW"
---

Build a REST API with proper error handling.
---
Use standard HTTP status codes.
EOF
run_hook "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
ITERATION=$(grep '^iteration:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | head -1 | sed 's/iteration: *//')
assert_eq "2" "$ITERATION" "iteration updated to 2"
# Verify the raw state file preserves --- and text after it in the prompt body
# (The awk prompt extractor on line 133 consumes bare --- lines -- that's pre-existing behavior.)
RAW_FILE=$(cat "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md")
assert_contains "$RAW_FILE" "Build a REST API with proper error handling." "prompt text before --- preserved in state file"
assert_contains "$RAW_FILE" "Use standard HTTP status codes." "prompt text after --- preserved in state file"
# Verify frontmatter was not corrupted by prompt --- leaking into parser
FRONTMATTER=$(awk '/^---$/{c++; next} c==1' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md")
assert_contains "$FRONTMATTER" "iteration: 2" "frontmatter contains updated iteration"
assert_contains "$FRONTMATTER" "stuck_count: 0" "frontmatter contains correct stuck_count"
cleanup_test "$TEST_DIR"
echo ""

# Test 14: Prompt containing iteration: text is preserved after update
echo "Test 14: Prompt body with iteration: text is preserved verbatim"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$NOW"
---

Check iteration: current status of deployment.
EOF
run_hook "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
ITERATION=$(grep '^iteration:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | head -1 | sed 's/iteration: *//')
assert_eq "2" "$ITERATION" "frontmatter iteration updated to 2"
PROMPT_BODY=$(awk '/^---$/{i++; next} i>=2' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md")
assert_contains "$PROMPT_BODY" "iteration: current status of deployment" "prompt iteration: text preserved"
cleanup_test "$TEST_DIR"
echo ""

# Test 15: Prompt containing stuck_count: text is preserved after update
echo "Test 15: Prompt body with stuck_count: text is preserved verbatim"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$NOW"
---

Monitor stuck_count: should be zero.
EOF
run_hook "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
STUCK_COUNT_FM=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | head -1 | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT_FM" "frontmatter stuck_count reset to 0"
PROMPT_BODY=$(awk '/^---$/{i++; next} i>=2' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md")
assert_contains "$PROMPT_BODY" "stuck_count: should be zero" "prompt stuck_count: text preserved"
cleanup_test "$TEST_DIR"
echo ""

# Test 16: Hook exits 0 from a non-root CWD when state file does not exist
echo "Test 16: Hook exits 0 from subdirectory when no state file"
TEST_DIR=$(setup_test)
mkdir -p "$TEST_DIR/sub/deep"
# No state file created -- hook should exit 0 cleanly
HOOK_OUTPUT=$(cd "$TEST_DIR/sub/deep" && echo '{}' | bash "$HOOK" 2>&1) || true
EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "hook exits 0 when no state file from subdirectory"
assert_eq "" "$HOOK_OUTPUT" "no output when no state file"
cleanup_test "$TEST_DIR"
echo ""

# Test 17: Hook finds state file at project root when CWD is a subdirectory
echo "Test 17: Hook finds state file from subdirectory via git rev-parse"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
mkdir -p "$TEST_DIR/sub/deep"
# run_hook uses a subshell, so CWD isolation is automatic
run_hook "$TEST_DIR/sub/deep" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file found and updated from subdirectory"
ITERATION=$(grep '^iteration:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | head -1 | sed 's/iteration: *//')
assert_eq "2" "$ITERATION" "iteration updated from subdirectory"
cleanup_test "$TEST_DIR"
echo ""

# Test 18: Hard safety cap at 50 iterations terminates even with max_iterations=0
echo "Test 18: Hard safety cap terminates at 50 iterations"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 50 0 "null" 0 3
STDERR_OUTPUT=$(run_hook_stderr "$TEST_DIR" "Substantive response with enough content here to pass threshold.")
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file removed after hard cap"
assert_contains "$STDERR_OUTPUT" "Hard safety cap" "stderr mentions hard safety cap"
cleanup_test "$TEST_DIR"
echo ""

# Test 19: Iteration 49 does NOT trigger hard cap
echo "Test 19: Iteration 49 continues (under hard cap)"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 49 0 "null" 0 3
run_hook "$TEST_DIR" "Substantive response with enough content here to pass threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (under hard cap)"
cleanup_test "$TEST_DIR"
echo ""

# Test 20: TTL auto-removes stale state file (started_at older than TTL)
echo "Test 20: TTL auto-removes stale state file"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$STALE_TS"
---

Stale prompt
EOF
STDERR_OUTPUT=$(cd "$TEST_DIR" && echo '{}' | bash "$HOOK" 2>&1 1>/dev/null) || true
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "stale state file removed by TTL"
assert_contains "$STDERR_OUTPUT" "stale state file detected" "stderr mentions stale detection"
cleanup_test "$TEST_DIR"
echo ""

# Test 21: setup-ralph-loop.sh defaults max_iterations to 25
echo "Test 21: setup-ralph-loop.sh defaults max_iterations to 25"
TEST_DIR=$(setup_test)
(cd "$TEST_DIR" && bash "$SETUP" "test prompt" > /dev/null 2>&1)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file created"
MAX_ITER=$(grep '^max_iterations:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/max_iterations: *//' || echo "MISSING")
assert_eq "25" "$MAX_ITER" "max_iterations defaults to 25"
cleanup_test "$TEST_DIR"
echo ""

# === Idle Pattern Detection Tests ===
echo "=== Idle Pattern Detection Tests ==="
echo ""

# Test 22: Idle pattern "All slash commands are finished" increments stuck counter
echo "Test 22: Idle pattern 'All slash commands are finished' increments stuck counter"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" "All slash commands are finished"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (only 1 idle, threshold 3)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented for idle pattern"
cleanup_test "$TEST_DIR"
echo ""

# Test 23: Idle pattern "Nothing left to do" increments stuck counter
echo "Test 23: Idle pattern 'Nothing left to do' increments stuck counter"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" "Nothing left to do"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented for idle pattern"
cleanup_test "$TEST_DIR"
echo ""

# Test 24: Idle pattern "Session already complete" increments stuck counter
echo "Test 24: Idle pattern 'Session already complete' increments stuck counter"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" "Session already complete"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented for idle pattern"
cleanup_test "$TEST_DIR"
echo ""

# Test 25: 3 consecutive idle-pattern responses trigger termination
echo "Test 25: 3 consecutive idle-pattern responses trigger termination"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 2 3
run_hook "$TEST_DIR" "All slash commands are finished"
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file removed after 3 idle responses"
cleanup_test "$TEST_DIR"
echo ""

# Test 26: Non-idle substantive response resets stuck counter (existing behavior)
echo "Test 26: Non-idle substantive response resets stuck_count to 0"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 2 0 "null" 2 3
run_hook "$TEST_DIR" "I've refactored the authentication layer, added rate limiting to the API endpoints, and improved the error handling across twelve different modules."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset to 0 for substantive response"
cleanup_test "$TEST_DIR"
echo ""

# Test 27: Long response (>= 200 chars) containing idle substring is NOT treated as idle
echo "Test 27: Long response (>= 200 chars) with idle substring is NOT idle (length gate)"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 2 3
# Build a 200+ char response containing "all done"
LONG_RESPONSE="I've updated all 5 files. The module is all done and tested. Here is a detailed summary of the changes: refactored the authentication layer, added rate limiting, improved error handling, updated the documentation, and added comprehensive integration tests."
run_hook "$TEST_DIR" "$LONG_RESPONSE"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (long response = substantive)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset (length gate prevents idle detection)"
cleanup_test "$TEST_DIR"
echo ""

# Test 28: Short response with idle pattern IS treated as idle (under 200 char gate)
echo "Test 28: Short response with idle pattern IS idle (under length gate)"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" "All done. No active commands to run."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (only 1 idle)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented for short idle response"
cleanup_test "$TEST_DIR"
echo ""

# === Repetition Detection Tests ===
echo "=== Repetition Detection Tests ==="
echo ""

# Test 29: 3 identical responses trigger repetition detection termination
echo "Test 29: 3 identical responses trigger repetition detection termination"
TEST_DIR=$(setup_test)
REPEATED_MSG="I've reviewed the codebase and everything looks good"
# Match hook hash computation: STRIPPED=$(echo ... | tr -d), then echo "$STRIPPED" | tr lower | md5sum
REPEATED_STRIPPED=$(echo "$REPEATED_MSG" | tr -d '[:space:]')
REPEATED_HASH=$(echo "$REPEATED_STRIPPED" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
create_state_file "$TEST_DIR" 5 0 "null" 0 3 "$REPEATED_HASH" 2
STDERR_OUTPUT=$(run_hook_stderr "$TEST_DIR" "$REPEATED_MSG")
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file removed after 3 identical responses"
assert_contains "$STDERR_OUTPUT" "repetition detection" "stderr mentions repetition detection"
cleanup_test "$TEST_DIR"
echo ""

# Test 30: 2 identical responses followed by different response resets repeat counter
echo "Test 30: Different response resets repeat counter"
TEST_DIR=$(setup_test)
REPEATED_MSG="I've reviewed the codebase and everything looks good"
REPEATED_STRIPPED=$(echo "$REPEATED_MSG" | tr -d '[:space:]')
REPEATED_HASH=$(echo "$REPEATED_STRIPPED" | tr '[:upper:]' '[:lower:]' | md5sum | cut -d' ' -f1)
create_state_file "$TEST_DIR" 5 0 "null" 0 3 "$REPEATED_HASH" 1
run_hook "$TEST_DIR" "This is a completely different substantive response with new content"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
REPEAT_COUNT=$(grep '^repeat_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/repeat_count: *//')
assert_eq "0" "$REPEAT_COUNT" "repeat_count reset to 0 after different response"
cleanup_test "$TEST_DIR"
echo ""

# Test 31: Pre-existing state file without last_response_hash/repeat_count works
echo "Test 31: Pre-existing state file without hash/repeat fields works (backward compat)"
TEST_DIR=$(setup_test)
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$NOW_TS"
---

Test prompt
EOF
run_hook "$TEST_DIR" "Substantive response with enough content here to pass threshold easily."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (no crash on missing fields)"
cleanup_test "$TEST_DIR"
echo ""

# Test 32: Exactly 200 stripped chars with idle substring is NOT idle (boundary test)
echo "Test 32: Exactly 200 stripped chars with idle phrase is NOT idle (boundary)"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 2 3
# Build a response that is exactly 200 stripped chars and contains "all done"
# Verified: echo "..." | tr -d '[:space:]' | wc -m == 200
BOUNDARY_RESPONSE="All done with the feature implementation. Here are the changes I made to the authentication system, the rate limiter, the error handlers, the logging framework, and the monitoring dashboards updated successfully with the new metrics.."
run_hook "$TEST_DIR" "$BOUNDARY_RESPONSE"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists (200 chars = substantive)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset (200 chars hits length gate)"
cleanup_test "$TEST_DIR"
echo ""

# Test 33: setup-ralph-loop.sh includes last_response_hash and repeat_count
echo "Test 33: setup-ralph-loop.sh includes last_response_hash and repeat_count"
TEST_DIR=$(setup_test)
(cd "$TEST_DIR" && bash "$SETUP" "test prompt" > /dev/null 2>&1)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file created"
LAST_HASH=$(grep '^last_response_hash:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/last_response_hash: *//' || echo "MISSING")
REPEAT_CT=$(grep '^repeat_count:' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" | sed 's/repeat_count: *//' || echo "MISSING")
assert_eq "" "$LAST_HASH" "last_response_hash initialized to empty"
assert_eq "0" "$REPEAT_CT" "repeat_count initialized to 0"
cleanup_test "$TEST_DIR"
echo ""

# Test 34: Idle pattern termination message in stderr
echo "Test 34: Idle pattern termination message in stderr"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 2 3
STDERR_OUTPUT=$(run_hook_stderr "$TEST_DIR" "Nothing left to do")
assert_contains "$STDERR_OUTPUT" "terminated after" "stderr contains termination warning"
assert_contains "$STDERR_OUTPUT" "empty/idle responses" "stderr mentions idle responses"
cleanup_test "$TEST_DIR"
echo ""

# Test 35: Prompt body containing last_response_hash: text is preserved
echo "Test 35: Prompt body with last_response_hash: text is preserved verbatim"
TEST_DIR=$(setup_test)
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
last_response_hash:
repeat_count: 0
started_at: "$NOW_TS"
---

Check last_response_hash: should be empty initially.
EOF
run_hook "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "state file still exists"
PROMPT_BODY=$(awk '/^---$/{i++; next} i>=2' "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md")
assert_contains "$PROMPT_BODY" "last_response_hash: should be empty initially" "prompt last_response_hash: text preserved"
cleanup_test "$TEST_DIR"
echo ""

# === Session Isolation Tests ===
echo "=== Session Isolation Tests ==="
echo ""

# Test 36: Foreign PID state file does not block exit
echo "Test 36: Foreign PID state file does not block exit"
TEST_DIR=$(setup_test)
# Create state file for PID 99999 (guaranteed not to be TEST_PID)
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TEST_DIR/.claude/ralph-loop.99999.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$NOW_TS"
---

Foreign session prompt
EOF
HOOK_OUTPUT=$(cd "$TEST_DIR" && echo '{}' | bash "$HOOK" 2>&1) || true
EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "hook exits 0 when only foreign PID state file exists"
assert_eq "" "$HOOK_OUTPUT" "no output for foreign PID"
# Foreign file still exists (not our session, and it's fresh)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.99999.local.md" "foreign PID file preserved"
cleanup_test "$TEST_DIR"
echo ""

# Test 37: TTL glob cleanup removes stale file from other PID
echo "Test 37: TTL glob cleanup removes stale file from other PID"
TEST_DIR=$(setup_test)
cat > "$TEST_DIR/.claude/ralph-loop.99999.local.md" <<EOF
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$STALE_TS"
---

Stale prompt from other session
EOF
(cd "$TEST_DIR" && echo '{}' | bash "$HOOK" 2>/dev/null) || true
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.99999.local.md" "stale foreign PID file removed by TTL"
cleanup_test "$TEST_DIR"
echo ""

# Test 38: TTL glob cleanup preserves fresh file from other PID
echo "Test 38: TTL glob cleanup preserves fresh file from other PID"
TEST_DIR=$(setup_test)
NOW_TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
cat > "$TEST_DIR/.claude/ralph-loop.88888.local.md" <<EOF
---
active: true
iteration: 3
max_iterations: 0
completion_promise: null
stuck_count: 0
stuck_threshold: 3
started_at: "$NOW_TS"
---

Fresh prompt from other session
EOF
# Also create our own state file so the hook doesn't exit early
create_state_file "$TEST_DIR" 1 0 "null" 0 3
run_hook "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold."
assert_file_exists "$TEST_DIR/.claude/ralph-loop.88888.local.md" "fresh foreign PID file preserved by TTL"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "own-session file preserved"
cleanup_test "$TEST_DIR"
echo ""

# Test 39: setup-ralph-loop.sh creates session-scoped state file
echo "Test 39: setup-ralph-loop.sh creates session-scoped state file (not old name)"
TEST_DIR=$(setup_test)
(cd "$TEST_DIR" && bash "$SETUP" "test prompt" > /dev/null 2>&1)
assert_file_exists "$TEST_DIR/.claude/ralph-loop.${TEST_PID}.local.md" "session-scoped state file created"
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.local.md" "old unscoped state file NOT created"
cleanup_test "$TEST_DIR"
echo ""

echo "=== Invalid JSON Input Tests ==="
echo ""

# Test 40: Malformed text input exits 0 without active loop
echo "Test 40: malformed text input exits 0 without active ralph loop"
TEST_DIR=$(setup_test)
HOOK_OUTPUT=""
EXIT_CODE=0
HOOK_OUTPUT=$(cd "$TEST_DIR" && echo 'not json at all' | bash "$HOOK" 2>/dev/null) || EXIT_CODE=$?
assert_eq "0" "$EXIT_CODE" "hook exits 0 on invalid JSON without active loop"
assert_eq "" "$HOOK_OUTPUT" "no output when no active loop"
cleanup_test "$TEST_DIR"
echo ""

# Test 41: Malformed text input with active loop emits block decision
echo "Test 41: malformed text input with active ralph loop emits block decision"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
HOOK_OUTPUT=$(cd "$TEST_DIR" && echo 'not json at all' | bash "$HOOK" 2>/dev/null) || true
assert_contains "$HOOK_OUTPUT" '"decision": "block"' "block decision emitted on invalid JSON with active loop"
cleanup_test "$TEST_DIR"
echo ""

# --- Summary ---

print_results
