#!/usr/bin/env bash

# Tests for Ralph Loop stuck detection in stop-hook.sh
# Run: bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh

set -euo pipefail

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$SCRIPT_DIR/../hooks/stop-hook.sh"
SETUP="$SCRIPT_DIR/../scripts/setup-ralph-loop.sh"

# --- Test Helpers ---

setup_test() {
  local test_dir
  test_dir=$(mktemp -d)
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

  cat > "$dir/.claude/ralph-loop.local.md" <<EOF
---
active: true
iteration: $iteration
max_iterations: $max
completion_promise: $promise
stuck_count: $stuck_count
stuck_threshold: $stuck_threshold
started_at: "2026-03-05T00:00:00Z"
---

Test prompt
EOF
}

create_transcript() {
  local dir="$1"
  local text_content="$2"

  local transcript_file="$dir/transcript.jsonl"
  # Create a valid JSONL assistant message
  echo "{\"role\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"$text_content\"}]}}" > "$transcript_file"
  echo "$transcript_file"
}

create_empty_transcript() {
  local dir="$1"

  local transcript_file="$dir/transcript.jsonl"
  # Tool-use only response (no text blocks)
  echo "{\"role\":\"assistant\",\"message\":{\"content\":[{\"type\":\"tool_use\",\"id\":\"test\",\"name\":\"Read\",\"input\":{\"file_path\":\"/tmp/test\"}}]}}" > "$transcript_file"
  echo "$transcript_file"
}

run_hook() {
  local dir="$1"
  local transcript_path="$2"

  local hook_input
  hook_input=$(jq -n --arg tp "$transcript_path" '{"transcript_path": $tp}')

  cd "$dir"
  echo "$hook_input" | bash "$HOOK" 2>/dev/null || true
}

run_hook_stderr() {
  local dir="$1"
  local transcript_path="$2"

  local hook_input
  hook_input=$(jq -n --arg tp "$transcript_path" '{"transcript_path": $tp}')

  cd "$dir"
  echo "$hook_input" | bash "$HOOK" 2>&1 1>/dev/null || true
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local msg="$3"

  if [[ "$expected" == "$actual" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local path="$1"
  local msg="$2"

  if [[ -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_not_exists() {
  local path="$1"
  local msg="$2"

  if [[ ! -f "$path" ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg (file still exists: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    echo "  PASS: $msg"
    PASS=$((PASS + 1))
  else
    echo "  FAIL: $msg"
    echo "    expected to contain: '$needle'"
    echo "    actual: '$haystack'"
    FAIL=$((FAIL + 1))
  fi
}

# --- Tests ---

echo "=== Ralph Loop Stuck Detection Tests ==="
echo ""

# Test 1: 3 consecutive empty responses triggers termination
echo "Test 1: 3 consecutive empty responses triggers termination"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 2 3
TRANSCRIPT=$(create_transcript "$TEST_DIR" "")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file removed after stuck detection"
cleanup_test "$TEST_DIR"
echo ""

# Test 2: Warning message printed to stderr
echo "Test 2: Warning message printed to stderr on stuck termination"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 2 3
TRANSCRIPT=$(create_transcript "$TEST_DIR" "")
STDERR_OUTPUT=$(run_hook_stderr "$TEST_DIR" "$TRANSCRIPT")
assert_contains "$STDERR_OUTPUT" "terminated after" "stderr contains termination warning"
assert_contains "$STDERR_OUTPUT" "consecutive empty responses" "stderr mentions empty responses"
cleanup_test "$TEST_DIR"
echo ""

# Test 3: Substantive response resets stuck counter
echo "Test 3: Substantive response resets stuck_count to 0"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 2 0 "null" 2 3
TRANSCRIPT=$(create_transcript "$TEST_DIR" "This is a substantive response with plenty of content to exceed the threshold.")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists (loop continues)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset to 0"
cleanup_test "$TEST_DIR"
echo ""

# Test 4: stuck_threshold=0 disables detection
echo "Test 4: stuck_threshold=0 disables stuck detection"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "null" 10 0
TRANSCRIPT=$(create_transcript "$TEST_DIR" "")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists (detection disabled)"
cleanup_test "$TEST_DIR"
echo ""

# Test 5: Normal loop with substantive output keeps stuck_count at 0
echo "Test 5: Normal loop with substantive output - stuck_count stays 0"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
TRANSCRIPT=$(create_transcript "$TEST_DIR" "Here is a detailed response explaining the changes I made to the codebase.")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count remains 0"
cleanup_test "$TEST_DIR"
echo ""

# Test 6: Exactly 20 characters counts as substantive
echo "Test 6: Exactly 20 characters (after stripping) is substantive"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 2 3
# "12345678901234567890" is exactly 20 chars
TRANSCRIPT=$(create_transcript "$TEST_DIR" "12345678901234567890")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_count: *//')
assert_eq "0" "$STUCK_COUNT" "stuck_count reset (20 chars = substantive)"
cleanup_test "$TEST_DIR"
echo ""

# Test 7: 19 characters counts as minimal
echo "Test 7: 19 characters (after stripping) is minimal"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
# "1234567890123456789" is 19 chars
TRANSCRIPT=$(create_transcript "$TEST_DIR" "1234567890123456789")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented to 1"
cleanup_test "$TEST_DIR"
echo ""

# Test 8: Pre-existing state file without stuck fields uses defaults
echo "Test 8: Pre-existing state file without stuck_count/stuck_threshold uses defaults"
TEST_DIR=$(setup_test)
# State file without stuck_count or stuck_threshold
cat > "$TEST_DIR/.claude/ralph-loop.local.md" <<'EOF'
---
active: true
iteration: 1
max_iterations: 0
completion_promise: null
started_at: "2026-03-05T00:00:00Z"
---

Test prompt
EOF
TRANSCRIPT=$(create_transcript "$TEST_DIR" "Substantive response with enough content here to pass threshold.")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists (no crash on missing fields)"
cleanup_test "$TEST_DIR"
echo ""

# Test 9: Tool-use only response (empty LAST_OUTPUT) counts as minimal
echo "Test 9: Tool-use only response counts as minimal"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 1 0 "null" 0 3
TRANSCRIPT=$(create_empty_transcript "$TEST_DIR")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file still exists (only 1 empty, threshold is 3)"
STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_count: *//')
assert_eq "1" "$STUCK_COUNT" "stuck_count incremented for tool-use only response"
cleanup_test "$TEST_DIR"
echo ""

# Test 10: Completion promise still takes priority over stuck detection
echo "Test 10: Completion promise check fires before stuck detection"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 0 "\"DONE\"" 2 3
TRANSCRIPT=$(create_transcript "$TEST_DIR" "<promise>DONE</promise>")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file removed (promise matched)"
cleanup_test "$TEST_DIR"
echo ""

# Test 11: setup-ralph-loop.sh adds stuck_threshold to state file
echo "Test 11: setup-ralph-loop.sh includes stuck_count and stuck_threshold in state"
TEST_DIR=$(setup_test)
cd "$TEST_DIR"
bash "$SETUP" "test prompt" --stuck-threshold 5 > /dev/null 2>&1
assert_file_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file created"
if [[ -f "$TEST_DIR/.claude/ralph-loop.local.md" ]]; then
  STUCK_COUNT=$(grep '^stuck_count:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_count: *//')
  STUCK_THRESHOLD=$(grep '^stuck_threshold:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_threshold: *//')
  assert_eq "0" "$STUCK_COUNT" "stuck_count initialized to 0"
  assert_eq "5" "$STUCK_THRESHOLD" "stuck_threshold set to 5"
fi
cleanup_test "$TEST_DIR"
echo ""

# Test 12: setup-ralph-loop.sh defaults stuck_threshold to 3
echo "Test 12: setup-ralph-loop.sh defaults stuck_threshold to 3"
TEST_DIR=$(setup_test)
cd "$TEST_DIR"
bash "$SETUP" "test prompt" > /dev/null 2>&1
if [[ -f "$TEST_DIR/.claude/ralph-loop.local.md" ]]; then
  STUCK_THRESHOLD=$(grep '^stuck_threshold:' "$TEST_DIR/.claude/ralph-loop.local.md" | sed 's/stuck_threshold: *//')
  assert_eq "3" "$STUCK_THRESHOLD" "stuck_threshold defaults to 3"
fi
cleanup_test "$TEST_DIR"
echo ""

# Test 13: Stuck detection wins over continued looping at iteration 5
echo "Test 13: Stuck detection fires at iteration 5 (before max_iterations=10)"
TEST_DIR=$(setup_test)
create_state_file "$TEST_DIR" 5 10 "null" 2 3
TRANSCRIPT=$(create_transcript "$TEST_DIR" "")
run_hook "$TEST_DIR" "$TRANSCRIPT"
assert_file_not_exists "$TEST_DIR/.claude/ralph-loop.local.md" "state file removed (stuck at iteration 5)"
cleanup_test "$TEST_DIR"
echo ""

# --- Summary ---

echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "SOME TESTS FAILED"
  exit 1
else
  echo "ALL TESTS PASSED"
  exit 0
fi
