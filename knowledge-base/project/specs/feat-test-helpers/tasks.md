# Tasks: Extract Shared Test Helpers

## Phase 1: Create Shared Helper

- [ ] 1.1 Create `plugins/soleur/test/test-helpers.sh`
  - [ ] 1.1.1 Shebang `#!/usr/bin/env bash` and `set -euo pipefail`
  - [ ] 1.1.2 Initialize `PASS=0` and `FAIL=0` counters
  - [ ] 1.1.3 `assert_eq` function (from ralph-loop implementation)
  - [ ] 1.1.4 `assert_contains` function using glob pattern (`[[ "$haystack" == *"$needle"* ]]`)
  - [ ] 1.1.5 `assert_file_exists` function (from ralph-loop implementation)
  - [ ] 1.1.6 `assert_file_not_exists` function (from ralph-loop implementation)
  - [ ] 1.1.7 `print_results` function (summary + exit code)
  - [ ] 1.1.8 All function variables declared with `local`

## Phase 2: Migrate ralph-loop Tests

- [ ] 2.1 Rename `ralph-loop-stuck-detection.test.sh` to `ralph-loop.test.sh` via `git mv`
- [ ] 2.2 Update run comment at top to reflect new filename
- [ ] 2.3 Add `source "$SCRIPT_DIR/test-helpers.sh"` after `SCRIPT_DIR` assignment
- [ ] 2.4 Remove inline `PASS=0` and `FAIL=0` declarations
- [ ] 2.5 Remove inline `assert_eq`, `assert_contains`, `assert_file_exists`, `assert_file_not_exists` functions (lines 89-145)
- [ ] 2.6 Replace inline summary block (lines 747-758) with `print_results`
- [ ] 2.7 Keep domain-specific helpers (`setup_test`, `cleanup_test`, `create_state_file`, `run_hook`, `run_hook_stderr`)
- [ ] 2.8 Keep `set -euo pipefail` at top for defense-in-depth (redundant with test-helpers.sh but harmless)

## Phase 3: Migrate resolve-git-root Tests

- [ ] 3.1 Add `source "$SCRIPT_DIR/test-helpers.sh"` after `SCRIPT_DIR` assignment
- [ ] 3.2 Remove inline `PASS=0` and `FAIL=0` declarations
- [ ] 3.3 Remove inline `assert_eq` and `assert_contains` functions
- [ ] 3.4 Replace inline summary block (lines 115-127) with `print_results`

## Phase 4: Verification

- [ ] 4.1 Run `bash plugins/soleur/test/ralph-loop.test.sh` -- all 39 tests pass
- [ ] 4.2 Run `bash plugins/soleur/test/resolve-git-root.test.sh` -- all 7 tests pass
- [ ] 4.3 Verify old filename `ralph-loop-stuck-detection.test.sh` no longer exists
- [ ] 4.4 Run `bun test` to confirm TypeScript tests unaffected
- [ ] 4.5 Lefthook verified: no bash test filename references in `lefthook.yml` (only `bun test` commands) -- no config update needed
