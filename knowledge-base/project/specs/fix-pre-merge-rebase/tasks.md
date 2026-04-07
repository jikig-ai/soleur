# Tasks: fix pre-merge-rebase detached HEAD test

## Phase 1: Setup

- [ ] 1.1 Read `test/pre-merge-rebase.test.ts` and `.claude/hooks/pre-merge-rebase.sh`
- [ ] 1.2 Run the test suite to confirm current state: `bun test test/pre-merge-rebase.test.ts`

## Phase 2: Core Implementation

- [ ] 2.1 Add `git clean -fd` to `beforeEach` after `git reset --hard origin/main` (line ~164)
- [ ] 2.2 Add precondition assertion to "detached HEAD without review evidence" test verifying no `todos/` directory exists
- [ ] 2.3 Add comment documenting the `gh` CLI failure assumption in the test

## Phase 3: Testing

- [ ] 3.1 Run `bun test test/pre-merge-rebase.test.ts` -- all 21 tests pass
- [ ] 3.2 Run test 5 times consecutively to verify no flakiness
- [ ] 3.3 Run `bash scripts/test-all.sh` to verify no regressions in other suites
