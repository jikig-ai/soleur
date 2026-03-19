# Tasks: fix ralph loop session-scoped state file

## Phase 1: Core Implementation

- [x] 1.1 Update `plugins/soleur/hooks/stop-hook.sh`
  - [x] 1.1.1 Change `RALPH_STATE_FILE` line 21 to `"${PROJECT_ROOT}/.claude/ralph-loop.${PPID}.local.md"`
  - [x] 1.1.2 Replace single-file TTL check (lines 29-44) with glob-based TTL cleanup loop over `ralph-loop.*.local.md`
  - [x] 1.1.3 Add `[[ -f "$state_file" ]] || continue` guard for empty glob under `set -euo pipefail`
  - [x] 1.1.4 Add `|| true` guards on grep/date inside the TTL loop to prevent pipefail abort
  - [x] 1.1.5 Include `$(basename "$state_file")` in stale-file stderr message for debugging
- [x] 1.2 Update `plugins/soleur/scripts/setup-ralph-loop.sh`
  - [x] 1.2.1 Change state file output path (line 143) to `ralph-loop.${PPID}.local.md`
  - [x] 1.2.2 Update cancel instructions in output to show specific PID file
  - [x] 1.2.3 Update monitoring instructions in output to show specific PID file
  - [x] 1.2.4 Update `--help` text STOPPING section to show glob pattern `ralph-loop.*.local.md`
  - [x] 1.2.5 Update `--help` text MONITORING section to show glob pattern `ralph-loop.*.local.md`
- [x] 1.3 Update `plugins/soleur/skills/one-shot/SKILL.md` cancel instruction to use glob pattern `rm .claude/ralph-loop.*.local.md`

## Phase 2: Testing

- [x] 2.1 Update `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` test infrastructure
  - [x] 2.1.1 Add `get_hook_ppid` helper: `(cd "$dir" && bash -c 'echo $PPID')` to determine what PPID the hook sees
  - [x] 2.1.2 Update `create_state_file` to use PID-scoped filename via `get_hook_ppid`
  - [x] 2.1.3 Update all `assert_file_exists` / `assert_file_not_exists` paths
  - [x] 2.1.4 Update all `grep` commands that read the state file for new path pattern
- [x] 2.2 Add new test: foreign PID state file does not block exit
  - [x] 2.2.1 Create state file as `ralph-loop.99999.local.md` (guaranteed foreign PID)
  - [x] 2.2.2 Verify hook exits 0 and outputs nothing (no block JSON)
  - [x] 2.2.3 Verify foreign PID file is preserved (fresh, not removed by TTL)
- [x] 2.3 Add new test: TTL glob cleanup removes stale file from other PID
  - [x] 2.3.1 Create stale state file as `ralph-loop.99999.local.md` with old `started_at`
  - [x] 2.3.2 Run hook and verify stale foreign file is removed
- [x] 2.4 Add new test: TTL glob cleanup preserves fresh file from other PID
  - [x] 2.4.1 Create fresh state file as `ralph-loop.99999.local.md` with current `started_at`
  - [x] 2.4.2 Run hook and verify fresh foreign file is NOT removed

## Phase 3: Verification

- [x] 3.1 Run `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh` and confirm ALL TESTS PASSED
- [x] 3.2 Verify `.gitignore` pattern covers new filenames (spot check, no changes needed)
- [x] 3.3 Run `bash -n` syntax check on modified scripts
