---
title: "fix: worktree verification gap, SKILL.md sharp edges, vitest rolldown binding"
type: fix
date: 2026-04-10
---

# Fix: Worktree Verification Gap, SKILL.md Sharp Edges, Vitest Rolldown Binding

Batch fix for three related engineering issues: #1854 (worktree-manager verification), #1855 (SKILL.md route-to-definition), and #1856 (vitest rolldown binding).

## Overview

Three small engineering fixes grouped into a single batch:

1. **#1854 -- worktree-manager.sh reports success when directory not created:** PR #1806 already merged a `git rev-parse --show-toplevel` verification into both `create_worktree()` and `create_for_feature()`. The issue's proposed `[[ -d "$worktree_path" ]]` check is weaker than what shipped. The remaining work is to verify the fix is sufficient and close the issue -- or add the directory check as a belt-and-suspenders guard before the git check.
2. **#1855 -- route-to-definition for git-worktree SKILL.md:** Add a Sharp Edges / Known Issues section to `plugins/soleur/skills/git-worktree/SKILL.md` documenting the silent failure fallback pattern.
3. **#1856 -- vitest fails with missing @rolldown/binding-linux-x64-gnu:** The `npx vitest run` invocation can resolve a different vitest version from the npx cache that depends on rolldown native bindings not installed locally. Fix by running vitest through the local `node_modules/.bin/vitest` binary instead of npx.

## Problem Statement

### Issue #1854

`worktree-manager.sh` historically could print "Worktree created successfully!" when the directory was not actually created or was not a functioning git worktree. PR #1806 merged a fix on 2026-04-10 that adds `git rev-parse --show-toplevel` verification to both `create_worktree()` (line 322) and `create_for_feature()` (line 393). The fix exits non-zero if verification fails and cleans up the partial directory.

**Current status:** The proposed fix in the issue (`[[ -d "$worktree_path" ]]`) is simpler but weaker than what already shipped. The shipped fix checks both directory existence (implicitly, via `git -C`) and git worktree validity. The issue can be closed with verification that the existing fix covers the described scenario.

### Issue #1855

A learning (`knowledge-base/project/learnings/2026-04-07-worktree-manager-partial-creation-failure.md`) documents the silent failure behavior but the SKILL.md for git-worktree has no Sharp Edges section warning users about the fallback pattern. Route-to-definition requires adding this to the skill docs.

### Issue #1856

`npx vitest run` in `apps/web-platform` fails with `Cannot find module '@rolldown/binding-linux-x64-gnu'`. This happens when the npx cache contains a vitest version (from vite 7.x's rolldown dependency) that differs from the locally installed one. The `package.json` has `"vitest": "^3.1.0"` with an override `"vite": "^7.3.2"`. The installed versions are vitest 3.2.4 and vite 7.3.2. Tests pass when vitest resolves from `node_modules/.bin/`.

**Root cause:** `npx vitest run` checks the npx cache before `node_modules/.bin/`. If a different vitest version is cached globally (e.g., one that bundles rolldown bindings for a different architecture), the cached version takes precedence. The fix is to use `node_modules/.bin/vitest run` or the npm script (`npm run test`) instead of `npx vitest run`.

## Proposed Solution

### Task 1: Verify #1854 fix and add belt-and-suspenders check

**File:** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

1. Verify the existing `git rev-parse --show-toplevel` check (lines 322-334 in `create_worktree()`, lines 393-405 in `create_for_feature()`) covers the scenario described in #1854
2. Add a simple directory existence check before the git check as defense-in-depth:

```bash
# plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh (create_worktree, after git worktree add)
if [[ ! -d "$worktree_path" ]]; then
  echo -e "${RED}Error: Worktree directory not created at $worktree_path${NC}"
  exit 1
fi
```

Insert this before the existing `git rev-parse` verification in both `create_worktree()` and `create_for_feature()`.

### Task 2: Add Sharp Edges section to SKILL.md (#1855)

**File:** `plugins/soleur/skills/git-worktree/SKILL.md`

Add before the `## Technical Details` section:

```markdown
## Sharp Edges

- If `worktree-manager.sh` reports success but `cd` to the worktree path fails or `git branch --show-current` returns an unexpected branch (e.g., `main`), the worktree was not properly created. Fall back to `git worktree add` directly: `git worktree add .worktrees/<name> -b <name> main`. The script includes post-creation verification (added in #1806) but edge cases on bare repos may still produce partial directories. Tracked in #1854.
- The `draft-pr` subcommand path shown in success output uses `SCRIPT_DIR` -- invoke it from inside the worktree, not from the bare repo root.
```

### Task 3: Fix vitest invocation to use local binary (#1856)

**File:** `scripts/test-all.sh`

Change the vitest invocation from `npx vitest run` to use the local binary:

```bash
# Before:
run_suite "apps/web-platform" bash -c "cd apps/web-platform && npx vitest run 2>&1"

# After:
run_suite "apps/web-platform" bash -c "cd apps/web-platform && ./node_modules/.bin/vitest run 2>&1"
```

Also update `.github/workflows/ci.yml` line 67 if it uses `npx` for vitest (currently it uses `npx tsc --noEmit` for typecheck, which is fine -- tsc doesn't have the same cache issue).

**Alternative considered:** Clearing `~/.npm/_npx/` -- rejected because it is a local workaround that doesn't prevent recurrence and doesn't fix CI if the cache ever diverges there.

**Alternative considered:** Pinning vitest to an exact version -- rejected because `^3.1.0` is already in `package.json` and the lockfile pins the exact version; the issue is npx resolving outside the lockfile.

## Acceptance Criteria

- [ ] `worktree-manager.sh` `create_worktree()` has a `[[ ! -d "$worktree_path" ]]` check before the `git rev-parse` verification
- [ ] `worktree-manager.sh` `create_for_feature()` has the same directory check
- [ ] `plugins/soleur/skills/git-worktree/SKILL.md` has a Sharp Edges section documenting the fallback pattern
- [ ] `scripts/test-all.sh` uses `./node_modules/.bin/vitest run` instead of `npx vitest run`
- [ ] All existing tests pass (`bash scripts/test-all.sh`)

## Test Scenarios

- Given a fresh worktree creation via `worktree-manager.sh create <name>`, when `git worktree add` succeeds, then the script prints success and the directory exists
- Given a worktree creation where `git worktree add` silently fails (directory not created), when the script runs the post-creation check, then it exits with a non-zero code and prints an error
- Given `scripts/test-all.sh` is invoked, when vitest runs for `apps/web-platform`, then it uses the local `node_modules/.bin/vitest` binary (not npx cache)
- Given the SKILL.md for git-worktree, when a user reads the Sharp Edges section, then they find the fallback pattern for silent creation failures

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- PR #1806 (merged) already added `git rev-parse --show-toplevel` verification to worktree-manager.sh
- Learning: `knowledge-base/project/learnings/2026-04-07-worktree-manager-partial-creation-failure.md` documents the root cause
- `apps/web-platform/package.json` has vitest `^3.1.0` with vite override `^7.3.2`
- CI runs tests via `bash scripts/test-all.sh` which calls `npx vitest run`
- Local tests pass with `npx vitest run` when the npx cache is clean

## References

- Issue #1854: [worktree-manager.sh reports success when worktree directory not created](https://github.com/jikig-ai/soleur/issues/1854)
- Issue #1855: [compound: route-to-definition proposal for git-worktree SKILL.md](https://github.com/jikig-ai/soleur/issues/1855)
- Issue #1856: [fix: vitest fails with missing @rolldown/binding-linux-x64-gnu](https://github.com/jikig-ai/soleur/issues/1856)
- PR #1806: [bot-fix] Fix #1756: verify worktree after creation and add SCRIPT_DIR
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (lines 264-347, 350-427)
- `plugins/soleur/skills/git-worktree/SKILL.md`
- `scripts/test-all.sh`
- `apps/web-platform/package.json`
