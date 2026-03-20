---
title: "fix: replace git pull with bare-repo-safe alternatives in session startup scripts"
type: fix
date: 2026-03-20
---

# fix: Replace git pull with Bare-Repo-Safe Alternatives in Session Startup Scripts

## Overview

Sessions frequently fail with `fatal: this operation must be run in a work tree` when the LLM agent runs `git pull origin main` from the bare repo root. The worktree-manager.sh script has been hardened (IS_BARE guards, sync-bare-files, fetch-with-refspec), but several skill SKILL.md files still contain `git pull` instructions that the LLM follows verbatim. These instructions need to be replaced with bare-repo-safe alternatives.

## Problem Statement

### Root Cause

The repository uses `core.bare=true` at the root. `git pull` requires a working tree and fails immediately in bare repos. Three instruction sources lead the LLM to attempt `git pull origin main`:

1. **`plugins/soleur/skills/work/SKILL.md` (line 108):** Option A for creating a new branch says `git pull origin [default_branch]` -- this is the primary trigger
2. **`plugins/soleur/skills/one-shot/SKILL.md` (line 14):** Says "pull latest and create a feature branch" -- LLM interprets this as `git pull origin main`
3. **LLM improvisation:** Even when instructions don't say `git pull`, the LLM may independently decide to run it as a "best practice" before creating branches, because `git pull` is the most common way to update a branch in non-bare repos

### Why Previous Fixes Didn't Eliminate This

The worktree-manager.sh was hardened (PR #607 and follow-ups) to handle bare repos correctly:
- `IS_BARE` flag computed at init
- `update_branch_ref()` uses `git fetch origin main:main` in bare context
- `sync_bare_files` keeps on-disk files current
- `cleanup-merged` works from bare root

But these fixes only protect code paths within worktree-manager.sh. The LLM reads skill SKILL.md files as instructions and independently runs `git pull origin main` -- bypassing the hardened script entirely.

### Affected Sessions

This is a recurring failure that happens at the start of sessions when:
- The user starts a session from the bare repo root (common for new tasks without an existing worktree)
- The LLM follows work/SKILL.md Option A or one-shot/SKILL.md Step 0b
- The LLM improvises `git pull` as a "sync to latest" step before creating a worktree

## Proposed Solution

### Change 1: Update work SKILL.md Option A (Primary Fix)

Replace the `git pull origin [default_branch]` instruction with a bare-repo-safe pattern.

**File:** `plugins/soleur/skills/work/SKILL.md` (lines 105-110)

**Current:**
```markdown
**Option A: Create a new branch (default)**

\`\`\`bash
git pull origin [default_branch]
git checkout -b feature-branch-name
\`\`\`
```

**Proposed:**
```markdown
**Option A: Create a new branch (default)**

First, update the local branch ref (bare-repo-safe):

\`\`\`bash
git fetch origin [default_branch]
git checkout -b feature-branch-name origin/[default_branch]
\`\`\`

Note: Use `git fetch` + `origin/[default_branch]` ref, not `git pull`. This repo may use `core.bare=true` where `git pull` is unavailable.
```

**Rationale:** `git fetch` works in both bare and non-bare repos. Creating the branch from `origin/[default_branch]` instead of the local ref ensures it's based on the latest remote state without needing `git pull`.

### Change 2: Update one-shot SKILL.md Step 0b

Replace the "pull latest" instruction with explicit bare-repo-safe commands.

**File:** `plugins/soleur/skills/one-shot/SKILL.md` (line 14)

**Current:**
```markdown
**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), pull latest and create a feature branch named `feat/one-shot-<slugified-arguments>` before proceeding.
```

**Proposed:**
```markdown
**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), update refs and create a feature branch:

\`\`\`bash
git fetch origin main
git checkout -b feat/one-shot-<slugified-arguments> origin/main
\`\`\`

Do NOT use `git pull` -- it fails on bare repos. Use `git fetch` + branch from `origin/main`.
```

**Rationale:** The instruction "pull latest" is ambiguous and the LLM consistently interprets it as `git pull origin main`. Replacing with explicit commands eliminates the ambiguity.

### Change 3: Add Constitution Rule (Prevention)

Add a rule to `knowledge-base/project/constitution.md` under `## Architecture > ### Never` to prevent `git pull` in scripts/instructions that may run from bare repo context.

**File:** `knowledge-base/project/constitution.md`

**New rule in Architecture > Never section:**
```markdown
- Never use `git pull` in skill instructions, agent prompts, or shell scripts -- this repo uses `core.bare=true` where `git pull` is unavailable; use `git fetch origin <branch>` to update refs, then branch from `origin/<branch>` or merge `origin/<branch>` as needed
```

### Change 4: Update AGENTS.md Session-Start Instruction (Defense-in-Depth)

The current session-start instruction handles the "from worktree" case well but doesn't explicitly cover the "bare root, no worktree for this task" case. Add a bare-root fallback.

**File:** `AGENTS.md` (line 31)

**Current:**
```markdown
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists, run `git worktree list` from the bare root to verify.
```

**Proposed:**
```markdown
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists for the current task, run `git worktree list` from the bare root to verify, then create a worktree before doing any work. Never run `git pull` from the bare repo root -- use `git fetch origin main:main` to update refs if needed.
```

### Change 5: Audit campaign-calendar SKILL.md (Secondary)

**File:** `plugins/soleur/skills/campaign-calendar/SKILL.md` (line 110)

Contains `git pull --rebase origin main` in a CI push-retry block. This runs in CI context (not bare repo), so it's lower risk, but should be noted. If the campaign-calendar ever runs locally from the bare root, it would fail.

**Action:** No change needed now -- this is a CI-only code path. Document in the plan for awareness.

## Non-Goals

- Refactoring worktree-manager.sh (already hardened in previous PRs)
- Fixing other scripts that use `git rev-parse --show-toplevel` (tracked separately, see prior plan's "Other Scripts" section)
- Adding automated tests for bare repo scenarios (valuable but out of scope for this fix)

## Acceptance Criteria

- [ ] `work` SKILL.md no longer contains `git pull` -- uses `git fetch` + `origin/<branch>` instead (`plugins/soleur/skills/work/SKILL.md`)
- [ ] `one-shot` SKILL.md Step 0b uses explicit `git fetch` + `git checkout -b ... origin/main` instead of "pull latest" (`plugins/soleur/skills/one-shot/SKILL.md`)
- [ ] Constitution has a "Never use git pull" rule in Architecture > Never section (`knowledge-base/project/constitution.md`)
- [ ] AGENTS.md session-start instruction includes bare-root fallback guidance (`AGENTS.md`)
- [ ] No `git pull` instructions remain in any skill SKILL.md file (verified by grep)
- [ ] Existing `git fetch` usages in `merge-pr/SKILL.md` and `ship/SKILL.md` remain unchanged (they're already correct)

## Test Scenarios

- Given a session starting from the bare repo root with no active worktree, when the LLM follows work SKILL.md Option A, then it runs `git fetch origin main` + `git checkout -b ... origin/main` (no `git pull`)
- Given a session running one-shot from the bare repo root, when Step 0b executes, then it runs `git fetch origin main` + `git checkout -b ... origin/main` (no `git pull`)
- Given a session starting from an active worktree, when the LLM follows work SKILL.md, then behavior is unchanged (already on a feature branch, Option A is skipped)
- Given a non-bare repo using Soleur, when the LLM follows work SKILL.md Option A, then `git fetch` + `origin/<branch>` works identically to the old `git pull` flow (no regression)

### Edge Cases

- **No network:** `git fetch origin main` fails gracefully (same as `git pull` would). The LLM can proceed with the local ref.
- **Detached HEAD in bare repo:** `git branch --show-current` returns empty, which the LLM should handle by creating a worktree rather than trying to pull.

## Context

### Affected Files

| File | Change | Impact |
|------|--------|--------|
| `plugins/soleur/skills/work/SKILL.md` | Replace `git pull` with `git fetch` + `origin/` ref | Primary fix -- most common trigger |
| `plugins/soleur/skills/one-shot/SKILL.md` | Replace "pull latest" with explicit commands | Secondary fix -- one-shot pipeline trigger |
| `knowledge-base/project/constitution.md` | Add "Never use git pull" rule | Prevention -- stops future `git pull` additions |
| `AGENTS.md` | Add bare-root fallback to session-start instruction | Defense-in-depth -- catches improvised `git pull` |

### Related Learnings

- `knowledge-base/learnings/2026-03-18-worktree-create-feature-bare-root.md` -- bare repo worktree creation fix
- `knowledge-base/learnings/2026-03-18-worktree-manager-bare-repo-false-positive.md` -- IS_BARE conflation bug
- `knowledge-base/project/learnings/2026-03-13-bare-repo-stale-files-and-working-tree-guards.md` -- comprehensive bare repo failure model
- `knowledge-base/project/learnings/2026-03-18-bare-repo-cleanup-stale-script-and-fetch-refspec.md` -- fetch refspec vs plain fetch

### Related Plans

- `knowledge-base/project/plans/2026-03-13-fix-bare-repo-worktree-manager-stale-files-plan.md` -- prior plan that hardened worktree-manager.sh (all accepted criteria checked off)

### Semver

`semver:patch` -- bug fix, no new functionality

## MVP

### plugins/soleur/skills/work/SKILL.md

Replace lines 105-110:

```markdown
   **Option A: Create a new branch (default)**

   First, update refs from remote (bare-repo-safe):

   ```bash
   git fetch origin <default_branch>
   git checkout -b feature-branch-name origin/<default_branch>
   ```

   Do NOT use `git pull` -- it fails on bare repos (`core.bare=true`). Use `git fetch` + branch from `origin/<default_branch>`.

   Use a meaningful name based on the work (e.g., `feat/user-authentication`, `fix/email-validation`).
```

### plugins/soleur/skills/one-shot/SKILL.md

Replace line 14:

```markdown
**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), fetch latest and create a feature branch. Do NOT use `git pull` -- it fails on bare repos.

```bash
git fetch origin main
git checkout -b feat/one-shot-<slugified-arguments> origin/main
```

Parallel agents on the same repo cause silent merge conflicts when both work on main.
```

### knowledge-base/project/constitution.md

Add to `## Architecture > ### Never` section:

```markdown
- Never use `git pull` in skill instructions, agent prompts, or shell scripts -- this repo uses `core.bare=true` where `git pull` is unavailable; use `git fetch origin <branch>` to update refs, then branch from `origin/<branch>` or merge `origin/<branch>` as needed
```

### AGENTS.md

Update line 31 session-start instruction to add bare-root guidance:

```markdown
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists for the current task, run `git worktree list` from the bare root, then create a worktree before doing any work. Never run `git pull` from the bare repo root -- use `git fetch origin main:main` to update refs if needed.
```

## References

- Prior plan: `knowledge-base/project/plans/2026-03-13-fix-bare-repo-worktree-manager-stale-files-plan.md`
- worktree-manager.sh: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Constitution: `knowledge-base/project/constitution.md`
