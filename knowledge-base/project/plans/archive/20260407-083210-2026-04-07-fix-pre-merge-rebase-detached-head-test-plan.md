---
title: "fix: pre-merge-rebase test — detached HEAD without review evidence"
type: fix
date: 2026-04-07
deepened: 2026-04-07
---

# fix: pre-merge-rebase test — detached HEAD without review evidence

## Enhancement Summary

**Deepened on:** 2026-04-07
**Sections enhanced:** 5
**Research sources:** 6 institutional learnings, test-design-reviewer analysis, code-simplicity review

### Key Improvements

1. Identified `git clean -fd` in `beforeEach` as the primary fix (single line change)
2. Rejected `afterEach` safety net as YAGNI -- `beforeEach` cleanup is sufficient
3. Discovered Bun spawn-count sensitivity as a potential contributor to intermittent failures
4. Added precondition assertion pattern from bare-repo learning (false-green prevention)

### New Considerations Discovered

- The `gh` CLI isolation concern (Failure Mode 2) is lower risk than initially assessed -- `GIT_CONFIG_GLOBAL=/dev/null` plus temp repo CWD means `gh` cannot resolve the real repo's remote, so the API call fails before searching issues
- The `spawnChecked` function already uses `GIT_ENV` for all calls, ruling out environment variable leakage as a cause
- Bun 1.3.11 (current version) is stable for this test's spawn count (~80 spawns), but the sequential runner provides defense-in-depth

## Overview

The test "detached HEAD without review evidence is denied" in `test/pre-merge-rebase.test.ts` was reported as failing during ship Phase 4 for PR #1695 (fixing #1683). The failure is reported as pre-existing on main. GitHub issue: #1694.

## Problem Statement

Investigation reveals the test currently passes consistently (locally and in CI). The failure was likely intermittent, caused by one or more test isolation gaps in the test suite. Three failure modes have been identified through code analysis:

### Failure Mode 1: `todos/` directory leaking between tests (most likely)

The `beforeEach` hook resets to `origin/main` via `git checkout main && git reset --hard origin/main`, which removes tracked files from feature branches. However, if a prior test crashes mid-execution or leaves the repo in a merge state, `git checkout main` may fail silently (the `spawnChecked` would throw, but `beforeEach` error handling in bun:test is not well-defined for cleanup). If `todos/review-finding.md` persists from a prior test's `addReviewEvidence()` call, the hook's `grep -rl "code-review" "$WORK_DIR/todos/"` check (line 61) finds evidence and the test passes instead of producing a deny.

The `beforeEach` does NOT:

- Run `git clean -fd` to remove untracked files
- Explicitly delete `todos/` directory
- Verify working tree cleanliness after reset

### Research Insights (Failure Mode 1)

**Institutional learnings applied:**

- **False-green anti-pattern** (`pre-merge-hook-bare-repo-diff-false-positive-20260402.md`): "When testing a specific code path in a multi-guard hook, verify the test actually reaches that code path. A test that passes because an earlier guard fires is a false green." The detached HEAD test could experience the inverse: passing because review evidence leaks forward, so the deny never fires.
- **GIT_* env var leak pattern**(`2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`): Tests that spawn git in temp directories must strip GIT_* env vars. This test already does this correctly via `GIT_ENV` (confirmed: `spawnChecked` at line 39 uses `{ ...opts, env: GIT_ENV }`). Ruled out as a cause.
- **GIT_CEILING_DIRECTORIES isolation** (`2026-03-24-git-ceiling-directories-test-isolation.md`): This test was previously fixed to include `GIT_CEILING_DIRECTORIES: tmpdir()`. The fix is still in place and prevents parent repo discovery.

**Best practice:** `git reset --hard` removes tracked files but NOT untracked files or directories. `git clean -fd` is the standard companion command for full working tree reset. Every test suite that uses shared mutable git state across tests should use both in its `beforeEach`.

### Failure Mode 2: `gh` CLI finding spurious review issues (environment-dependent)

The hook's Check 3 (lines 72-84) queries `gh issue list --label code-review --search "PR #123"` where 123 is the hardcoded PR number in all test commands. If the real repository has any issue with a `code-review` label that mentions "PR #123" in the title/body, this check returns a match, causing the review gate to pass when the test expects it to deny. This is a time bomb -- it works today but could break as the repo accumulates issues.

### Research Insights (Failure Mode 2)

**Risk reassessment:** Lower than initially assessed. The hook resolves the repo remote via `git -C "$WORK_DIR" remote get-url origin` where `$WORK_DIR` is the temp repo. The temp repo's `origin` points to the bare temp remote (`remoteDir`), not the real GitHub repo. So `gh pr list --repo` receives a local filesystem path, which `gh` cannot resolve as a GitHub repo. The `gh` command fails with a non-GitHub-URL error, returning empty. This means Check 3 is effectively inert in tests.

**Remaining risk:** If `gh` is authenticated and falls back to the current directory's git remote when `--repo` fails, it could still match against the real repo. This is unlikely with current `gh` CLI behavior but worth documenting.

### Failure Mode 3: Stale `origin/main` with review evidence (unlikely but possible)

If a prior test's merge+push sequence somehow pushes a review-evidence commit to `origin/main` (not observed in current test code but possible via merge commit inclusion), the `git log origin/main..HEAD` range computation changes.

### Research Insights (Failure Mode 3)

**Ruled out by code analysis:** The `addReviewEvidence()` function commits on feature branches. Tests push feature branches to `origin/<branch-name>`, not `origin/main`. The only tests that push to `origin/main` are "branch behind main" (line 275: pushes "main advance") and "merge conflict" (line 340: pushes "main conflict"). Neither includes the review evidence commit message "refactor: add code review findings".

## Proposed Solution

### Phase 1: Harden `beforeEach` test isolation (primary fix)

Add `git clean -fd` to `beforeEach` after `git reset --hard origin/main`. This is the minimal change that addresses the root cause:

```typescript
beforeEach(() => {
  spawnChecked(["git", "checkout", "main"], { cwd: repoDir });
  spawnChecked(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
  // Remove untracked files/directories (e.g., todos/ from addReviewEvidence)
  // git reset --hard only resets tracked files; clean -fd handles the rest
  spawnChecked(["git", "clean", "-fd"], { cwd: repoDir });
  const branches = Bun.spawnSync(["git", "branch", "--list", "test-*"], {
    cwd: repoDir,
    env: GIT_ENV,
  });
  // ... rest of branch cleanup unchanged ...
});
```

**File:** `test/pre-merge-rebase.test.ts` line 164, insert after `git reset --hard`

### Phase 2: Add precondition assertion to the failing test

Add a precondition check that catches isolation failures early with a clear error message, rather than producing a confusing JSON parse error or silent pass:

```typescript
test("detached HEAD without review evidence is denied", async () => {
  // Precondition: verify no review evidence leaked from prior tests.
  // Without this, a leaked todos/ directory causes a silent false-green
  // (hook finds evidence, skips deny, test gets empty stdout, JSON.parse throws).
  const todosCheck = Bun.spawnSync(["test", "-d", "todos"], {
    cwd: repoDir, env: GIT_ENV,
  });
  expect(todosCheck.exitCode).not.toBe(0); // todos/ must NOT exist

  // ... existing test code ...
});
```

**File:** `test/pre-merge-rebase.test.ts` line 386, insert before existing test body

### ~~Phase 3: Add `afterEach` safety net~~ (REMOVED -- YAGNI)

**Simplicity review finding:** An `afterEach` safety net duplicates the cleanup already done in `beforeEach`. If `beforeEach` runs `git clean -fd`, untracked files are cleaned before every test. Adding `afterEach` provides no additional protection -- it only adds ~10 lines of code, ~5 extra git spawns per test (slowing the suite by ~20%), and a maintenance surface. The precondition assertion in Phase 2 provides the diagnostic value that `afterEach` would offer, without the runtime cost.

**Decision:** Removed. If test isolation issues recur despite Phase 1, revisit.

## Acceptance Criteria

- [x] Test "detached HEAD without review evidence is denied" passes reliably (10 consecutive runs)
- [x] `beforeEach` explicitly cleans untracked files via `git clean -fd`
- [x] No cross-test state leakage possible for `todos/` directory
- [x] All 21 existing tests continue to pass
- [x] No new test flakiness introduced
- [x] Precondition assertion in the failing test catches isolation failures early

## Test Scenarios

- Given a clean repo after `beforeEach`, when the "detached HEAD without review evidence" test runs, then it produces a deny with `permissionDecision: "deny"`
- Given a prior test that called `addReviewEvidence()`, when `beforeEach` runs, then no `todos/` directory exists in the working tree (verified by `git clean -fd`)
- Given all 21 tests run sequentially, when the full suite completes, then all tests pass with 0 failures
- Given the test suite runs 10 times consecutively, when checking results, then all runs show 21 pass / 0 fail
- Given the precondition assertion, when `todos/` leaks from a prior test, then the test fails with a clear "todos/ must NOT exist" message instead of a JSON parse error

### Test Quality Assessment (Dave Farley's 8 Properties)

| Property | Current | After Fix | Notes |
|----------|---------|-----------|-------|
| Repeatable | 7/10 | 9/10 | `git clean -fd` eliminates state leakage |
| Atomic | 8/10 | 9/10 | Precondition assertion isolates failure cause |
| Granular | 6/10 | 8/10 | Precondition gives clear failure message vs JSON parse error |
| Understandable | 8/10 | 8/10 | Comment explains why cleanup is needed |
| Maintainable | 8/10 | 8/10 | No change -- fix is additive |
| Necessary | 9/10 | 9/10 | Tests a real security gate |
| Fast | 7/10 | 7/10 | One extra git spawn (~50ms) per test |
| First (TDD) | N/A | N/A | Bug fix, not new feature |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal test isolation fix.

## Context

- Issue: #1694
- Files: `test/pre-merge-rebase.test.ts`, `.claude/hooks/pre-merge-rebase.sh`
- Related learnings:
  - `2026-03-24-git-ceiling-directories-test-isolation.md` -- GIT_CEILING_DIRECTORIES fix for this same test file
  - `2026-03-28-pretooluse-hook-guard-ordering-matters.md` -- Guard ordering (review gate before detached HEAD exit)
  - `workflow-issues/pre-merge-hook-bare-repo-diff-false-positive-20260402.md` -- False-green anti-pattern in hook tests
  - `workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md` -- GIT_* env var leak pattern (ruled out)
  - `2026-03-20-bun-fpe-spawn-count-sensitivity.md` -- Bun FPE crash from high spawn counts (mitigated by sequential runner)
  - `2026-03-05-verify-pretooluse-hooks-ci-deterministic-guard-testing.md` -- Deterministic hook testing patterns
- The hook itself is correct -- guard ordering (review gate before detached HEAD exit) is intentional per the 2026-03-28 learning
- The fix targets test isolation only, not hook behavior

## Implementation Notes

**Total change size:** ~5 lines added, 0 lines removed

1. Insert `spawnChecked(["git", "clean", "-fd"], { cwd: repoDir });` after line 164
2. Insert precondition assertion (3 lines) at the start of the failing test body (line 386)
3. Add comment explaining the `git clean -fd` addition

**Risk:** Very low. `git clean -fd` in a temp directory has no side effects. The precondition assertion fails early with a clear message if isolation breaks.

**Spawn count impact:** +1 `git clean` per `beforeEach` call. The suite has ~12 tests in the "with git repo" describe block, adding ~12 extra spawns. Total spawn count stays well under the Bun FPE threshold (~130 spawns).

## References

- Related PR: #1695 (fix-code-review-1683, where failure was discovered)
- Hook design: `2026-03-28-pretooluse-hook-guard-ordering-matters.md`
- Test isolation: `2026-03-24-git-ceiling-directories-test-isolation.md`
- False-green prevention: `workflow-issues/pre-merge-hook-bare-repo-diff-false-positive-20260402.md`
