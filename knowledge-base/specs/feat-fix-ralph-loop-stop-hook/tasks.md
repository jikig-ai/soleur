# Tasks: fix-ralph-loop-stop-hook

## Phase 1: Setup

- [ ] 1.1 Read and understand the current stop-hook.sh, setup-ralph-loop.sh, and welcome-hook.sh
- [ ] 1.2 Run existing test suite to confirm baseline: `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh`

## Phase 2: Core Implementation

- [ ] 2.1 Fix stop-hook.sh path resolution and ordering
  - [ ] 2.1.1 Add `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` after `set -euo pipefail`
  - [ ] 2.1.2 Update `RALPH_STATE_FILE` to use `${PROJECT_ROOT}/.claude/ralph-loop.local.md`
  - [ ] 2.1.3 Move the `if [[ ! -f "$RALPH_STATE_FILE" ]]` check before `HOOK_INPUT=$(cat)`
  - [ ] 2.1.4 Update the `TEMP_FILE` path to use `${RALPH_STATE_FILE}.tmp.$$` (already does, but verify after PROJECT_ROOT change)
- [ ] 2.2 Replace transcript file parsing with `last_assistant_message` from hook input
  - [ ] 2.2.1 Remove transcript path extraction (line 66: `TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path')`)
  - [ ] 2.2.2 Remove transcript file existence check (lines 68-72)
  - [ ] 2.2.3 Remove grep for assistant messages in transcript (lines 75-81)
  - [ ] 2.2.4 Remove jq extraction of text content blocks (lines 84-89)
  - [ ] 2.2.5 Replace with single line: `LAST_OUTPUT=$(echo "$HOOK_INPUT" | jq -r '.last_assistant_message // ""')`
- [ ] 2.3 Fix setup-ralph-loop.sh path resolution
  - [ ] 2.3.1 Add `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` after `set -euo pipefail`
  - [ ] 2.3.2 Update `mkdir -p .claude` to `mkdir -p "${PROJECT_ROOT}/.claude"`
  - [ ] 2.3.3 Update state file write path to `${PROJECT_ROOT}/.claude/ralph-loop.local.md`
  - [ ] 2.3.4 Update all references to `.claude/ralph-loop.local.md` in echo/help text if they serve as functional paths (leave user-facing display paths unchanged)

## Phase 3: Testing

- [ ] 3.1 Update test helper `run_hook` to include `last_assistant_message` in hook input JSON (third parameter)
- [ ] 3.2 Update test helper `run_hook_stderr` similarly
- [ ] 3.3 Update all existing test invocations to pass message text as third argument to `run_hook`/`run_hook_stderr`
- [ ] 3.4 Run updated test suite: `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh` -- all 15 tests must pass
- [ ] 3.5 Add test 16: hook exits 0 from a non-root CWD when state file does not exist
- [ ] 3.6 Add test 17: hook finds state file at project root when CWD is a subdirectory
- [ ] 3.7 Verify no awk or jq errors in stderr output when state file is absent
