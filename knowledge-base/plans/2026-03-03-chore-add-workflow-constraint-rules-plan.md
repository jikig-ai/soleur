---
title: "chore: add workflow constraint rules and DO NOT guards to CLAUDE.md"
type: chore
date: 2026-03-03
issue: "#389"
version_bump: PATCH
---

# chore: Add Workflow Constraint Rules and DO NOT Guards to CLAUDE.md

## Overview

Insights analysis across 226 sessions identified 61 "wrong_approach" friction events -- nearly 3x more than any other friction category. Most stem from Claude ignoring conventions that are documented in constitution.md or learnings but not enforced as hard rules in AGENTS.md or via PreToolUse hooks. This plan adds the missing constraint rules to AGENTS.md and, where possible, backs them with hook-based enforcement.

## Problem Statement / Motivation

The project already has a strong guardrails architecture (4 PreToolUse hook guards, a lean AGENTS.md with gotchas-only principle). But the insights report identified 6 specific gaps where the agent still deviates. Three are already partially covered; three are genuinely missing.

### Gap Analysis: Issue Recommendations vs Current Coverage

| # | Recommendation | Already In AGENTS.md? | Already In constitution.md? | Hook Enforced? | Action Needed |
|---|---------------|----------------------|---------------------------|----------------|--------------|
| 1 | Always use git worktrees for feature work | Yes (line 7) | Yes (lines 106-108) | Yes (worktree-write-guard.sh + Guard 1) | **No action** -- already a hard rule with hook enforcement |
| 2 | Pull and rebase against latest main before merging | No | Partially (line 60: fetch before version bumps) | No | **Add to AGENTS.md** as hard rule |
| 3 | Always read a file before editing it | No | No (documented in 7+ learnings) | **Built-in** (Edit tool rejects unread files) | **Add to AGENTS.md** as hard rule -- the tool enforces it but agents waste turns hitting the error |
| 4 | Run compound after completing primary task | Yes (line 18) | Yes (line 72) | No | **No action** -- already a hard rule. Could strengthen wording. |
| 5 | Guardrails hooks block rm -rf and branch deletion | No explicit awareness rule | Yes (lines 106-108, 115) | Yes (Guards 2, 3) | **Add awareness note** to AGENTS.md so agent doesn't fight the hooks |
| 6 | Explicit DO NOT rules | Partially (5 "Never" bullets) | Yes (large "Never" sections) | Partially | **Add missing DO NOTs** that emerge from gap analysis |

## Proposed Solution

### Phase 1: AGENTS.md Hard Rule Additions

Add these rules to the `## Hard Rules` section in `AGENTS.md`:

**Rule: Rebase before merge (new)**

```text
- Before merging any PR, pull and rebase against latest main. Parallel PRs cause version conflicts -- handle version bumps during rebase proactively.
```

Rationale: constitution.md line 60 covers "fetch before version bumps" but does not mandate a full rebase before merge. The `learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` documents this exact friction. This rule makes it a hard rule.

**Rule: Read before edit (new)**

```text
- Always read a file before editing it. The Edit tool rejects unread files, but context compaction erases prior reads -- re-read after any compaction event.
```

Rationale: 7+ learnings document this failure mode. The Edit tool's built-in guard catches it, but each rejection wastes a turn and creates friction. Making it explicit in AGENTS.md prevents the attempt.

**Rule: Hook awareness (new)**

```text
- PreToolUse hooks enforce: no commits on main (Guard 1), no rm -rf on worktrees (Guard 2), no --delete-branch with active worktrees (Guard 3), no writes to main repo when worktrees exist (Guard 4). Use `git worktree remove` and `worktree-manager.sh cleanup-merged` instead of fighting these guards.
```

Rationale: Agents sometimes try alternative commands to accomplish blocked operations. Listing what the hooks enforce prevents wasted turns trying workarounds.

### Phase 2: Constitution.md Additions

Add to `## Architecture > ### Always`:

```text
- Before creating a PR or merging, rebase feature branch on latest origin/main (`git fetch origin main && git rebase origin/main`) -- parallel feature branches that bump versions without rebasing cause merge conflicts that require manual resolution
```

Add to `## Architecture > ### Never`:

```text
- Never attempt to edit a file that has not been read in the current conversation context -- the Edit tool will reject it, and context compaction erases prior reads; re-read after compaction
```

### Phase 3: Consolidation of Existing Rules

Review current AGENTS.md hard rules for any that can be tightened:

- Line 18 (compound before commit): Already clear. No change needed.
- Line 7 (never commit to main): Already enforced by Guard 1. No change needed.
- Line 9 (never edit main repo files): Already enforced by Guard 4. Add cross-reference to hook awareness rule.

### Non-Goals

- No new PreToolUse hooks. The existing 4 guards cover the enforceable cases. The new rules (rebase before merge, read before edit) are workflow discipline rules that cannot be reliably detected by command-string grep.
- No changes to lefthook pre-commit hooks. These are code-quality gates (lint, test), not agent-discipline guards.
- No changes to `.claude/settings.json` beyond what already exists.
- No plugin version bump -- AGENTS.md and constitution.md are repo-level files, not plugin files.

## Acceptance Criteria

- [ ] AGENTS.md `## Hard Rules` section includes rebase-before-merge rule
- [ ] AGENTS.md `## Hard Rules` section includes read-before-edit rule
- [ ] AGENTS.md `## Hard Rules` section includes hook awareness rule listing all 4 guards
- [ ] constitution.md `## Architecture > ### Always` includes rebase-before-PR rule
- [ ] constitution.md `## Architecture > ### Never` includes never-edit-without-read rule
- [ ] No duplicate rules between AGENTS.md and constitution.md (AGENTS.md = gotchas-only, constitution.md = full conventions)
- [ ] AGENTS.md stays under 40 lines (currently 29 lines; adding 3 rules = ~32 lines, well within the lean principle)
- [ ] All existing PreToolUse hook tests still pass (`bun test`)

## Test Scenarios

- Given a fresh session with the updated AGENTS.md, when the agent attempts to edit a file without reading it first, then the agent should read the file before calling the Edit tool (no wasted rejection turns).
- Given a feature branch with version bumps, when the agent prepares to merge via `gh pr merge`, then the agent should first run `git fetch origin main && git rebase origin/main` and resolve any conflicts.
- Given the agent encounters a blocked PreToolUse hook (Guard 1-4), when it reads the hook awareness rule, then it should use the documented alternative (`git worktree remove`, `worktree-manager.sh cleanup-merged`) instead of attempting workarounds.
- Given the updated constitution.md, when a new learning about file editing is discovered, then the constitution.md already covers the principle (no duplicate entry needed).

## Context

### Files to Modify

- `AGENTS.md` -- Add 3 new hard rules (~3 lines each)
- `knowledge-base/overview/constitution.md` -- Add 2 new conventions (1 Always, 1 Never)

### Relevant Learnings

- `knowledge-base/learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` -- Documents version conflict friction from parallel PRs
- `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md` -- Documents the 4-guard progression
- `knowledge-base/learnings/2026-02-24-guardrails-chained-commit-bypass.md` -- Guard 1 bypass and fix
- `knowledge-base/learnings/2026-02-24-guardrails-grep-false-positive-worktree-text.md` -- Guard 2 false positive and fix
- `knowledge-base/learnings/2026-02-25-lean-agents-md-gotchas-only.md` -- Lean AGENTS.md principle (keep under 40 lines)
- `knowledge-base/learnings/2026-02-12-review-compound-before-commit-workflow.md` -- Compound before commit gate

### Related Issues

- #389 (this issue)

### Source

Claude Code Insights report -- 2026-02-02 to 2026-03-03, 226 sessions, 61 wrong_approach events.

## References

- [AGENTS.md](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/AGENTS.md)
- [constitution.md](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/knowledge-base/overview/constitution.md)
- [guardrails.sh](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/.claude/hooks/guardrails.sh)
- [worktree-write-guard.sh](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/.claude/hooks/worktree-write-guard.sh)
