# Tasks: fix pre-merge hook bare repo false positive

## Phase 1: Test (TDD RED)

- [ ] 1.1 Add test case for bare repo CWD not false-positive on uncommitted changes
  - Create a bare repo test setup with non-main HEAD
  - Verify hook does NOT deny with "Uncommitted changes" when diff returns exit 128
- [ ] 1.2 Add test case for exit code 1 still triggers deny (regression guard)
  - Verify existing "uncommitted changes blocks merge" test still passes after refactor
- [ ] 1.3 Run test suite, confirm new test(s) fail (RED phase)

## Phase 2: Implementation (TDD GREEN)

- [ ] 2.1 Replace boolean diff check with exit-code-aware check in `pre-merge-rebase.sh`
  - Replace lines 104-116: `if ! git diff ...` with explicit `$?` capture
  - Only block on exit code 1 (dirty), fail open on 128+ (bare/error)
  - Add inline comment referencing #1386
- [ ] 2.2 Run test suite, confirm all tests pass (GREEN phase)

## Phase 3: Verification

- [ ] 3.1 Run full test suite to confirm no regressions
- [ ] 3.2 Manually verify hook behavior from worktree CWD
