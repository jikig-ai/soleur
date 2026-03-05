---
title: feat: rule retirement - manual migration and compound budget check
type: feat
date: 2026-03-05
---

# Rule Retirement: Manual Migration + Compound Budget Check

[Updated 2026-03-05] Dramatically simplified after plan review. Three independent reviewers rejected the CI audit workflow as the same Layer 2 that was cut from #397. The correct v1 is a manual PR + a simple compound check.

## Overview

Two lightweight changes to reduce governance context cost and prevent rule duplication:

1. **Manual rule migration** -- Annotate 9 hook-superseded rules in constitution.md with `[hook-enforced]`, shorten corresponding AGENTS.md entries to cross-references, and add maintenance comments to hook scripts.
2. **Compound rule budget check** -- Add a 3-line count to compound Phase 1.5 that prints always-loaded rule totals and warns above 250. Also add one instruction to the Deviation Analyst about checking hooks before proposing new rules.

## Problem Statement / Motivation

Nine prose rules in AGENTS.md and constitution.md are already enforced by 6 PreToolUse hook guards across 3 scripts. These duplicate rules waste ~180 tokens per turn. Constitution.md (197 rules) + AGENTS.md (22 rules) = 219 always-loaded rules, costing 10-22% extra reasoning tokens per interaction.

## Non-Goals

- Scheduled CI workflow for automated detection (deferred -- premature at 3 hooks / 9 supersessions)
- Auto-generated PRs or issues from CI
- Session counting or cross-session violation tracking (Trigger B from original issue)
- Rule manifest/metadata file
- Parsing agent descriptions (Tier 4) or skill instructions (Tier 5)
- Automated rule deletion without human review

## Proposed Solution

### Part 1: Manual Rule Migration (one-time PR)

Edit 9 hook-superseded rules across two files:

**AGENTS.md changes** -- Shorten 5 rules to cross-references:

| Current Rule | Shortened To |
|---|---|
| Never commit directly to main. Create a worktree... | Never commit directly to main [enforced: guardrails.sh Guard 1]. Create a worktree... |
| Never `--delete-branch` with `gh pr merge`... | Never `--delete-branch` with `gh pr merge` [enforced: guardrails.sh Guard 3]... |
| Never edit files in the main repo when a worktree is active... | Never edit files in the main repo when a worktree is active [enforced: worktree-write-guard.sh]... |
| Never `rm -rf` on the current directory, a worktree path... | Never `rm -rf` on the current directory, a worktree path... [enforced: guardrails.sh Guard 2] |
| Before merging any PR, merge origin/main... | Before merging any PR, merge origin/main... [enforced: pre-merge-rebase.sh] |

**Constitution.md changes** -- Annotate 4 rules:

| Rule Location | Annotation Added |
|---|---|
| Architecture > Never: "Never allow agents to work directly on the default branch" | Append `[hook-enforced: guardrails.sh Guard 1]` |
| Architecture > Always: "grep staged content for conflict markers" | Append `[hook-enforced: guardrails.sh Guard 4]` |
| Architecture > Always: "Merge latest origin/main into the feature branch" | Append `[hook-enforced: pre-merge-rebase.sh]` |
| Architecture > Never: "Never edit files in the main repo root when a worktree is active" | Append `[hook-enforced: worktree-write-guard.sh]` |

**Hook script comments** -- Add maintenance comments to each hook:

```bash
# Corresponding prose rules:
#   AGENTS.md: "Never commit directly to main"
#   constitution.md: "Never allow agents to work directly on the default branch"
```

This replaces the hardcoded mapping table. 3 comments in 3 files is the mapping table.

### Part 2: Compound Rule Budget Check

**Not a new phase.** Add to the end of Phase 1.5 (Deviation Analyst) output:

```text
Rule budget: N always-loaded rules (constitution: X, AGENTS.md: Y)
```

If N > 250, append:

```text
[WARNING] Rule budget exceeded (N/250). Consider retiring hook-enforced rules.
```

**Add one instruction to Phase 1.5:** "Before proposing a new enforcement rule for constitution.md or AGENTS.md, check if an existing PreToolUse hook already covers it. If so, note 'already hook-enforced' and skip the proposal."

This prevents future duplication at the source without any new infrastructure.

### Part 3: Future Tracking Issue

File a GitHub issue: "Revisit automated rule audit if always-loaded rule count exceeds 300." This preserves the CI audit idea for when scale justifies it, without building the infrastructure now.

## Rollback Plan

All changes are to markdown files (AGENTS.md, constitution.md, compound SKILL.md) and shell comments. Revert the PR commit to undo everything. No data migrations, no infrastructure, no state to clean up.

## Acceptance Criteria

- [ ] 5 AGENTS.md rules annotated with `[enforced: ...]` cross-references
- [ ] 4 constitution.md rules annotated with `[hook-enforced: ...]`
- [ ] 3 hook scripts have corresponding prose rule comments
- [ ] Compound Phase 1.5 prints rule budget count after Deviation Analyst output
- [ ] Compound warns when always-loaded rules exceed 250
- [ ] Deviation Analyst checks for existing hooks before proposing new enforcement rules
- [ ] GitHub issue filed for "revisit automated audit at 300+ rules"

## Test Scenarios

- Given compound runs on current codebase (219 rules), then rule budget line shows "219 always-loaded rules" without warning
- Given a developer adds rules to reach 255, when compound runs, then it prints a warning
- Given Phase 1.5 detects a deviation already covered by a hook, when it proposes enforcement, then it notes "already hook-enforced" and skips

## References

- Brainstorm: `knowledge-base/brainstorms/2026-03-05-rule-retirement-brainstorm.md`
- Spec: `knowledge-base/specs/feat-rule-retirement/spec.md`
- Deviation Analyst scope reduction: `knowledge-base/learnings/2026-03-03-deviation-analyst-scope-reduction.md`
- Plan review feedback: DHH, Kieran, and Simplicity reviewers unanimously recommended cutting CI automation
- Related: #422, #397 / PR #416 (Deviation Analyst v1), PR #450
