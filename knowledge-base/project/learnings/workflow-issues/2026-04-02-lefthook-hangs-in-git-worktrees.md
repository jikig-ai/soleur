---
title: "Lefthook pre-commit hooks hang in git worktrees"
date: 2026-04-02
module: System
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "lefthook run pre-commit hangs indefinitely on web-platform-typecheck"
  - "Same tsc command completes in <30s when run directly"
  - "Multiple stalled lefthook processes accumulate"
root_cause: config_error
resolution_type: workflow_improvement
severity: medium
tags: [lefthook, worktree, typecheck, pre-commit, git]
---

# Lefthook Pre-Commit Hooks Hang in Git Worktrees

## Problem

When committing in a git worktree (`.worktrees/feat-*`), `lefthook run pre-commit` hangs indefinitely on the `web-platform-typecheck` command (`cd apps/web-platform && npx tsc --noEmit`). The same command completes in under 30 seconds when run directly from the same directory.

## Symptoms

- `lefthook run pre-commit` shows `web-platform-typecheck ❯` spinner and never completes
- Verbose output (`LEFTHOOK_VERBOSE=1`) confirms lefthook reaches `[lefthook] run:` but the subprocess never returns
- Multiple stalled `lefthook run` processes accumulate, requiring `pkill -f "lefthook run"` to clear
- The repo uses `core.bare=true` (bare repo with worktrees)

## Investigation

1. Verified `npx tsc --noEmit` passes from the worktree's `apps/web-platform/` directory (<30s)
2. Tested with `< /dev/null` to rule out stdin blocking — still passes when run directly
3. Set `extensions.worktreeConfig=true` and `core.bare=false` per-worktree — hook still hangs
4. Changed command to `./node_modules/.bin/tsc --noEmit` (skip npx) — still hangs
5. Changed command to `npx --yes tsc --noEmit < /dev/null` — still hangs
6. Changed command to `echo "test"` — echo runs but subsequent `bun-test` hook also hangs
7. Confirmed no tsc process is actually spawned (lefthook itself hangs before starting the subprocess)

## Root Cause

Unknown lefthook/worktree interaction. Lefthook v2.1.4 appears to have a bug where subprocess execution hangs in git worktree contexts, likely related to how it manages the git directory pointer (`.git` file pointing to `.git/worktrees/<name>` in the bare repo). The issue manifests when staged files match the glob pattern for the hook.

## Solution

Workaround: Use `LEFTHOOK=0 git commit` to bypass hooks after manually verifying that typecheck and tests pass:

```bash
# Manually verify checks
cd apps/web-platform && npx tsc --noEmit
cd apps/web-platform && npx vitest run

# Commit with hooks disabled
LEFTHOOK=0 git commit -m "message"
```

## Prevention

- When working in worktrees, run typecheck and tests manually before committing
- Use `LEFTHOOK=0` only after manual verification
- Monitor lefthook releases for worktree fixes
- Consider filing an upstream issue at lefthook GitHub

## Session Errors

**Subagent failed to commit work** — A parallel subagent completed all implementation (10 files, 945 insertions) but its commit never appeared in git log. Files were left as uncommitted changes. Recovery: manual staging and commit from the main agent. **Prevention:** After parallel subagent fan-out, always verify commits appeared in `git log` before proceeding. If missing, stage and commit manually.

**Multiple stalled lefthook processes** — 3 `lefthook run pre-commit` processes accumulated from failed commit attempts. Recovery: `pkill -f "lefthook run"`. **Prevention:** Check for stalled lefthook processes before retrying commits (`pgrep -fa lefthook`).

**core.bare=true fix attempt failed** — Set `extensions.worktreeConfig=true` and `core.bare=false` per-worktree, but this did not resolve the lefthook hang. Recovery: Reverted to `LEFTHOOK=0` workaround. **Prevention:** The issue is in lefthook's subprocess management, not git config.

## Related

- [2026-03-21 lefthook gobwas glob double star](../2026-03-21-lefthook-gobwas-glob-double-star.md) — different lefthook issue but same tool
- [2026-03-24 git ceiling directories test isolation](../2026-03-24-git-ceiling-directories-test-isolation.md) — related worktree/git env issues
