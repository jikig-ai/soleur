# Tasks: Ralph Loop Stuck Detection

## Phase 1: Setup

- [ ] 1.1 Read current `plugins/soleur/hooks/stop-hook.sh` and `plugins/soleur/scripts/setup-ralph-loop.sh`
- [ ] 1.2 Read `plugins/soleur/skills/one-shot/SKILL.md` to verify no changes needed

## Phase 2: Core Implementation

- [ ] 2.1 Modify `plugins/soleur/scripts/setup-ralph-loop.sh`
  - [ ] 2.1.1 Add `STUCK_THRESHOLD=3` default variable
  - [ ] 2.1.2 Add `--stuck-threshold` argument parsing (same pattern as `--max-iterations`)
  - [ ] 2.1.3 Add `stuck_count: 0` and `stuck_threshold: <value>` to state file frontmatter
  - [ ] 2.1.4 Update help text with `--stuck-threshold` documentation
  - [ ] 2.1.5 Update setup output message with stuck detection info
- [ ] 2.2 Modify `plugins/soleur/hooks/stop-hook.sh`
  - [ ] 2.2.1 Parse `stuck_count` and `stuck_threshold` from frontmatter (with backward-compatible defaults)
  - [ ] 2.2.2 Measure response length after whitespace stripping
  - [ ] 2.2.3 Increment or reset `stuck_count` based on response length threshold (20 chars)
  - [ ] 2.2.4 Add stuck threshold check: if threshold > 0 and count >= threshold, terminate
  - [ ] 2.2.5 Print warning to stderr on stuck termination
  - [ ] 2.2.6 Remove state file on stuck termination
  - [ ] 2.2.7 Combine `stuck_count` and `iteration` updates into a single `sed` pass (avoid TOCTOU and double disk I/O)

## Phase 3: Testing

- [ ] 3.1 Create `test/stop-hook.test.ts` with test cases
  - [ ] 3.1.1 Test: 3 consecutive minimal responses triggers termination
  - [ ] 3.1.2 Test: 2 minimal then 1 substantive resets counter
  - [ ] 3.1.3 Test: stuck_threshold=0 disables detection
  - [ ] 3.1.4 Test: substantive output keeps stuck_count at 0
  - [ ] 3.1.5 Test: backward compatibility with pre-existing state files (no stuck_count/stuck_threshold fields)
  - [ ] 3.1.6 Test: corrupted stuck_count defaults to 0
  - [ ] 3.1.7 Test: response exactly 20 chars counts as substantive
  - [ ] 3.1.8 Test: stuck detection fires before max_iterations when both conditions could match
- [ ] 3.2 Manual smoke test: create a ralph loop and verify stuck detection message appears after 3 empty iterations
- [ ] 3.3 Verify one-shot pipeline unaffected (substantive output each iteration)
