# Tasks: fix-stop-hook-unguarded-jq (#713)

## Phase 1: Fix

- [ ] 1.1 Guard jq call on line 118 of `plugins/soleur/hooks/stop-hook.sh` with `2>/dev/null || true`

## Phase 2: Testing

- [ ] 2.1 Add test: invalid JSON input (e.g., `"not json"`) to stop hook exits 0 and produces no blocking output when no ralph loop is active
- [ ] 2.2 Add test: empty stdin to stop hook exits 0 when no ralph loop is active
- [ ] 2.3 Add test: invalid JSON input with active ralph loop -- `LAST_OUTPUT` treated as empty, loop continues (block decision emitted)
- [ ] 2.4 Run full test suite (`bash plugins/soleur/test/ralph-loop.test.sh`) -- verify all 39 existing tests plus new tests pass

## Phase 3: Verification

- [ ] 3.1 Run compound (`skill: soleur:compound`) before commit
