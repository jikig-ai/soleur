# Tasks: fix-stop-hook-unguarded-jq (#713)

## Phase 1: Fix

- [ ] 1.1 Add `2>/dev/null || true` guard to jq call on line 118 of `plugins/soleur/hooks/stop-hook.sh`

## Phase 2: Testing

- [ ] 2.1 Add test 40: malformed text input (`"not json"`) with no ralph loop -- hook exits 0, no output (bypass `run_hook` helper, pipe raw input directly)
- [ ] 2.2 Add test 41: malformed text input with active ralph loop -- hook emits block decision JSON, `LAST_OUTPUT` treated as empty (create state file, pipe invalid JSON, verify block decision in stdout)
- [ ] 2.3 Run full test suite (`bash plugins/soleur/test/ralph-loop.test.sh`) -- verify all 41 tests pass

## Phase 3: Verification

- [ ] 3.1 Run compound (`skill: soleur:compound`) before commit
