# Learning: shared bare remote ordering dependency in test isolation

## Problem

Tests in `test/pre-merge-rebase.test.ts` share a single bare remote created in `beforeAll`. Tests like "merge conflict aborts" and "push failure after merge" push commits to `origin/main`, permanently advancing the remote ref. The `beforeEach` reset the local repo but not the remote, creating a latent ordering dependency — if test execution order changes, earlier tests see a different `origin/main` than expected.

Additionally, 7 `JSON.parse(result.stdout)` calls lacked precondition guards. If test isolation leaked (e.g., review evidence from a prior test), the hook would return empty stdout and `JSON.parse` would throw a cryptic `SyntaxError` instead of a diagnostic message.

## Solution

1. **Remote ref reset in beforeEach:** Capture `initialMainSha` in `beforeAll` after the first push, then reset the remote's `refs/heads/main` back to that SHA in each `beforeEach` using `git update-ref`. Follow with `git fetch origin` and `git reset --hard origin/main` to sync the local clone.

2. **Precondition guards:** Add `expect(result.stdout, "expected JSON deny output but got empty stdout").not.toBe("")` before each `JSON.parse(result.stdout)` call. This surfaces a diagnostic assertion failure instead of an opaque `SyntaxError`.

## Key Insight

When tests share a mutable remote, `beforeEach` must reset both local AND remote state. `git update-ref` on the bare remote is the cleanest approach — it avoids force-push semantics and operates directly on the ref store. The 3-step sequence (update-ref on remote → fetch → reset --hard) provides complete state isolation without per-test bare repo overhead.

## Tags

category: test-failures
module: pre-merge-rebase-hook
