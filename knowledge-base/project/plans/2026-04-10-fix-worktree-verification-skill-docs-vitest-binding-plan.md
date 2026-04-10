---
title: "fix: worktree verification gap, SKILL.md sharp edges, vitest rolldown binding"
type: fix
date: 2026-04-10
deepened: 2026-04-10
---

# Fix: Worktree Verification Gap, SKILL.md Sharp Edges, Vitest Rolldown Binding

Batch fix for three related engineering issues: #1854 (worktree-manager verification), #1855 (SKILL.md route-to-definition), and #1856 (vitest rolldown binding).

## Enhancement Summary

**Deepened on:** 2026-04-10
**Sections enhanced:** 3 (Proposed Solution, Test Scenarios, Context)
**Research sources used:** local repo analysis, existing learnings, dependency chain verification

### Key Improvements

1. Confirmed #1854 is already substantially fixed by PR #1806 -- the belt-and-suspenders `[[ ! -d ]]` check is still worthwhile but the plan now reflects that the core fix is shipped
2. Identified that vite 7.3.2 uses rollup (not rolldown) -- the rolldown dependency comes from a newer vitest cached in npx, confirming the root cause analysis
3. Added learnings from `2026-03-30-npm-latest-tag-crosses-major-versions.md` and worktree-specific learnings to strengthen the plan's edge case coverage
4. Recommended adding a `test:ci` npm script to `apps/web-platform/package.json` as a more robust alternative to `./node_modules/.bin/vitest run`

### New Considerations Discovered

- The `npx` cache issue is a variant of the same class of problem documented in the `npm-latest-tag` learning -- npx resolves versions independently of the project lockfile
- Three worktree-related learnings exist in the knowledge base that should be cross-referenced in the SKILL.md Sharp Edges section
- The `test-all.sh` script already unsets `GIT_DIR` and `GIT_WORK_TREE` (per learning `2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`) -- the vitest fix should not regress this

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

#### Research Insights (Task 1)

**Existing verification is robust:** The `git -C "$worktree_path" rev-parse --show-toplevel` check on lines 322-334 already catches the scenario described in #1854 -- if the directory does not exist, `git -C` fails immediately. The belt-and-suspenders `[[ ! -d ]]` check adds value as a fast-fail before the more expensive git subprocess, and produces a clearer error message ("directory not created" vs. git's "cannot chdir").

**Relevant learnings:**

- `2026-04-07-worktree-manager-partial-creation-failure.md`: Documents the exact failure mode -- `mkdir -p` in `create_for_feature()` created a directory with `knowledge-base/` but no `.git` file. The existing `git rev-parse` check catches this case (git discovery fails without `.git`). The `[[ ! -d ]]` check would NOT catch this case because the directory exists -- it catches the no-directory-at-all case.
- `2026-03-17-worktree-creation-requires-absolute-path-from-bare-root.md`: Relative paths resolve from CWD, not GIT_DIR. The script already uses `$WORKTREE_DIR/$branch_name` which is absolute. No gap here.

**Edge case not covered by either check:** If `git worktree add` creates the directory and `.git` file but the branch ref is wrong (e.g., points to `main` instead of the new branch), the existing path-match check (`$actual_toplevel != $worktree_path`) does not detect this. A branch verification (`git -C "$worktree_path" rev-parse --abbrev-ref HEAD`) after the toplevel check would close this gap. This is an enhancement, not a blocker for this fix.

### Task 2: Add Sharp Edges section to SKILL.md (#1855)

**File:** `plugins/soleur/skills/git-worktree/SKILL.md`

Add before the `## Technical Details` section:

```markdown
## Sharp Edges

- If `worktree-manager.sh` reports success but `cd` to the worktree path fails or `git branch --show-current` returns an unexpected branch (e.g., `main`), the worktree was not properly created. Fall back to `git worktree add` directly: `git worktree add .worktrees/<name> -b <name> main`. The script includes post-creation verification (added in #1806) but edge cases on bare repos may still produce partial directories. Tracked in #1854.
- The `draft-pr` subcommand path shown in success output uses `SCRIPT_DIR` -- invoke it from inside the worktree, not from the bare repo root.
- When creating worktrees from inside another worktree, always use absolute paths. Relative paths resolve from CWD, not from `GIT_DIR`, creating nested worktrees that are difficult to clean up. The script handles this correctly but manual `git worktree add` commands are susceptible (learning: `2026-03-17-worktree-creation-requires-absolute-path-from-bare-root.md`).
```

#### Research Insights (Task 2)

**Cross-reference with existing learnings:** Three worktree-related learnings exist that should inform the Sharp Edges content:

1. `2026-04-07-worktree-manager-partial-creation-failure.md` -- partial directory creation (the primary failure mode)
2. `2026-03-17-worktree-creation-requires-absolute-path-from-bare-root.md` -- relative path resolution from CWD
3. `2026-04-02-lefthook-hangs-in-git-worktrees.md` -- lefthook can hang >60s in worktrees (already documented in AGENTS.md but worth mentioning in SKILL.md)

**SKILL.md currently has no Sharp Edges section.** The section should be placed before `## Technical Details` (line 293 of SKILL.md) to match the convention used in other skills.

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

**Recommended additional change:** Add a `test:ci` script to `apps/web-platform/package.json`:

```json
"scripts": {
  "test": "vitest",
  "test:ci": "vitest run"
}
```

Then update `scripts/test-all.sh` to use:

```bash
run_suite "apps/web-platform" bash -c "cd apps/web-platform && npm run test:ci 2>&1"
```

This is more robust than `./node_modules/.bin/vitest run` because `npm run` always resolves from the project's `node_modules/.bin/` and is the standard npm convention for CI vs. development test modes.

**Alternative considered:** Clearing `~/.npm/_npx/` -- rejected because it is a local workaround that doesn't prevent recurrence and doesn't fix CI if the cache ever diverges there.

**Alternative considered:** Pinning vitest to an exact version -- rejected because `^3.1.0` is already in `package.json` and the lockfile pins the exact version; the issue is npx resolving outside the lockfile.

**Alternative considered:** `npx --no` flag to prevent remote fetch -- rejected because modern npx (npm 7+) does not support this flag. The equivalent `npm exec --no` exists but still checks the npx cache.

#### Research Insights (Task 3)

**Root cause confirmed via dependency chain:** Vite 7.3.2 (the version installed via override) uses `rollup` ^4.43.0 as its bundler, NOT `rolldown`. The `@rolldown/binding-linux-x64-gnu` dependency would come from a vite 8.x pre-release or vitest 4.x that npx resolves from its global cache. This confirms the diagnosis: the locally installed vitest (3.2.4 via lockfile) works correctly, but npx can resolve a different version.

**Relevant learning:** `2026-03-30-npm-latest-tag-crosses-major-versions.md` documents the same class of problem -- npm/npx version resolution operates independently of the project's lockfile. The key insight applies here: "npx is not 'run from local node_modules' -- it is 'run from cache or fetch.'"

**`test-all.sh` context:** The script already contains GIT env var cleanup (lines 21-26, per learning `2026-04-03-lefthook-git-env-var-leak-breaks-tests.md`). The vitest invocation change is isolated and does not interact with the env cleanup.

## Acceptance Criteria

- [x] `worktree-manager.sh` `create_worktree()` has a `[[ ! -d "$worktree_path" ]]` check before the `git rev-parse` verification
- [x] `worktree-manager.sh` `create_for_feature()` has the same directory check
- [x] `plugins/soleur/skills/git-worktree/SKILL.md` has a Sharp Edges section documenting the fallback pattern, absolute path requirement, and lefthook caveat
- [x] `apps/web-platform/package.json` has a `test:ci` script set to `vitest run`
- [x] `scripts/test-all.sh` uses `npm run test:ci` (or `./node_modules/.bin/vitest run`) instead of `npx vitest run`
- [x] All existing tests pass (`bash scripts/test-all.sh`)
- [x] Both lockfiles (`bun.lock` and `package-lock.json`) regenerated if `package.json` changes

## Test Scenarios

- Given a fresh worktree creation via `worktree-manager.sh create <name>`, when `git worktree add` succeeds, then the script prints success and the directory exists
- Given a worktree creation where `git worktree add` silently fails (directory not created), when the script runs the post-creation check, then it exits with a non-zero code and prints "Error: Worktree directory not created"
- Given a worktree creation where `git worktree add` creates a directory but not a valid git worktree (partial creation), when the script runs the git rev-parse check, then it exits with a non-zero code and cleans up the partial directory
- Given `scripts/test-all.sh` is invoked, when vitest runs for `apps/web-platform`, then it uses `npm run test:ci` which resolves vitest from `node_modules/.bin/` (not npx cache)
- Given the SKILL.md for git-worktree, when a user reads the Sharp Edges section, then they find documentation for: (1) silent creation failure fallback, (2) absolute path requirement, (3) lefthook hang workaround
- Given `apps/web-platform/package.json` has a `test:ci` script, when `npm run test:ci` is executed from the web-platform directory, then vitest runs in single-run mode and exits

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change.

## Context

- PR #1806 (merged) already added `git rev-parse --show-toplevel` verification to worktree-manager.sh -- the core of #1854 is already fixed
- Learning: `knowledge-base/project/learnings/2026-04-07-worktree-manager-partial-creation-failure.md` documents the root cause
- Learning: `knowledge-base/project/learnings/2026-03-17-worktree-creation-requires-absolute-path-from-bare-root.md` documents absolute path requirement
- Learning: `knowledge-base/project/learnings/2026-03-30-npm-latest-tag-crosses-major-versions.md` documents the same class of npx/npm resolution issue
- Learning: `knowledge-base/project/learnings/workflow-issues/2026-04-03-lefthook-git-env-var-leak-breaks-tests.md` documents GIT env var cleanup in test-all.sh
- `apps/web-platform/package.json` has vitest `^3.1.0` with vite override `^7.3.2` -- installed: vitest 3.2.4, vite 7.3.2
- Vite 7.3.2 depends on rollup ^4.43.0 (NOT rolldown) -- rolldown dependency comes from a newer cached vitest/vite version
- CI runs tests via `bash scripts/test-all.sh` which calls `npx vitest run`
- Local tests pass with `npx vitest run` when the npx cache is clean or absent
- The `test-all.sh` script already handles GIT env var cleanup (lines 21-26) -- the vitest fix is isolated

## References

- Issue #1854: [worktree-manager.sh reports success when worktree directory not created](https://github.com/jikig-ai/soleur/issues/1854)
- Issue #1855: [compound: route-to-definition proposal for git-worktree SKILL.md](https://github.com/jikig-ai/soleur/issues/1855)
- Issue #1856: [fix: vitest fails with missing @rolldown/binding-linux-x64-gnu](https://github.com/jikig-ai/soleur/issues/1856)
- PR #1806: [bot-fix] Fix #1756: verify worktree after creation and add SCRIPT_DIR
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` (lines 264-347, 350-427)
- `plugins/soleur/skills/git-worktree/SKILL.md`
- `scripts/test-all.sh`
- `apps/web-platform/package.json`
