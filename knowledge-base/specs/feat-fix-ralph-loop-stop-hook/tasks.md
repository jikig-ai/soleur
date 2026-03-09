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
- [ ] 2.2 Fix setup-ralph-loop.sh path resolution
  - [ ] 2.2.1 Add `PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT_ROOT="."` after `set -euo pipefail`
  - [ ] 2.2.2 Update `mkdir -p .claude` to `mkdir -p "${PROJECT_ROOT}/.claude"`
  - [ ] 2.2.3 Update state file write path to `${PROJECT_ROOT}/.claude/ralph-loop.local.md`
  - [ ] 2.2.4 Update all references to `.claude/ralph-loop.local.md` in echo/help text if they serve as functional paths (leave user-facing display paths unchanged)

## Phase 3: Testing

- [ ] 3.1 Run existing test suite: `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh` -- all 15 tests must pass
- [ ] 3.2 Add test: hook exits 0 from a non-root CWD when state file does not exist
- [ ] 3.3 Add test: hook finds state file at project root when CWD is a subdirectory
- [ ] 3.4 Verify no awk or jq errors in stderr output when state file is absent
