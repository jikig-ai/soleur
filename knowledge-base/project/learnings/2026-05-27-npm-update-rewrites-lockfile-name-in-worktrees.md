---
title: npm update rewrites lockfile name field in git worktrees
date: 2026-05-27
category: build-errors
tags: [build-errors, npm, worktrees]
---

# Learning: npm update rewrites lockfile name field in git worktrees

## Problem

Running `npm update liquidjs` inside a git worktree at `.worktrees/feat-one-shot-fix-liquidjs-dependabot-vulns/` silently rewrote `package-lock.json`'s `"name"` field from `"soleur"` to `"feat-one-shot-fix-liquidjs-dependabot-vulns"` — the worktree directory name. The lockfile has no `"name"` in `package.json` to anchor to, so npm infers it from the directory.

## Solution

After any `npm update` or `npm install` in a worktree, verify the lockfile's `name` field matches `origin/main`:

```bash
EXPECTED=$(git show origin/main:package-lock.json | head -3 | grep '"name"' | sed 's/.*: "//;s/".*//')
ACTUAL=$(head -3 package-lock.json | grep '"name"' | sed 's/.*: "//;s/".*//')
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  sed -i "s/\"name\": \"$ACTUAL\"/\"name\": \"$EXPECTED\"/" package-lock.json
fi
```

## Key Insight

npm derives the project name from the nearest `package.json` `name` field, falling back to the directory name when absent. Git worktrees have different directory names than the repo root, so any lockfile-mutating npm command can silently rewrite the `name`. This is cosmetic but pollutes the diff and can confuse lockfile-aware tools.

## Session Errors

1. **npm rewrote lockfile name to worktree directory name** — Recovery: manual `Edit` to restore `"soleur"`, amend commit. Prevention: add a post-`npm update` verification step to the work skill's lockfile-bump reference doc.
2. **Commit message quoted stale version number** — Recovery: caught by git-history-analyzer review agent (P3). Prevention: always re-run `npm ls <pkg>` at commit-message-drafting time rather than carrying forward plan-time measurements.

## Tags
category: build-errors
module: npm/worktrees
