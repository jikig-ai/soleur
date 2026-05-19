---
name: dependabot-prs-need-bun-lock-resync-and-override-dedup
description: Dependabot's npm-ecosystem PRs in apps/web-platform fail CI because they leave bun.lock drifted and skip nested vulnerable copies — both require a manual follow-up push.
metadata:
  category: workflow-patterns
  module: dependabot
  date: 2026-05-19
tags:
  - dependabot
  - lockfile
  - bun
  - npm
  - overrides
---

## Problem

Dependabot opens PRs against `apps/web-platform/package-lock.json` when it sees a vulnerable npm package. Two recurring failure modes ship with every such PR:

1. **bun.lock drift** — Dependabot is npm-only; `apps/web-platform` carries both `package-lock.json` and `bun.lock`. The PR updates `package.json` + `package-lock.json` only, leaving `bun.lock` pinned to the old version. CI's `bun install --frozen-lockfile` step (`test-webplat`, `e2e`, aggregate `test`) fails with:

   ```
   error: lockfile had changes, but lockfile is frozen
   note: try re-running without --frozen-lockfile and commit the updated lockfile
   ```

2. **Nested vulnerable copies survive the top-level bump** — Bumping the direct dep doesn't dedup nested copies if other packages declare a narrower range. For PR #4035, after bumping top-level `ws` to 8.20.1, nested `@supabase/realtime-js/ws` and `happy-dom/ws` stayed at 8.19.0 (still inside the vulnerable range). Dependabot's alert stays open even after the PR merges.

This is the rule `cq-before-pushing-package-json-changes` enforces for humans (regenerate both lockfiles), but Dependabot can't see the rule.

## Solution

Manual follow-up workflow per Dependabot PR in this repo:

```bash
# 1. Worktree the dependabot branch, rebase onto current main (often there
#    are other dep PRs landing concurrently)
git fetch origin <dependabot-branch>
git worktree add .worktrees/fix-<name> -B fix-<name> origin/<dependabot-branch>
cd .worktrees/fix-<name>
git rebase origin/main

# 2. Add the bumped dep to the `overrides` block in apps/web-platform/package.json
#    (forces dedup of nested copies)

# 3. Regenerate BOTH lockfiles
cd apps/web-platform
bun install
npm install

# 4. Verify only the patched version resolves (no nested copies linger)
grep -E '"<pkg>@[0-9]' bun.lock
grep -B1 -A3 "node_modules/<pkg>" package-lock.json

# 5. Commit, push as a new branch, open a new PR superseding the dependabot one
```

Close the original Dependabot PR with a comment pointing to the supersession PR. The bot re-files if the alert is still open after closure.

## Root Cause

Dependabot's `npm_and_yarn` ecosystem updater only handles npm/yarn/pnpm lockfiles. There's no "primary lockfile" concept that detects sibling `bun.lock` — adding bun lockfile support is a Dependabot product gap (tracked upstream; no ETA).

Override-based dedup is a separate concern Dependabot intentionally doesn't touch — it would alter user-controlled config.

## Key Insight

A Dependabot PR is a *starting point*, not a finished change. Treat every Dependabot PR against `apps/web-platform` as "rebase + bun install + maybe override + push" rather than expecting a one-click merge. The two-step pattern is consistent enough to script if volume grows.

## Prevention Options Considered (Not Acted On)

- **CI auto-fix workflow** — listen for `dependabot[bot]` PRs, run `bun install`, push back. Adds infra; requires PAT with write access to dependabot/* branches; high blast-radius if it ever misfires.
- **Drop bun.lock** — npm-only would eliminate drift but loses bun's faster install for local dev. Not worth the speed tradeoff for occasional Dependabot toil.
- **Drop package-lock.json** — Dockerfile uses `npm ci`. Switching the build to `bun install --frozen-lockfile` is feasible but a bigger change than this learning warrants.

Current approach: manual follow-up per PR, documented here so the recipe is one lookup away.

## Related

- [[worktree-recovery-check-pr-merge-status-first]] — same session, worktree-recovery checklist
- `AGENTS.rest.md` rule `cq-before-pushing-package-json-changes` — the human-facing version of the dual-lockfile requirement
