# Plan: Verify and Close Bun Test FPE Crash (Issue #1796)

**Date:** 2026-04-10
**Type:** bug-verification
**Status:** draft

## Summary
Issue #1796 reports a `SIGFPE` (Floating Point Error) crash when running `bun test` on Bun v1.3.6. Based on internal research and existing project documentation, this is a known Bun bug (Crash Class 3) affecting versions $\le 1.3.6$ caused by high subprocess spawn counts during GC.

The project has already implemented a multi-layer defense:
1. **Version Pin**: `.bun-version` is pinned to `1.3.11`.
2. **Sequential Runner**: `scripts/test-all.sh` runs tests in isolation.
3. **Test Offloading**: Heavy tests moved to Vitest.

This plan focuses on verifying that the environment is current, confirming the fix is active, and closing the issue as "fixed by version upgrade".

## Acceptance Criteria
- [ ] Verify current environment is running Bun $\ge 1.3.11$.
- [ ] Verify `.bun-version` is pinned to `1.3.11`.
- [ ] Run a sample of the test suite via `scripts/test-all.sh` to confirm no crashes occur.
- [ ] Confirm that the `bunfig.toml` warning regarding $\le 1.3.6$ is present and accurate.
- [ ] Close GitHub issue #1796 with a reference to the version fix and documented learnings.

## Domain Review
**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change.

## Test Scenarios

### Scenario 1: Version Verification
- **Action**: Run `bun -v` and check `.bun-version`.
- **Expected**: Output is `1.3.11` (or higher).

### Scenario 2: Regression Check
- **Action**: Execute `bash scripts/test-all.sh`.
- **Expected**: Tests execute without `panic: Floating point error` or segfaults.

## Implementation Steps

### Phase 1: Environment Audit
- [ ] Verify Bun version in current shell: `bun -v`
- [ ] Verify content of `.bun-version` file
- [ ] Check `bunfig.toml` for the FPE warning string

### Phase 2: Functional Verification
- [ ] Run a subset of tests via `bun test` (if safe/small)
- [ ] Run full test suite via `scripts/test-all.sh` and monitor for crashes

### Phase 3: Issue Resolution
- [ ] Close issue #1796
- [ ] Add comment explaining: "Fixed by upgrading Bun to v1.3.11 (pinned in .bun-version) and implementing sequential test execution via scripts/test-all.sh. See learning: 2026-03-20-bun-fpe-spawn-count-sensitivity.md"

## Alternative Approaches Considered
- **Downgrade to older stable**: Rejected. v1.3.11 is the current project standard and proven stable.
- **Switch entirely to Vitest**: Rejected. `bun test` is preferred for speed; sequential execution in `test-all.sh` is sufficient to prevent the FPE crash.
