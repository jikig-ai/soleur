---
title: "fix: pre-merge-rebase test — detached HEAD without review evidence"
type: fix
date: 2026-04-07
---

# fix: pre-merge-rebase test — detached HEAD without review evidence

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

### Failure Mode 2: `gh` CLI finding spurious review issues (environment-dependent)

The hook's Check 3 (lines 72-84) queries `gh issue list --label code-review --search "PR #123"` where 123 is the hardcoded PR number in all test commands. If the real repository has any issue with a `code-review` label that mentions "PR #123" in the title/body, this check returns a match, causing the review gate to pass when the test expects it to deny. This is a time bomb -- it works today but could break as the repo accumulates issues.

### Failure Mode 3: Stale `origin/main` with review evidence (unlikely but possible)

If a prior test's merge+push sequence somehow pushes a review-evidence commit to `origin/main` (not observed in current test code but possible via merge commit inclusion), the `git log origin/main..HEAD` range computation changes.

## Proposed Solution

### Phase 1: Harden `beforeEach` test isolation

Add explicit cleanup to prevent cross-test state leakage:

```typescript
// In beforeEach, after git reset:
// 1. Clean untracked files/directories to prevent todos/ leakage
Bun.spawnSync(["git", "clean", "-fd"], { cwd: repoDir, env: GIT_ENV });
```

**File:** `test/pre-merge-rebase.test.ts` (beforeEach block, ~line 162-178)

### Phase 2: Isolate the detached HEAD test from `gh` CLI

Replace the hardcoded PR number `123` with a non-existent PR number that cannot match any real issue, OR mock the `gh` command by setting `PATH` to exclude it for tests that should NOT have review evidence:

The simpler approach: set `GH_TOKEN=""` in the hook's env for this specific test to force the `gh` command to fail (fail-open behavior, which is the hook's design). This is already the behavior in most test runs but should be made explicit.

Better approach: the test already relies on `gh` failing (no auth in test env). Document this assumption with a comment, and add a precondition assertion:

```typescript
test("detached HEAD without review evidence is denied", async () => {
  // Precondition: verify no todos/ directory exists (test isolation check)
  const todosExist = Bun.spawnSync(["test", "-d", join(repoDir, "todos")]);
  expect(todosExist.exitCode).not.toBe(0);

  // ... existing test code ...
});
```

**File:** `test/pre-merge-rebase.test.ts` (test block, ~line 385-397)

### Phase 3: Add `afterEach` safety net

Add an `afterEach` that verifies the repo is in a known clean state, catching any test that leaves behind state:

```typescript
afterEach(() => {
  // Safety net: ensure working tree is clean after each test
  const status = Bun.spawnSync(["git", "status", "--porcelain"], {
    cwd: repoDir,
    env: GIT_ENV,
  });
  const output = new TextDecoder().decode(status.stdout).trim();
  if (output) {
    // Force cleanup if a test left state behind
    Bun.spawnSync(["git", "checkout", "main"], { cwd: repoDir, env: GIT_ENV });
    Bun.spawnSync(["git", "reset", "--hard", "origin/main"], { cwd: repoDir, env: GIT_ENV });
    Bun.spawnSync(["git", "clean", "-fd"], { cwd: repoDir, env: GIT_ENV });
  }
});
```

**File:** `test/pre-merge-rebase.test.ts` (after beforeEach block, ~line 178)

## Acceptance Criteria

- [ ] Test "detached HEAD without review evidence is denied" passes reliably (10 consecutive runs)
- [ ] `beforeEach` explicitly cleans untracked files via `git clean -fd`
- [ ] No cross-test state leakage possible for `todos/` directory
- [ ] All 21 existing tests continue to pass
- [ ] No new test flakiness introduced

## Test Scenarios

- Given a clean repo after `beforeEach`, when the "detached HEAD without review evidence" test runs, then it produces a deny with `permissionDecision: "deny"`
- Given a prior test that called `addReviewEvidence()`, when `beforeEach` runs, then no `todos/` directory exists in the working tree
- Given all 21 tests run sequentially, when the full suite completes, then all tests pass with 0 failures
- Given the test suite runs 10 times consecutively, when checking results, then all runs show 21 pass / 0 fail

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal test isolation fix.

## Context

- Issue: #1694
- Files: `test/pre-merge-rebase.test.ts`, `.claude/hooks/pre-merge-rebase.sh`
- Related learnings: `2026-03-24-git-ceiling-directories-test-isolation.md`, `2026-03-28-pretooluse-hook-guard-ordering-matters.md`
- The hook itself is correct -- guard ordering (review gate before detached HEAD exit) is intentional per the 2026-03-28 learning
- The fix targets test isolation only, not hook behavior

## References

- Related PR: #1695 (fix-code-review-1683, where failure was discovered)
- Hook design: `2026-03-28-pretooluse-hook-guard-ordering-matters.md`
- Test isolation: `2026-03-24-git-ceiling-directories-test-isolation.md`
