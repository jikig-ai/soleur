---
title: "fix: replace git pull with bare-repo-safe alternatives in session startup scripts"
type: fix
date: 2026-03-20
---

# fix: Replace git pull with Bare-Repo-Safe Alternatives in Session Startup Scripts

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources:** live bare-repo command verification, 4 institutional learnings, repo-wide grep audit, git-worktree SKILL.md analysis

### Key Improvements
1. **Critical bug found in original plan:** `git checkout -b ... origin/main` also fails from bare repo root -- the proposed MVP would not have worked
2. Discovered that the correct approach from bare repo root is `git worktree add` via worktree-manager.sh, not `git checkout -b`
3. Work SKILL.md Option A should be removed entirely (not patched) since this repo always uses worktrees -- Option B is the only valid path
4. Expanded the constitution rule to cover both `git pull` AND `git checkout` from bare context
5. Added a bare-repo command compatibility table for implementers to reference

### New Considerations Discovered
- `git branch --show-current` returns `main` from bare repo root, which triggers the "on default branch, must create branch" logic in both work and one-shot skills
- The one-shot skill's `git checkout -b` replacement also needs to use `git worktree add` for bare-repo safety
- The work SKILL.md already has Option B (worktree) as the correct path -- Option A is dead code in this repo

## Overview

Sessions frequently fail with `fatal: this operation must be run in a work tree` when the LLM agent runs `git pull origin main` from the bare repo root. The worktree-manager.sh script has been hardened (IS_BARE guards, sync-bare-files, fetch-with-refspec), but several skill SKILL.md files still contain `git pull` instructions that the LLM follows verbatim. These instructions need to be replaced with bare-repo-safe alternatives.

### Research Insights

**Verified git command behavior from bare repo root (live testing 2026-03-20):**

| Command | Works in bare repo? | Notes |
|---------|---------------------|-------|
| `git fetch origin main` | Yes | Updates FETCH_HEAD and origin/main |
| `git fetch origin main:main` | Yes | Also advances local main ref |
| `git rev-parse origin/main` | Yes | Returns commit SHA |
| `git branch --show-current` | Yes | Returns `main` (the HEAD ref) |
| `git worktree add -b <name> <path> origin/main` | Yes | Creates worktree + branch |
| `git pull origin main` | **No** | Requires working tree (exit 128) |
| `git checkout -b <name> origin/main` | **No** | Requires working tree (exit 128) |
| `git checkout <branch>` | **No** | Requires working tree (exit 128) |

**Critical finding:** The original plan proposed replacing `git pull` with `git checkout -b ... origin/main`, but `git checkout` also requires a working tree. The only way to create a branch from a bare repo root is `git worktree add`.

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

### Change 1: Remove work SKILL.md Option A, Make Worktree the Default (Primary Fix)

Option A (`git pull` + `git checkout -b`) is entirely non-functional in bare repos -- both commands require a working tree. Rather than patching it with another working-tree command (`git checkout -b ... origin/main` also fails), remove Option A and make the worktree path (current Option B) the sole branch creation method.

**File:** `plugins/soleur/skills/work/SKILL.md` (lines 103-121)

**Current:**
```markdown
   **If on the default branch**, you MUST create a branch before proceeding. Never edit files on the default branch -- parallel agents cause silent merge conflicts.

   **Option A: Create a new branch (default)**

   \`\`\`bash
   git pull origin [default_branch]
   git checkout -b feature-branch-name
   \`\`\`

   Use a meaningful name based on the work (e.g., `feat/user-authentication`, `fix/email-validation`).

   **Option B: Use a worktree (recommended for parallel development)**

   \`\`\`bash
   skill: git-worktree
   # The skill will create a new branch from the default branch in an isolated worktree
   \`\`\`

   Prefer worktree if other worktrees already exist or multiple features are in-flight.
```

**Proposed:**
```markdown
   **If on the default branch**, you MUST create a worktree before proceeding. Never edit files on the default branch -- parallel agents cause silent merge conflicts, and this repo uses `core.bare=true` where `git pull` and `git checkout` are unavailable.

   Create a worktree for the new feature:

   \`\`\`bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feature-branch-name
   \`\`\`

   Then `cd` into the worktree path printed by the script. The worktree manager handles bare-repo detection, branch creation from latest origin/main, .env copying, and dependency installation.

   Use a meaningful name based on the work (e.g., `feat-user-authentication`, `fix-email-validation`).
```

**Rationale:** Option A uses two commands that both fail in bare repos (`git pull`, `git checkout -b`). Option B (worktree via worktree-manager.sh) is the only path that works. The worktree-manager.sh already has bare-repo detection via `IS_BARE` and uses `git fetch origin main:main` internally. Since this repo always uses worktrees (AGENTS.md Hard Rule 1: "Create a worktree"), having two options where one is broken is worse than having one correct path.

### Research Insights

**Why removing Option A is safe:** AGENTS.md Hard Rule 1 already mandates worktrees for all work: "Never commit directly to main. Create a worktree." The `go.md` command routes to worktrees. The `one-shot` skill creates worktrees. Option A existed for non-bare repos that use Soleur -- but the worktree path works correctly in both bare and non-bare repos, making Option A redundant even in non-bare contexts.

### Change 2: Update one-shot SKILL.md Step 0b

Replace the "pull latest" instruction with worktree-manager.sh (the only bare-repo-safe branch creation method).

**File:** `plugins/soleur/skills/one-shot/SKILL.md` (line 14)

**Current:**
```markdown
**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), pull latest and create a feature branch named `feat/one-shot-<slugified-arguments>` before proceeding. Parallel agents on the same repo cause silent merge conflicts when both work on main.
```

**Proposed:**
```markdown
**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), create a worktree for the feature branch. Do NOT use `git pull` or `git checkout -b` -- both fail on bare repos (`core.bare=true`).

\`\`\`bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-one-shot-<slugified-arguments>
\`\`\`

Then `cd` into the worktree path. Parallel agents on the same repo cause silent merge conflicts when both work on main.
```

**Rationale:** The instruction "pull latest" is ambiguous and the LLM consistently interprets it as `git pull origin main`. The original plan proposed `git checkout -b ... origin/main` as a replacement, but live testing confirmed `git checkout -b` also fails from bare repo root. `git worktree add` (via worktree-manager.sh) is the only command that creates a branch from bare context.

### Research Insights

**Edge case: one-shot invoked from an existing worktree.** When one-shot runs from a worktree (not bare root), `git branch --show-current` won't return `main` (it returns the worktree's branch), so Step 0b is skipped entirely. The fix only affects the bare-root entry path, which is the failure scenario.

### Change 3: Add Constitution Rule (Prevention)

Add a rule to `knowledge-base/project/constitution.md` under `## Architecture > ### Never` to prevent `git pull` and `git checkout` in scripts/instructions that may run from bare repo context.

**File:** `knowledge-base/project/constitution.md`

**New rule in Architecture > Never section:**
```markdown
- Never use `git pull` or `git checkout` in skill instructions, agent prompts, or shell scripts -- this repo uses `core.bare=true` where both commands are unavailable (they require a working tree); use `git fetch origin <branch>` to update refs and `git worktree add` (via worktree-manager.sh) to create branches; within an existing worktree, `git merge origin/<branch>` is safe
```

### Research Insights

**Why include `git checkout`:** The original plan only banned `git pull`, but live testing on the bare repo root confirmed `git checkout -b` also returns `fatal: this operation must be run in a work tree`. The constitution rule must cover both commands to prevent the same class of error from being reintroduced via `git checkout`.

### Change 4: Update AGENTS.md Session-Start Instruction (Defense-in-Depth)

The current session-start instruction handles the "from worktree" case well but doesn't explicitly cover the "bare root, no worktree for this task" case. Add a bare-root fallback with explicit prohibition of working-tree commands.

**File:** `AGENTS.md` (line 31)

**Current:**
```markdown
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists, run `git worktree list` from the bare root to verify.
```

**Proposed:**
```markdown
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists for the current task, run `git worktree list` from the bare root, then create a worktree with `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create <name>` before doing any work. The repo root is a bare repository -- never run `git pull`, `git checkout`, or other working-tree commands from the bare root.
```

### Research Insights

**Why be explicit about `git checkout` too:** `git branch --show-current` returns `main` from the bare root. The LLM sees this, concludes it needs to create a feature branch, and its default instinct is `git checkout -b`. This is a strong LLM prior that requires explicit prohibition in the AGENTS.md instruction, not just implicit prohibition via "use worktree-manager.sh."

### Change 5: Audit campaign-calendar SKILL.md (Secondary)

**File:** `plugins/soleur/skills/campaign-calendar/SKILL.md` (line 110)

Contains `git pull --rebase origin main` in a CI push-retry block. This runs in CI context (not bare repo), so it's lower risk, but should be noted. If the campaign-calendar ever runs locally from the bare root, it would fail.

**Action:** No change needed now -- this is a CI-only code path. Document in the plan for awareness.

## Non-Goals

- Refactoring worktree-manager.sh (already hardened in previous PRs)
- Fixing other scripts that use `git rev-parse --show-toplevel` (tracked separately, see prior plan's "Other Scripts" section)
- Adding automated tests for bare repo scenarios (valuable but out of scope for this fix)

## Acceptance Criteria

- [x] `work` SKILL.md no longer contains `git pull` or `git checkout -b` -- uses `worktree-manager.sh create` instead (`plugins/soleur/skills/work/SKILL.md`)
- [x] `work` SKILL.md Option A is removed; the worktree path is the only branch creation method
- [x] `one-shot` SKILL.md Step 0b uses `worktree-manager.sh --yes create` instead of "pull latest" (`plugins/soleur/skills/one-shot/SKILL.md`)
- [x] Constitution has a "Never use git pull or git checkout" rule in Architecture > Never section (`knowledge-base/project/constitution.md`)
- [x] AGENTS.md session-start instruction includes bare-root fallback with explicit prohibition of `git pull` and `git checkout` (`AGENTS.md`)
- [x] No `git pull` instructions remain in any skill SKILL.md file except campaign-calendar CI-only path (verified by grep)
- [x] Existing `git fetch` usages in `merge-pr/SKILL.md` and `ship/SKILL.md` remain unchanged (they're already correct and run from worktree context)
- [x] `fix-issue` SKILL.md `git checkout -b` replaced with `worktree-manager.sh --yes create` (bonus fix not in original plan)

## Test Scenarios

- Given a session starting from the bare repo root with no active worktree, when the LLM follows work SKILL.md, then it runs `worktree-manager.sh --yes create <name>` (no `git pull` or `git checkout`)
- Given a session running one-shot from the bare repo root, when Step 0b executes, then it runs `worktree-manager.sh --yes create <name>` and `cd`s into the worktree
- Given a session starting from an active worktree, when the LLM follows work SKILL.md, then behavior is unchanged (already on a feature branch, worktree creation is skipped)
- Given a non-bare repo using Soleur, when the LLM follows work SKILL.md, then `worktree-manager.sh create` works correctly (it handles both bare and non-bare contexts via IS_BARE detection)

### Edge Cases

- **No network:** `git fetch` inside worktree-manager.sh fails gracefully (the `update_branch_ref` function has `|| true` fallback). The worktree is still created from the local main ref.
- **Detached HEAD in bare repo:** `git branch --show-current` returns empty string. Work SKILL.md should detect this as "not on a feature branch" and proceed to create a worktree.
- **Worktree already exists for the branch name:** `worktree-manager.sh` detects this and offers to switch instead -- no crash.
- **worktree-manager.sh is stale on disk (bare root):** The `sync_bare_files` function in `cleanup-merged` auto-updates it. If stale, the session-start `cleanup-merged` call refreshes it before the work skill runs.

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

Replace lines 103-121 (remove Option A/B structure, make worktree the single path):

```markdown
   **If on the default branch**, you MUST create a worktree before proceeding. Never edit files on the default branch -- parallel agents cause silent merge conflicts, and this repo uses `core.bare=true` where `git pull` and `git checkout` are unavailable.

   Create a worktree for the new feature:

   ```bash
   bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feature-branch-name
   ```

   Then `cd` into the worktree path printed by the script. The worktree manager handles bare-repo detection, branch creation from latest origin/main, .env copying, and dependency installation.

   Use a meaningful name based on the work (e.g., `feat-user-authentication`, `fix-email-validation`).
```

### plugins/soleur/skills/one-shot/SKILL.md

Replace line 14:

```markdown
**Step 0b: Ensure branch isolation.** Check the current branch with `git branch --show-current`. If on the default branch (main or master), create a worktree for the feature branch. Do NOT use `git pull` or `git checkout -b` -- both fail on bare repos (`core.bare=true`).

```bash
bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create feat-one-shot-<slugified-arguments>
```

Then `cd` into the worktree path printed by the script. Parallel agents on the same repo cause silent merge conflicts when both work on main.
```

### knowledge-base/project/constitution.md

Add to `## Architecture > ### Never` section:

```markdown
- Never use `git pull` or `git checkout` in skill instructions, agent prompts, or shell scripts -- this repo uses `core.bare=true` where both commands are unavailable (they require a working tree); use `git fetch origin <branch>` to update refs and `git worktree add` (via worktree-manager.sh) to create branches; within an existing worktree, `git merge origin/<branch>` is safe
```

### AGENTS.md

Update line 31 session-start instruction to add bare-root guidance:

```markdown
- At session start, from any active worktree (not the bare repo root): run `bash ../../plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh cleanup-merged && git worktree list`. If no worktree exists for the current task, run `git worktree list` from the bare root, then create a worktree with `bash ./plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh --yes create <name>` before doing any work. The repo root is a bare repository -- never run `git pull`, `git checkout`, or other working-tree commands from the bare root.
```

## References

- Prior plan: `knowledge-base/project/plans/2026-03-13-fix-bare-repo-worktree-manager-stale-files-plan.md`
- worktree-manager.sh: `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
- Constitution: `knowledge-base/project/constitution.md`
