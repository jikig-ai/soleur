# Tasks: fix pre-merge hook bare repo false positive

## Phase 1: Test (TDD RED)

- [x] 1.1 Add test case for bare repo CWD not false-positive on uncommitted changes
  - Create a bare repo test setup with non-main HEAD
  - Verify hook does NOT deny with "Uncommitted changes" when diff returns exit 128
- [x] 1.2 Add test case for exit code 1 still triggers deny (regression guard)
  - Existing "uncommitted changes blocks merge" test covers this
- [x] 1.3 Run test suite, confirm new test(s) fail (RED phase)

## Phase 2: Implementation (TDD GREEN)

- [x] 2.1 Wrap diff check in work-tree guard in `pre-merge-rebase.sh`
  - Used `rev-parse --is-inside-work-tree` guard instead of exit-code capture
  - Exit-code approach insufficient: `diff --cached --quiet` returns 1 (not 128) in bare repos
  - Add inline comment referencing #1386
- [x] 2.2 Run test suite, confirm all tests pass (GREEN phase)

## Phase 3: Verification

- [x] 3.1 Run full test suite to confirm no regressions
- [x] 3.2 Manually verify hook behavior from worktree CWD
