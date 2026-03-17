# Tasks: fix ralph loop session-scoped state file

## Phase 1: Core Implementation

- [ ] 1.1 Update `plugins/soleur/hooks/stop-hook.sh` state file path to include `$PPID`
  - [ ] 1.1.1 Change `RALPH_STATE_FILE` from `ralph-loop.local.md` to `ralph-loop.${PPID}.local.md`
  - [ ] 1.1.2 Add glob-based TTL cleanup loop: iterate `ralph-loop.*.local.md`, remove stale files (older than TTL_HOURS)
  - [ ] 1.1.3 Move existing single-file TTL check into the glob loop
- [ ] 1.2 Update `plugins/soleur/scripts/setup-ralph-loop.sh` state file path to include `$PPID`
  - [ ] 1.2.1 Change state file output path to `ralph-loop.${PPID}.local.md`
  - [ ] 1.2.2 Update cancel instructions to show glob: `rm .claude/ralph-loop.*.local.md`
  - [ ] 1.2.3 Update monitoring instructions to show glob: `head -10 .claude/ralph-loop.*.local.md`
- [ ] 1.3 Update `plugins/soleur/skills/one-shot/SKILL.md` cancel instruction to use glob pattern

## Phase 2: Testing

- [ ] 2.1 Update `plugins/soleur/test/ralph-loop-stuck-detection.test.sh` for new file naming
  - [ ] 2.1.1 Update `create_state_file` to write `ralph-loop.$$.local.md`
  - [ ] 2.1.2 Update all `assert_file_exists` / `assert_file_not_exists` calls for new path
  - [ ] 2.1.3 Update all `grep` commands that read the state file for new path
- [ ] 2.2 Add new test: state file from different PID does not block exit
  - [ ] 2.2.1 Create state file with foreign PID (e.g., `ralph-loop.99999.local.md`)
  - [ ] 2.2.2 Verify hook exits 0 and does not output block JSON
- [ ] 2.3 Add new test: TTL glob cleanup removes stale files from other PIDs
  - [ ] 2.3.1 Create stale state file with foreign PID (started_at in the past)
  - [ ] 2.3.2 Run hook and verify the stale file is removed
- [ ] 2.4 Run full test suite and verify all tests pass

## Phase 3: Verification

- [ ] 3.1 Run `bash plugins/soleur/test/ralph-loop-stuck-detection.test.sh` and confirm ALL TESTS PASSED
- [ ] 3.2 Verify `.gitignore` pattern `*.local.md` covers new filenames (no changes needed)
