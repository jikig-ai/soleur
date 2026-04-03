---
module: System
date: 2026-04-03
problem_type: test_failure
component: testing_framework
symptoms:
  - "resolve-git-root.test.sh Test 2 fails with 'Error: Not inside a git repository'"
  - "Pre-commit hook bun-test exits 1, blocking all commits touching .ts/.tsx files"
root_cause: test_isolation
resolution_type: code_fix
severity: high
tags: [git-env-vars, lefthook, pre-commit, test-isolation, bare-repo]
synced_to: []
---

# Learning: GIT_* env vars leak from lefthook into test subshells, breaking bare repo detection

## Problem

`plugins/soleur/test/resolve-git-root.test.sh` Test 2 ("Bare repo sets GIT_ROOT and IS_BARE=true") failed when run inside lefthook's `bun-test` pre-commit hook. The test created a fresh bare repo in `/tmp`, `cd`'d into it, and sourced the helper — but git couldn't detect the bare repo.

The error: `Error: Not inside a git repository.`

This blocked ALL commits touching `.ts`/`.tsx` files from worktrees, since the pre-commit hook runs the full test suite.

## Solution

The test already cleared `GIT_DIR` and `GIT_WORK_TREE` at the top, but lefthook injects additional GIT environment variables (`GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, etc.) that override git's repo detection even in freshly-created test repos.

Fixed by clearing ALL GIT_* env vars:

```bash
# Before (incomplete):
unset GIT_DIR GIT_WORK_TREE 2>/dev/null || true

# After (complete):
while IFS= read -r var; do
  unset "$var" 2>/dev/null || true
done < <(env | grep -oP '^GIT_\w+' || true)
```

## Key Insight

The existing learning (`2026-03-24-git-ceiling-directories-test-isolation.md`) already documented that `GIT_INDEX_FILE` leaks from pre-commit hooks. But `resolve-git-root.test.sh` only cleared `GIT_DIR` and `GIT_WORK_TREE` — it was written before or without referencing that learning. The defensive pattern is: clear ALL `GIT_*` vars, not a manually-maintained list. New GIT env vars can be added by git or tools at any time; an allowlist approach will always have gaps.

## Session Errors

1. **`core.bare=true` blocking git commands in worktrees** — `git status`, `git add`, `git commit` fail with "this operation must be run in a work tree" when `core.bare=true` is inherited. Recovery: used `git -c core.bare=false` or `GIT_WORK_TREE=<path>` env var. **Prevention:** Already documented in constitution; the worktree-manager script should set `core.bare=false` in worktree-local config on creation.

2. **`npx vitest` stale cache with missing native bindings** — `npx vitest` picked up a cached version requiring `@rolldown/binding-linux-x64-gnu`. Recovery: used `./node_modules/.bin/vitest` directly. **Prevention:** Always use project-local test runner (`./node_modules/.bin/vitest` or the package.json test script), never `npx` for project test tools.

3. **Security reminder hook blocked Edit** — Expected behavior on first `.tsx` edit in session. Recovery: retried successfully. **Prevention:** None needed (working as designed).

## Related

- [git-ceiling-directories-test-isolation](2026-03-24-git-ceiling-directories-test-isolation.md) — same class of GIT env var leak from pre-commit hooks
- Issue: [#1463](https://github.com/jikig-ai/soleur/issues/1463) — tracking issue created before fix

## Tags

category: test-failures
module: System
