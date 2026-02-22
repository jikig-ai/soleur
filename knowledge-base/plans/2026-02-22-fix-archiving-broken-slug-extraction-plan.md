---
title: "fix: Archiving broken due to slug extraction mismatch and incomplete cleanup"
type: fix
date: 2026-02-22
---

# fix: Archiving broken due to slug extraction mismatch and incomplete cleanup

## Enhancement Summary

**Deepened on:** 2026-02-22
**Sections enhanced:** 4 (Implementation Tasks 1-4)
**Research sources:** codebase analysis, institutional learnings, shell scripting patterns

### Key Improvements
1. Added precise line-by-line edit instructions for compound-capture SKILL.md
2. Added complete shell function for cleanup-merged brainstorm/plan archival with edge case handling
3. Identified additional consistency fix needed in branch detection prose (line 321 and 323)
4. Added `external/` directory exclusion note for one-time cleanup

### New Considerations Discovered
- The `compound-capture` code fence contains literal `${current_branch#feat-}` which violates the constitution's "No command substitution in .md files" rule -- the fix should use prose instructions instead
- The `external/` spec directory must be excluded from one-time cleanup (it contains reference docs, not feature specs)
- The `cleanup-merged` script uses `mv` not `git mv` for spec archival -- brainstorm/plan archival should match this convention (non-git-tracked archive moves)
- False-positive slug matching risk is low: no feature slugs in this repo are under 6 characters

## Problem Statement

Knowledge base archiving is not working properly for brainstorms, plans, and specs. The evidence:

- **13 active brainstorms** with no corresponding feature branch
- **38 active plans** with no corresponding feature branch
- **42 active spec directories** with no corresponding feature branch
- Only **2 feature branches** exist (one is this issue's branch)

Root causes identified:

### Root Cause 1: compound-capture slug extraction mismatch (Critical)

The `compound-capture` skill extracts the feature slug with:

```bash
slug="${current_branch#feat-}"
```

But AGENTS.md specifies branches use `feat/<name>` convention (with slash, e.g., `feat/fix-archiving`). The parameter expansion `${current_branch#feat-}` only strips the `feat-` prefix -- it does NOT strip `feat/`. This means:

- Branch `feat/domain-leaders` produces slug `feat/domain-leaders` instead of `domain-leaders`
- Glob patterns `*feat/domain-leaders*` match nothing in the filesystem
- Spec directory check `test -d knowledge-base/specs/feat-feat/domain-leaders` fails
- Result: compound silently skips consolidation ("no artifacts found")

The `ship` and `merge-pr` skills correctly document stripping `feat-`, `feature/`, `fix-`, `fix/` -- but `compound-capture` has the outdated single-prefix logic.

### Root Cause 2: cleanup-merged only archives specs, not brainstorms or plans

The `worktree-manager.sh cleanup-merged` function:

1. Correctly converts `feat/` to `feat-` using `tr '/' '-'`
2. Archives spec directories to `knowledge-base/specs/archive/`
3. Does NOT touch brainstorms or plans

This means even when cleanup-merged runs successfully, brainstorms and plans remain as active artifacts forever.

### Root Cause 3: No orphan detection for already-accumulated artifacts

There is no mechanism to retroactively archive artifacts whose feature branches have already been deleted. The 13+38+42 orphaned artifacts accumulated from prior sessions where compound's slug extraction silently failed, and cleanup-merged did not handle brainstorms/plans.

## Research Findings

### Relevant file paths

- `plugins/soleur/skills/compound-capture/SKILL.md:321` -- branch detection (only checks `feat-`)
- `plugins/soleur/skills/compound-capture/SKILL.md:323` -- prose reference to `feat-*` branches
- `plugins/soleur/skills/compound-capture/SKILL.md:330` -- broken slug extraction code fence
- `plugins/soleur/skills/compound/SKILL.md:198` -- references compound-capture's discovery logic
- `plugins/soleur/skills/ship/SKILL.md:47,226` -- correct prefix stripping (multiple prefixes)
- `plugins/soleur/skills/merge-pr/SKILL.md:90` -- correct prefix stripping (multiple prefixes)
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:382` -- correct `tr '/' '-'` but specs-only
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:403-413` -- spec archival block (insertion point for brainstorm/plan archival)
- `plugins/soleur/skills/brainstorm/SKILL.md:280` -- manual archive instructions
- `plugins/soleur/skills/plan/SKILL.md:392` -- manual archive instructions

### Related learnings

- `knowledge-base/learnings/2026-02-22-cleanup-merged-path-mismatch.md` -- documents the branch-name-to-path mismatch pattern; key insight: "Never construct filesystem paths from git ref names"
- `knowledge-base/learnings/2026-02-21-stale-worktrees-accumulate-across-sessions.md` -- the cleanup gap pattern; key insight: session boundaries are the most common point of workflow failure
- `knowledge-base/learnings/2026-02-09-worktree-cleanup-gap-after-merge.md` -- original identification of post-merge cleanup gap

### Existing archiving mechanisms

| Mechanism | Brainstorms | Plans | Specs | Trigger |
|-----------|:-----------:|:-----:|:-----:|---------|
| compound-capture auto-consolidation | BROKEN | BROKEN | BROKEN | feat-* branch + slug match |
| ship Phase 2 (compound gate) | BROKEN | BROKEN | BROKEN | Delegates to compound |
| ship Phase 7 (pre-push gate) | BROKEN | BROKEN | BROKEN | Delegates to compound |
| merge-pr Phase 1.3 | BROKEN | BROKEN | BROKEN | Delegates to compound |
| cleanup-merged | No | No | Yes | [gone] branches post-merge |
| Manual archive (brainstorm/plan skills) | Manual | Manual | N/A | User invokes instructions |

### Constitution constraint

The constitution states: "Never use shell variable expansion (`${VAR}`, `$VAR`, `$()`) in bash code blocks within skill, command, or agent .md files -- use angle-bracket prose placeholders (`<variable-name>`) with substitution instructions instead." The broken code fence at line 330 violates this rule. The fix must use prose instructions with `<slug>` placeholders, not literal bash parameter expansion.

## Implementation Plan

### Task 1: Fix compound-capture slug extraction (Critical)

**File:** `plugins/soleur/skills/compound-capture/SKILL.md`

**Change 1a -- Branch detection (line 321):**

Replace:
```text
Run `git branch --show-current` to get the current branch. If it does not start with `feat-`, skip consolidation entirely.
```

With:
```text
Run `git branch --show-current` to get the current branch. If it does not start with `feat-` or `feat/`, skip consolidation entirely.
```

**Change 1b -- Section heading prose (line 323):**

Replace:
```text
**If on a `feat-*` branch, run the following steps automatically:**
```

With:
```text
**If on a feature branch (`feat-*` or `feat/*`), run the following steps automatically:**
```

**Change 1c -- Slug extraction (lines 327-331):**

Replace the bash code fence:
```bash
slug="${current_branch#feat-}"
```

With prose instructions:
```text
Extract the slug from the current branch name by stripping the branch type prefix. Handle all prefix variants:
- `feat/` -> strip prefix (e.g., `feat/domain-leaders` -> `domain-leaders`)
- `feat-` -> strip prefix (e.g., `feat-domain-leaders` -> `domain-leaders`)
- `feature/` -> strip prefix (e.g., `feature/domain-leaders` -> `domain-leaders`)
- `fix/` -> strip prefix (e.g., `fix/typo` -> `typo`)
- `fix-` -> strip prefix (e.g., `fix-typo` -> `typo`)
```

### Research Insights for Task 1

**Best practice:** The ship and merge-pr skills already use the correct prose-based approach -- they say "strip `feat-`, `feature/`, `fix-`, `fix/` prefix" as natural language that the LLM interprets. This is more resilient than a bash code fence because:
1. It handles all variants without explicit bash parameter expansion
2. It complies with the constitution's "no shell variable expansion in .md" rule
3. It lets the LLM adapt to any future prefix convention

**Edge case -- `fix/` branches:** The compound-capture branch detection currently only checks for `feat-`. Branches starting with `fix/` or `fix-` also produce artifacts (plans, specs). The fix should expand detection to include these prefixes too. However, `fix/` branches may not always have brainstorms -- the discovery step already handles "no artifacts found" gracefully.

### Task 2: Extend cleanup-merged to archive brainstorms and plans

**File:** `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`

In `cleanup_merged_worktrees()`, after the spec archival block (line 413), add a function to archive brainstorms and plans. Insert the following logic:

```bash
    # Archive brainstorms and plans matching the feature slug
    local feature_slug="${safe_branch#feat-}"
    local brainstorm_dir="$GIT_ROOT/knowledge-base/brainstorms"
    local plan_dir="$GIT_ROOT/knowledge-base/plans"
    local timestamp
    timestamp="$(date +%Y-%m-%d-%H%M%S)"

    # Archive matching brainstorms
    if [[ -d "$brainstorm_dir" ]]; then
      local brainstorm_archive="$brainstorm_dir/archive"
      for f in "$brainstorm_dir"/*"$feature_slug"*; do
        if [[ -f "$f" && "$f" != */archive/* ]]; then
          mkdir -p "$brainstorm_archive"
          local fname
          fname=$(basename "$f")
          if ! mv "$f" "$brainstorm_archive/$timestamp-$fname" 2>/dev/null; then
            [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive brainstorm $fname${NC}"
          fi
        fi
      done
    fi

    # Archive matching plans
    if [[ -d "$plan_dir" ]]; then
      local plan_archive="$plan_dir/archive"
      for f in "$plan_dir"/*"$feature_slug"*; do
        if [[ -f "$f" && "$f" != */archive/* ]]; then
          mkdir -p "$plan_archive"
          local fname
          fname=$(basename "$f")
          if ! mv "$f" "$plan_archive/$timestamp-$fname" 2>/dev/null; then
            [[ "$verbose" == "true" ]] && echo -e "${YELLOW}Warning: Could not archive plan $fname${NC}"
          fi
        fi
      done
    fi
```

### Research Insights for Task 2

**Convention consistency:** The existing spec archival uses `mv` (not `git mv`) because the cleanup-merged script runs from the main repo root, and the archived files are not being committed as part of this operation -- they are being moved as a filesystem housekeeping step. The brainstorm/plan archival should follow the same convention.

**Glob safety:** The bash glob `"$brainstorm_dir"/*"$feature_slug"*` will expand to the literal string if no matches exist (default bash behavior). The `-f "$f"` check inside the loop handles this by skipping non-file results. Setting `shopt -s nullglob` would be cleaner but changes global shell state; the explicit check is safer.

**Timestamp consistency:** The existing spec archival uses `%Y-%m-%d-%H%M%S` format. The compound-capture uses `YYYYMMDD-HHMMSS` (no hyphens in date). The cleanup-merged convention should take precedence since it is the established pattern in the shell script.

**Insertion point:** The new code should go immediately after line 413 (the closing `fi` of the spec archival block) and before the worktree removal block (line 416). This ensures brainstorms and plans are archived in the same pass as specs.

### Task 3: One-time cleanup of orphaned artifacts

Archive the 93 orphaned artifacts using `git mv` to preserve history. This is a one-time operation executed manually, not a script change.

**Step 3a: Archive brainstorms (13 files)**

Generate a timestamp, then run `git mv` for each file:

```text
For each file in knowledge-base/brainstorms/*.md:
  git mv "knowledge-base/brainstorms/<filename>" "knowledge-base/brainstorms/archive/<timestamp>-<filename>"
```

**Step 3b: Archive plans (38 files)**

```text
For each file in knowledge-base/plans/*.md:
  git mv "knowledge-base/plans/<filename>" "knowledge-base/plans/archive/<timestamp>-<filename>"
```

**Step 3c: Archive spec directories (41 directories)**

Exclude `external/` and `feat-fix-archiving/` (the current feature):

```text
For each directory in knowledge-base/specs/feat-*/ (excluding feat-fix-archiving):
  git mv "knowledge-base/specs/<dirname>" "knowledge-base/specs/archive/<timestamp>-<dirname>"
```

**Step 3d: Commit**

Single atomic commit:

```text
git add -A knowledge-base/
git commit -m "fix: archive 93 orphaned KB artifacts from completed features"
```

### Research Insights for Task 3

**Exclusions:** Two directories in `knowledge-base/specs/` must NOT be archived:
- `external/` -- contains reference docs (claude-code.md, codex.md, opencode.md), not feature specs
- `feat-fix-archiving/` -- the active feature branch for this issue

**Commit atomicity:** The constitution requires "operations that modify the knowledge-base or move files must use `git mv` to preserve history and produce a single atomic commit that can be reverted with `git revert`." The one-time cleanup should be a single commit for clean revert.

**Historical note:** CHANGELOG entry `v2.13.0` mentions "Archived 5 stale KB artifacts (2 brainstorms, 2 plans, 1 spec directory) from agent-team and community-contributor-audit features." This confirms that manual archival has been done before and is an established pattern.

### Task 4: Update compound skill's discovery documentation

**File:** `plugins/soleur/skills/compound/SKILL.md`

Update line 198 from:

```text
1. **Discovers artifacts** -- globs `knowledge-base/{brainstorms,plans}/*<slug>*` and `knowledge-base/specs/feat-<slug>/` (excluding `*/archive/`)
```

To:

```text
1. **Discovers artifacts** -- extracts the feature slug by stripping `feat/`, `feat-`, `feature/`, `fix/`, or `fix-` prefix from the branch name, then globs `knowledge-base/{brainstorms,plans}/*<slug>*` and `knowledge-base/specs/feat-<slug>/` (excluding `*/archive/`)
```

### Research Insights for Task 4

**Documentation-implementation consistency:** The compound skill's description of the discovery logic must match the compound-capture implementation. Since compound routes to compound-capture (line 323: "Routes To: compound-capture skill"), keeping the summary in sync prevents confusion when maintaining either file.

## Acceptance Criteria

- [ ] `compound-capture` branch detection handles both `feat-` and `feat/` prefixes
- [ ] `compound-capture` slug extraction uses prose instructions (not bash code fence) covering `feat/`, `feat-`, `feature/`, `fix/`, `fix-`
- [ ] `cleanup-merged` archives brainstorms matching the feature slug
- [ ] `cleanup-merged` archives plans matching the feature slug
- [ ] All 93 orphaned artifacts are moved to their respective `archive/` directories via `git mv`
- [ ] `external/` and `feat-fix-archiving/` spec directories are NOT archived
- [ ] No active brainstorms, plans, or specs exist without a corresponding feature branch (except `external/`)
- [ ] compound skill documentation reflects the corrected slug extraction logic

## Test Scenarios

### Given a branch named feat/domain-leaders, when compound runs
- Then the slug extracted is `domain-leaders`
- And `knowledge-base/brainstorms/*domain-leaders*` files are discovered
- And `knowledge-base/plans/*domain-leaders*` files are discovered
- And `knowledge-base/specs/feat-domain-leaders/` is discovered

### Given a branch named feat-legacy-name (hyphenated), when compound runs
- Then the slug extracted is `legacy-name`
- And artifact discovery works the same as with slash convention

### Given a merged PR whose branch was feat/code-coverage, when cleanup-merged runs
- Then spec directory `knowledge-base/specs/feat-code-coverage/` is archived
- And brainstorms matching `*code-coverage*` are archived
- And plans matching `*code-coverage*` are archived

### Given orphaned artifacts with no feature branch, when one-time cleanup runs
- Then all active brainstorms are moved to `knowledge-base/brainstorms/archive/`
- And all active plans are moved to `knowledge-base/plans/archive/`
- And all active specs (except external/ and feat-fix-archiving/) are moved to `knowledge-base/specs/archive/`

## Non-Goals

- Changing the branch naming convention (feat/ vs feat-)
- Adding automated tests for archiving (manual verification is sufficient for markdown-only changes)
- Restructuring the archive directory layout
- Changing the timestamp format used in archive filenames
- Adding orphan detection as a recurring check (the bug fix prevents future orphans)

## Rollback Plan

All archival moves use `git mv`, so a single `git revert` restores the original state. For the slug extraction fix, reverting the compound-capture SKILL.md change restores the old behavior.

## Version Bump

PATCH bump -- this is a bug fix to existing archiving logic.
