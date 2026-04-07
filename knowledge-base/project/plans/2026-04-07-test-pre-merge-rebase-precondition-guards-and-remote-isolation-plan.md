---
title: "test: add precondition guards and remote isolation to pre-merge-rebase tests"
type: fix
date: 2026-04-07
---

# test: add precondition guards and remote isolation to pre-merge-rebase tests

Closes #1701, Closes #1702

Two test reliability improvements in `test/pre-merge-rebase.test.ts`:

1. **Precondition guards before JSON.parse (#1701):** Five tests call `JSON.parse(result.stdout)` without verifying stdout contains JSON. If a prior guard unexpectedly passes (e.g., test isolation leak), the hook returns empty stdout and `JSON.parse` throws a cryptic `SyntaxError` instead of a diagnostic message. PR #1704 added this pattern to the "detached HEAD without review evidence" test -- extend it to all remaining JSON-parsing tests.

2. **Remote ref reset in beforeEach (#1702):** Tests in the "with git repo" block share a single bare remote. Tests like "merge conflict aborts" (line 329) and "push failure after merge" (line 465) push commits to `origin/main`, permanently advancing the remote ref. The `beforeEach` resets the local repo but not the remote. If test execution order changes, earlier tests see a different `origin/main` than expected.

## Proposed Solution

### Phase 1: Precondition Guards (#1701)

Add `expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("")` before each `JSON.parse(result.stdout)` call in these tests:

- **"no review evidence blocks merge with deny"** (line 195)
- **"branch behind main triggers merge and push"** (line 287)
- **"uncommitted changes blocks merge with deny"** (line 302)
- **"staged uncommitted changes blocks merge with deny"** (line 322) -- issue body lists line 300, but the actual second instance is at 322
- **"merge conflict aborts and blocks with file list"** (line 352)
- **"push failure after merge blocks with deny"** (line 493)
- **"hook is idempotent -- second run after merge shows up-to-date"** (line 529) -- `JSON.parse(first.stdout)`

The "detached HEAD without review evidence" test (line 406) already has a precondition guard from PR #1704 -- no change needed there.

### Phase 2: Remote Ref Reset (#1702)

Capture the initial commit SHA in `beforeAll` (after the first push to `origin/main`) and reset the remote's `main` ref back to that SHA in `beforeEach`.

**Implementation:**

1. Add `let initialMainSha: string;` alongside the existing `repoDir` and `remoteDir` declarations
2. After `spawnChecked(["git", "push", "origin", "main"], { cwd: repoDir })` in `beforeAll`, capture the SHA:

   ```typescript
   initialMainSha = new TextDecoder()
     .decode(spawnChecked(["git", "rev-parse", "main"], { cwd: repoDir }).stdout)
     .trim();
   ```

3. In `beforeEach`, after `git clean -fd` and before the branch cleanup, reset the remote:

   ```typescript
   // Reset remote main to initial commit so tests that pushed to origin/main
   // don't affect subsequent tests (latent ordering dependency).
   spawnChecked(
     ["git", "update-ref", "refs/heads/main", initialMainSha],
     { cwd: remoteDir }
   );
   // Re-fetch so local origin/main tracks the reset remote.
   spawnChecked(["git", "fetch", "origin"], { cwd: repoDir });
   // Re-reset local main to match the now-reset origin/main.
   spawnChecked(["git", "reset", "--hard", "origin/main"], { cwd: repoDir });
   ```

   Note: The existing `git reset --hard origin/main` runs before `git clean -fd`. The remote reset must happen before the local reset, so the sequence becomes: (a) checkout main, (b) reset remote ref, (c) fetch origin, (d) reset local to origin/main, (e) git clean -fd.

## Files Changed

| File | Change |
|------|--------|
| `test/pre-merge-rebase.test.ts` | Add precondition guards, capture initial SHA, reset remote in beforeEach |

## Acceptance Criteria

- [ ] All 7 `JSON.parse(result.stdout)` calls (excluding the already-guarded detached HEAD test) are preceded by `expect(result.stdout, ...).not.toBe("")`
- [ ] `initialMainSha` is captured in `beforeAll` and used to reset the remote in `beforeEach`
- [ ] `beforeEach` resets the remote's `main` ref, fetches, then resets local -- in that order
- [ ] All 21 existing tests still pass
- [ ] No new test flakiness introduced (run test suite 3+ times)

## Test Scenarios

- Given a test where a prior guard unexpectedly passes, when `JSON.parse(result.stdout)` would receive empty string, then the precondition assertion fails with message "expected JSON deny output but got empty stdout" instead of `SyntaxError: Unexpected end of JSON input`
- Given the "merge conflict aborts" test has run and pushed to `origin/main`, when the next test runs, then `origin/main` points to the initial commit SHA (not the advanced one)
- Given all tests run in any order, when each test's `beforeEach` completes, then both local and remote repos are in the same initial state

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- PR #1704 established the precondition guard pattern for the "detached HEAD without review evidence" test
- Learning: `knowledge-base/project/learnings/test-failures/2026-04-07-git-reset-hard-does-not-clean-untracked-files-in-test-isolation.md` documents the root cause and fix pattern
- Current sequential test execution masks the #1702 ordering dependency, but bun may randomize order in future versions

## References

- Related issue: #1694 (original test isolation fix, closed by PR #1704)
- Related PR: #1704 (added `git clean -fd` and first precondition guard)
- File: `test/pre-merge-rebase.test.ts`
