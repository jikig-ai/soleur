---
title: "chore: add workflow constraint rules and DO NOT guards to CLAUDE.md"
type: chore
date: 2026-03-03
issue: "#389"
version_bump: none
deepened: 2026-03-03
---

# chore: Add Workflow Constraint Rules and DO NOT Guards to CLAUDE.md

## Enhancement Summary

**Deepened on:** 2026-03-03
**Sections enhanced:** 4 (Rule Wording, Constitution Additions, Test Scenarios, Edge Cases)
**Research sources:** ETH Zurich AGENTS.md study, HumanLayer CLAUDE.md guide, DEV Community adaptive patterns, 8 project learnings

### Key Improvements

1. Rule phrasing tightened using RFC 2119 keywords (MUST/NEVER) based on research showing "MUST use X" is followed reliably while "Prefer X" is treated as optional
2. Added edge case for rebase rule: interactive rebase (`-i`) is unsupported by Claude Code's Bash tool -- rule must specify non-interactive rebase only
3. Added compaction-specific guidance: the read-before-edit rule must survive context compaction since it is the rule most likely to be violated *after* compaction erases prior reads
4. Hook awareness rule refined with maintenance cost note -- update AGENTS.md whenever a new guard is added to hooks

### New Considerations Discovered

- AGENTS.md instruction budget is constrained: ~150-200 instructions total capacity, ~50 already consumed by Claude Code system prompt. Current 29 lines + 3 additions = 32 lines is well within budget.
- Rules that provide an alternative action are followed more reliably than bare prohibitions. All three new rules already include alternatives.
- Context compaction erases AGENTS.md instruction-following context; rules that prevent compaction-triggered failures (like read-before-edit) are the highest-leverage additions.

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
- Before merging any PR, rebase against latest origin/main (`git fetch origin main && git rebase origin/main`). Parallel PRs cause version conflicts -- handle version bumps during rebase proactively.
```

Rationale: constitution.md line 60 covers "fetch before version bumps" but does not mandate a full rebase before merge. The `learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` documents this exact friction. This rule makes it a hard rule.

#### Research Insights: Rebase Rule

**Edge cases:**
- Claude Code's Bash tool does not support interactive mode (`-i` flag). The rule must use non-interactive `git rebase origin/main`, never `git rebase -i`. This is already correctly specified in the rule wording.
- If rebase produces conflicts in version files (`plugin.json`, `CHANGELOG.md`), the agent should resolve by accepting theirs (latest main) and re-applying the version bump on top. The learning `2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` documents this pattern.
- The `cleanup-merged` script already runs `git pull --ff-only origin main` after cleaning worktrees (per `2026-02-24-pull-latest-main-after-cleanup-merged.md`), so session-start gets the latest main automatically. The rebase rule covers the gap between session-start and merge time when parallel PRs land.

**Rule phrasing:**
- Research confirms definitive language ("Before merging any PR, rebase...") is followed more reliably than suggestive ("Consider rebasing before merge"). The current wording is correct.
- The rule provides an alternative action (the explicit git commands), which research shows improves compliance vs. bare prohibitions.

**Rule: Read before edit (new)**

```text
- Always read a file before editing it. The Edit tool rejects unread files, but context compaction erases prior reads -- re-read after any compaction event.
```

Rationale: 7+ learnings document this failure mode. The Edit tool's built-in guard catches it, but each rejection wastes a turn and creates friction. Making it explicit in AGENTS.md prevents the attempt.

#### Research Insights: Read-Before-Edit Rule

**Compaction interaction:**
- This rule is the one most likely to be violated *after* context compaction, because compaction erases the evidence that a file was previously read. The rule explicitly calls out "re-read after any compaction event" which is the critical clause.
- The `2026-02-24-bsl-license-migration-pattern.md` learning documents 3 separate Write/Edit rejections in a single session caused by context compaction erasing prior reads. The `2026-02-22-domain-prerequisites-refactor-table-driven-routing.md` learning documents 5 such rejections.
- Research from HumanLayer confirms that "as instruction count increases, instruction-following quality decreases uniformly." This rule is high-leverage because it prevents a failure mode that wastes 1-2 turns per occurrence, and occurs in nearly every long session.

**Documented occurrences across learnings:**
1. `2026-02-24-bsl-license-migration-pattern.md` -- 3 rejections (LICENSE, legal docs)
2. `2026-02-27-feature-video-graceful-degradation.md` -- README.md and bug_report.yml
3. `2026-03-02-multi-agent-cascade-orchestration-checklist.md` -- plugin.json
4. `2026-03-02-skill-handoff-blocks-pipeline-when-announcing.md` -- 6 files
5. `2026-02-22-domain-prerequisites-refactor-table-driven-routing.md` -- 5 files
6. `2026-02-21-gdpr-article-30-email-provider-documentation.md` -- 1 file
7. `2026-02-26-cla-system-implementation-and-gdpr-compliance.md` -- Eleventy privacy-policy.md

**Rule: Hook awareness (new)**

```text
- PreToolUse hooks enforce: no commits on main (Guard 1), no rm -rf on worktrees (Guard 2), no --delete-branch with active worktrees (Guard 3), no writes to main repo when worktrees exist (Guard 4). Use `git worktree remove` and `worktree-manager.sh cleanup-merged` instead of fighting these guards.
```

Rationale: Agents sometimes try alternative commands to accomplish blocked operations. Listing what the hooks enforce prevents wasted turns trying workarounds.

#### Research Insights: Hook Awareness Rule

**Maintenance cost:**
- This rule creates a second place to update when a new guard is added (guardrails.sh + AGENTS.md). The guard error messages already explain what was blocked and suggest alternatives.
- Justification for the redundancy: the 61 friction events include cases where agents attempted workarounds after receiving hook error messages. The rule preemptively informs the agent about all guards, preventing the initial blocked attempt entirely.
- Mitigation: add a comment in `guardrails.sh` and `worktree-write-guard.sh` reminding maintainers to update AGENTS.md when adding new guards.

**Rule structure:**
- Lists all 4 guards in a single line with Guard numbers (1-4) for cross-reference to the hook source code.
- Provides the two primary alternative commands (`git worktree remove`, `worktree-manager.sh cleanup-merged`) so the agent knows what to do instead.

### Phase 2: Constitution.md Additions

Add to `## Architecture > ### Always`:

```text
- Before creating a PR or merging, rebase feature branch on latest origin/main (`git fetch origin main && git rebase origin/main`) -- parallel feature branches that bump versions without rebasing cause merge conflicts that require manual resolution
```

Add to `## Architecture > ### Never`:

```text
- Never attempt to edit a file that has not been read in the current conversation context -- the Edit tool will reject it, and context compaction erases prior reads; re-read after compaction
```

#### Research Insights: Constitution vs AGENTS.md Separation

**The two-tier rule system:**
- **AGENTS.md** (gotchas-only, ~30 lines): Loaded into the system prompt on every turn. Contains only rules the agent would violate without being told. Per ETH Zurich research, context files increase reasoning tokens by 10-22% and cost by 15-20% per interaction -- every line must earn its place.
- **constitution.md** (~250 lines): Loaded on-demand when specific skills request it (plan, work, compound). Contains the full convention set with rationale.

**Duplication principle:**
- The AGENTS.md versions are terse one-liners (gotcha form).
- The constitution.md versions include the full rationale and the specific git commands.
- This is intentional duplication: the AGENTS.md version prevents the violation; the constitution.md version explains why.

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
- Given context compaction occurs mid-session, when the agent needs to edit a previously-read file, then the agent should re-read the file before calling Edit (the compaction clause in the rule triggers re-read behavior).
- Given a rebase produces conflicts in `plugin.json` or `CHANGELOG.md`, when the agent resolves conflicts, then it should accept the main version and re-apply its version bump on top (not the reverse).

## Context

### Files to Modify

- `AGENTS.md` -- Add 3 new hard rules (~1 line each)
- `knowledge-base/overview/constitution.md` -- Add 2 new conventions (1 Always, 1 Never)

### Relevant Learnings

- `knowledge-base/learnings/2026-02-10-parallel-feature-version-conflicts-and-flag-lifecycle.md` -- Documents version conflict friction from parallel PRs
- `knowledge-base/learnings/2026-02-26-worktree-enforcement-pretooluse-hook.md` -- Documents the 4-guard progression
- `knowledge-base/learnings/2026-02-24-guardrails-chained-commit-bypass.md` -- Guard 1 bypass and fix
- `knowledge-base/learnings/2026-02-24-guardrails-grep-false-positive-worktree-text.md` -- Guard 2 false positive and fix
- `knowledge-base/learnings/2026-02-25-lean-agents-md-gotchas-only.md` -- Lean AGENTS.md principle (keep under 40 lines)
- `knowledge-base/learnings/2026-02-12-review-compound-before-commit-workflow.md` -- Compound before commit gate
- `knowledge-base/learnings/2026-02-24-bsl-license-migration-pattern.md` -- 3 Edit rejections from compaction-erased reads
- `knowledge-base/learnings/2026-02-22-context-compaction-command-optimization.md` -- Compaction frequency reduction strategy
- `knowledge-base/learnings/2026-02-24-pull-latest-main-after-cleanup-merged.md` -- cleanup-merged already pulls latest main
- `knowledge-base/learnings/2026-02-17-worktree-not-enforced-for-new-work.md` -- Dead rule pattern (rule exists but never triggers)
- `knowledge-base/learnings/2026-02-22-worktree-loss-stash-merge-pop.md` -- Catastrophic stash loss in worktrees

### Related Issues

- #389 (this issue)

### Source

Claude Code Insights report -- 2026-02-02 to 2026-03-03, 226 sessions, 61 wrong_approach events.

## References

- [AGENTS.md](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/AGENTS.md)
- [constitution.md](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/knowledge-base/overview/constitution.md)
- [guardrails.sh](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/.claude/hooks/guardrails.sh)
- [worktree-write-guard.sh](/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-claude-md-constraints/.claude/hooks/worktree-write-guard.sh)

### External References

- [HumanLayer: Writing a good CLAUDE.md](https://www.humanlayer.dev/blog/writing-a-good-claude-md) -- Instruction budget (~150-200), progressive disclosure, "never send an LLM to do a linter's job"
- [DEV Community: CLAUDE.md best practices](https://dev.to/cleverhoods/claudemd-best-practices-from-basic-to-adaptive-9lm) -- RFC 2119 keywords, path-scoped rules, adaptive maintenance
- ETH Zurich: "Evaluating AGENTS.md" (arxiv.org/abs/2602.11988) -- 10-22% reasoning token increase from context files
