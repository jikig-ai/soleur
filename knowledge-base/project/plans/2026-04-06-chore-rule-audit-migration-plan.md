---
title: "chore: migrate 7 hook-enforced rules from AGENTS.md to constitution.md"
type: chore
date: 2026-04-06
issue: "#1316"
semver: patch
---

# Migrate Hook-Enforced Rules from AGENTS.md to Constitution.md

## Problem

Always-loaded rule count is 314 (63 AGENTS.md + 251 constitution.md), exceeding
the 300 threshold defined in #451. Seven AGENTS.md rules already have mechanical
enforcement via PreToolUse hooks (guardrails.sh, pre-merge-rebase.sh,
worktree-write-guard.sh), making their AGENTS.md copies redundant
defense-in-depth. Migrating them to constitution.md (where four already have
duplicates) reduces the AGENTS.md count and brings the total back under budget by
consolidating duplicates.

## Context

- **Issue:** #1316
- **Brainstorm:** `knowledge-base/project/brainstorms/2026-03-30-rule-audit-ci-brainstorm.md`
- **Audit script:** `scripts/rule-audit.sh` (generated the migration candidates)
- **Enforcement tier model:** Tier 1 (hooks) > Tier 2 (AGENTS.md) > Tier 3 (constitution.md)

## Migration Analysis

| # | AGENTS.md Line | Hook Enforcement | Constitution.md Status | Migration Action |
|---|----------------|-----------------|----------------------|-----------------|
| 1 | L7: Never commit directly to main | guardrails.sh Guard 1 | L170: DUPLICATE (already present) | Remove from AGENTS.md only |
| 2 | L8: Never --delete-branch with gh pr merge | guardrails.sh Guard 3 | None | Move to constitution.md Architecture > Never |
| 3 | L9: Never edit files in main repo when worktree active | worktree-write-guard.sh | L168: DUPLICATE (already present) | Remove from AGENTS.md only |
| 4 | L11: Never rm -rf on worktree paths | guardrails.sh Guard 2 | None | Move to constitution.md Architecture > Never |
| 5 | L14: Before merging, merge origin/main | pre-merge-rebase.sh | L149: DUPLICATE (already present) | Remove from AGENTS.md only |
| 6 | L15: gh issue create must include --milestone | guardrails.sh Guard 5 | L82: PARTIAL DUPLICATE (no hook tag) | Remove from AGENTS.md; add hook tag to constitution L82 |
| 7 | L18: PreToolUse hooks block summary | All hooks combined | N/A (summary of hooks) | Remove from AGENTS.md; no constitution equivalent needed |

## Budget Impact

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| AGENTS.md rules | 63 | 56 | -7 |
| constitution.md rules | 251 | 253 | +2 (net new migrations #2, #4) |
| **Total always-loaded** | **314** | **309** | **-5** |

Note: Total drops by 5, not 7, because 2 net-new rules are added to
constitution.md. The 4 duplicates and 1 summary rule are pure removals.
309 is still over 300. Additional migration candidates from non-hook-enforced
rules would be needed to reach 300 -- that is out of scope for this issue.

## Acceptance Criteria

- [ ] Seven identified rules removed from AGENTS.md Hard Rules section
- [ ] Two net-new rules added to constitution.md Architecture > Never section:
  - Never use `--delete-branch` with `gh pr merge` (with hook tag and rationale)
  - Never `rm -rf` on worktree paths (with hook tag and rationale)
- [ ] constitution.md L82 (--milestone rule) gains `[hook-enforced: guardrails.sh Guard 5]` annotation
- [ ] Hook script prose rule comments updated to reflect new locations (guardrails.sh header, pre-merge-rebase.sh header, worktree-write-guard.sh header)
- [ ] No behavioral change: all 7 rules remain enforced by their PreToolUse hooks
- [ ] `scripts/rule-audit.sh` output shows reduced AGENTS.md count (56)
- [ ] Markdown lint passes on both AGENTS.md and constitution.md

## Non-Goals

- Reaching exactly 300 or below (309 is the achievable target from hook-enforced migrations alone)
- Migrating non-hook-enforced rules (separate issue scope)
- Changing hook behavior or adding new hooks
- Restructuring constitution.md sections

## Phases

### Phase 1: Remove 7 Rules from AGENTS.md

**Files:** `AGENTS.md`

Remove these 7 bullet points from the Hard Rules section:

1. **L7:** `- Never commit directly to main [hook-enforced: guardrails.sh Guard 1]. Create a worktree...`
2. **L8:** `- Never --delete-branch with gh pr merge [hook-enforced: guardrails.sh Guard 3]. Use gh pr merge...`
3. **L9:** `- Never edit files in the main repo when a worktree is active [hook-enforced: worktree-write-guard.sh]. Run pwd...`
4. **L11:** `- Never rm -rf on the current directory, a worktree path, or the repo root [hook-enforced: guardrails.sh Guard 2].`
5. **L14:** `- Before merging any PR, merge origin/main into the feature branch [hook-enforced: pre-merge-rebase.sh]...`
6. **L15:** `- Every gh issue create must include --milestone [hook-enforced: guardrails.sh Guard 5]...`
7. **L18:** `- PreToolUse hooks block: commits on main, rm -rf on worktrees, --delete-branch with active worktrees...`

After removal, AGENTS.md Hard Rules should have 56 rules (currently 63 minus 7).

### Phase 2: Add 2 Net-New Rules to Constitution.md

**Files:** `knowledge-base/project/constitution.md`

Add to Architecture > Never section (after existing worktree/branch rules around L170-L181):

1. **--delete-branch rule:**

   ```
   - Never use `--delete-branch` with `gh pr merge` when worktrees exist [hook-enforced: guardrails.sh Guard 3] -- use `gh pr merge <number> --squash --auto` then poll with `gh pr view <number> --json state --jq .state` until MERGED, then run `cleanup-merged`; `--delete-branch` orphans active worktrees whose branches are deleted out from under them
   ```

2. **rm -rf rule:**

   ```
   - Never `rm -rf` on the current directory, a worktree path, or the repo root [hook-enforced: guardrails.sh Guard 2] -- use `git worktree remove` or `worktree-manager.sh cleanup-merged` instead; recursive force-delete on worktree paths destroys branch state irrecoverably
   ```

### Phase 3: Update Existing Constitution.md Rule with Hook Tag

**Files:** `knowledge-base/project/constitution.md`

Update L82 to add hook enforcement annotation:

**Before:**

```
- GitHub Actions workflows and shell scripts that create issues must include `--milestone` -- issues without milestones are invisible...
```

**After:**

```
- GitHub Actions workflows and shell scripts that create issues must include `--milestone` [hook-enforced: guardrails.sh Guard 5] -- issues without milestones are invisible...
```

### Phase 4: Update Hook Script Prose Comments

**Files:** `.claude/hooks/guardrails.sh`, `.claude/hooks/pre-merge-rebase.sh`, `.claude/hooks/worktree-write-guard.sh`

Update the "Corresponding prose rules" header comments to reflect that migrated rules now live only in constitution.md:

**guardrails.sh** (lines 9-14):

- Guard 1: Change `AGENTS.md "Never commit directly to main"` to just `constitution.md "Never allow agents to work directly on the default branch"`
- Guard 2: Change `AGENTS.md "Never rm -rf..."` to `constitution.md "Never rm -rf on the current directory, a worktree path, or the repo root"`
- Guard 3: Change `AGENTS.md "Never --delete-branch..."` to `constitution.md "Never use --delete-branch with gh pr merge when worktrees exist"`
- Guard 5: Change `AGENTS.md "Every gh issue create..."` to `constitution.md "GitHub Actions workflows and shell scripts that create issues must include --milestone"`
- Guard 6: Remains AGENTS.md (git stash rule was NOT migrated -- it stays in AGENTS.md)

**pre-merge-rebase.sh** (lines 15-17):

- Remove `AGENTS.md "Before merging any PR..."` reference
- Remove `AGENTS.md "gh pr merge without review evidence"` reference (the review evidence rule stays in AGENTS.md but the summary line L18 is being removed; the hook comment should reference the remaining constitution.md rule only)
- Keep `constitution.md "Before creating a PR or merging..."` reference

**worktree-write-guard.sh** (lines 7-8):

- Remove `AGENTS.md "Never edit files in the main repo when a worktree is active"` reference
- Keep `constitution.md "Never edit files in the main repo root when a worktree is active for the current feature"` reference

### Phase 5: Validate

1. Run `grep -c '^- ' AGENTS.md` -- expect 56
2. Run `grep -c '^- ' knowledge-base/project/constitution.md` -- expect 253
3. Run `bash scripts/rule-audit.sh` (if available locally) to verify budget report
4. Run `npx markdownlint-cli2 --fix AGENTS.md knowledge-base/project/constitution.md`
5. Verify hook scripts still reference correct prose rule locations

## Test Scenarios

- Given all 7 rules are removed from AGENTS.md, when counting `^-` lines, then AGENTS.md has 56 rules
- Given 2 net-new rules are added to constitution.md, when counting `^-` lines, then constitution.md has 253 rules
- Given the --delete-branch rule is migrated, when running `gh pr merge --delete-branch` with active worktrees, then guardrails.sh Guard 3 still blocks it (no behavioral change)
- Given the rm-rf rule is migrated, when running `rm -rf .worktrees/...`, then guardrails.sh Guard 2 still blocks it (no behavioral change)
- Given the --milestone rule gains a hook tag in constitution.md, when running `gh issue create` without --milestone, then guardrails.sh Guard 5 still blocks it (no behavioral change)
- Given L18 (summary) is removed, when the agent encounters PreToolUse hooks, then each individual hook still functions independently (the summary was informational only)
- Given the pre-merge-rebase rule is removed from AGENTS.md, when running `gh pr merge`, then pre-merge-rebase.sh still auto-syncs origin/main (no behavioral change)

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Remove all 7 from AGENTS.md, rely only on hooks | Maximum context reduction | Loses documentation for agents without hook context | Rejected -- constitution.md preserves the documentation |
| Keep all 7 in AGENTS.md as-is | No change risk | Stays over budget (314) | Rejected -- budget violation |
| Move to agent descriptions (Tier 4) instead | Lower context cost | Agent descriptions already near budget; rules not domain-specific | Rejected -- constitution.md is the correct tier |
| Also migrate non-hook-enforced rules | Could reach 300 | Larger scope, higher risk, different migration criteria | Deferred -- separate issue |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- infrastructure/tooling change affecting internal governance documents only.

## MVP

This is a single-PR change. All phases execute in one pass.

## Files Changed

| File | Change Type | Description |
|------|------------|-------------|
| `AGENTS.md` | Edit (remove 7 rules) | Remove 7 hook-enforced bullet points from Hard Rules |
| `knowledge-base/project/constitution.md` | Edit (add 2 rules, update 1) | Add --delete-branch and rm-rf rules; add hook tag to --milestone rule |
| `.claude/hooks/guardrails.sh` | Edit (comments only) | Update prose rule location references in header |
| `.claude/hooks/pre-merge-rebase.sh` | Edit (comments only) | Update prose rule location references in header |
| `.claude/hooks/worktree-write-guard.sh` | Edit (comments only) | Update prose rule location references in header |
