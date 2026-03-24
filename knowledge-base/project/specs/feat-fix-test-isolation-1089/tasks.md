# Tasks: fix test isolation failures when running global bun test from worktrees

## Phase 1: Setup

- [ ] 1.1 Read and understand the three affected files:
  - `test/pre-merge-rebase.test.ts`
  - `apps/web-platform/test/workspace.test.ts`
  - `lefthook.yml`

## Phase 2: Core Implementation

- [ ] 2.1 Fix `test/pre-merge-rebase.test.ts` git isolation
  - [ ] 2.1.1 Add `GIT_CEILING_DIRECTORIES: tmpdir()` to the `GIT_ENV` constant to prevent git from discovering the parent worktree repo
  - [ ] 2.1.2 Verify the `beforeAll` setup still creates and clones temp repos correctly
  - [ ] 2.1.3 Verify all 16 tests still pass in isolation: `bun test test/pre-merge-rebase.test.ts`

- [ ] 2.2 Fix `apps/web-platform/test/workspace.test.ts` git context leak
  - [ ] 2.2.1 Add `process.env.GIT_CEILING_DIRECTORIES = tmpdir()` at the top of the test file (before workspace import)
  - [ ] 2.2.2 Import `tmpdir` from `os` module
  - [ ] 2.2.3 Verify workspace tests still pass: `bun test apps/web-platform/test/workspace.test.ts`

- [ ] 2.3 Fix `lefthook.yml` bun-test hook
  - [ ] 2.3.1 Change `run: bun test` to `run: bash scripts/test-all.sh` in the `bun-test` pre-commit hook
  - [ ] 2.3.2 Verify `scripts/test-all.sh` runs successfully

## Phase 3: Testing

- [ ] 3.1 Run `bun test` from worktree root to verify global test execution no longer fails on isolation issues
- [ ] 3.2 Run `bash scripts/test-all.sh` to verify sequential runner still works
- [ ] 3.3 Verify git log shows no unexpected commits on the feature branch after test runs
- [ ] 3.4 Stage a `.ts` file and verify the lefthook pre-commit hook uses `scripts/test-all.sh`
