# Tasks: fix-ralph-loop-stop-hook

## Phase 1: Setup

- [x] 1.1 Read and understand the current stop-hook.sh, setup-ralph-loop.sh, and welcome-hook.sh
- [x] 1.2 Run existing test suite to confirm baseline: `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh`

## Phase 2: Core Implementation

- [x] 2.1 Fix stop-hook.sh path resolution and ordering
  - [x] 2.1.1 Add `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` after `set -euo pipefail`
  - [x] 2.1.2 Update `RALPH_STATE_FILE` to use `${PROJECT_ROOT}/.claude/ralph-loop.local.md`
  - [x] 2.1.3 Move the `if [[ ! -f "$RALPH_STATE_FILE" ]]` check before `HOOK_INPUT=$(cat)`
  - [x] 2.1.4 Update the `TEMP_FILE` path to use `${RALPH_STATE_FILE}.tmp.$$` (already does, but verify after PROJECT_ROOT change)
- [x] 2.2 Replace transcript file parsing with `last_assistant_message` from hook input
  - [x] 2.2.1 Remove transcript path extraction
  - [x] 2.2.2 Remove transcript file existence check
  - [x] 2.2.3 Remove grep for assistant messages in transcript
  - [x] 2.2.4 Remove jq extraction of text content blocks
  - [x] 2.2.5 Replace with single line: `LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')`
- [x] 2.3 Fix setup-ralph-loop.sh path resolution
  - [x] 2.3.1 Add `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` after `set -euo pipefail`
  - [x] 2.3.2 Update `mkdir -p .claude` to `mkdir -p "${PROJECT_ROOT}/.claude"`
  - [x] 2.3.3 Update state file write path to `${PROJECT_ROOT}/.claude/ralph-loop.local.md`
  - [x] 2.3.4 User-facing display paths left unchanged (correct behavior)

## Phase 3: Testing

- [x] 3.1 Update test helper `run_hook` to pass `last_assistant_message` in hook input JSON
- [x] 3.2 Update test helper `run_hook_stderr` similarly
- [x] 3.3 Update all existing test invocations to pass message text directly
- [x] 3.4 Run updated test suite -- all 17 tests pass (37 assertions)
- [x] 3.5 Add test 16: hook exits 0 from a non-root CWD when state file does not exist
- [x] 3.6 Add test 17: hook finds state file at project root when CWD is a subdirectory
- [x] 3.7 Verified no awk or jq errors in stderr output when state file is absent
