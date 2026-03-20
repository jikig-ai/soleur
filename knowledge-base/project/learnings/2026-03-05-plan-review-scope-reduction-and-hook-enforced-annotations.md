---
title: "Plan review as scope reduction tool + hook-enforced annotation pattern for rule retirement"
date: 2026-03-05
category: process_improvement
tags: [plan_review, scope_reduction, hook_enforcement, rule_retirement, defense_in_depth, compound_skill]
---

# Learning: Plan review as scope reduction tool + hook-enforced annotation pattern for rule retirement

## Problem

The original plan for rule retirement automation proposed a CI audit workflow:
- GitHub Actions scheduled workflow scanning for prose/hook duplication
- Auto-generated PRs to retire superseded rules
- Rule staleness tracking with supersession metadata
- Approximately 395 LOC across multiple files

This was Layer 2 infrastructure for a system with 3 PreToolUse hooks and 9 known supersessions -- a scale that does not justify automated retirement pipelines.

## Solution

Three parallel plan reviewers (DHH, Kieran, Simplicity) unanimously rejected the CI audit workflow as premature Layer 2 infrastructure at current scale. This reduced implementation from ~395 LOC to ~15 LOC -- a 96% reduction. The correct v1 had two parts:

1. **`[hook-enforced: ...]` annotation convention.** When a PreToolUse hook enforces a prose rule, annotate the prose rule with `[hook-enforced: script.sh Guard N]` rather than deleting it. This preserves defense-in-depth documentation (the prose rule still trains agents that lack hook access) while making the duplication visible for future retirement decisions. The annotation is grep-able: `grep -c 'hook-enforced'` gives an instant count.

2. **Compound budget check in Phase 1.5.** Adding a rule-count + hook-duplication check to the Deviation Analyst prevents future duplication at the source -- when new rules are being proposed during compound review. If a proposed rule duplicates an existing hook, the analyst flags it before it enters the constitution.

## Key Insight

Plan review consistently reduces scope by 50-96%. This is now the fourth documented instance of the pattern (see related learnings below). The shape is always the same: remove infrastructure that serves hypothetical future scale, keep the behavior change that delivers immediate value. At current scale (3 hooks, ~200 rules), manual annotation with a grep-able convention outperforms any automated pipeline. The convention itself creates the migration path -- when `grep -c 'hook-enforced'` crosses a pain threshold, that is the signal to build automation, not before.

The `[hook-enforced: ...]` pattern also solves a recurring tension in defense-in-depth systems: you want both the prose instruction (for agents without hook access) and the hook (for enforcement), but you need to track the duplication so it does not grow unbounded. The annotation makes the duplication intentional and visible rather than accidental and hidden.

## Session Errors

1. **Edit tool string mismatch on constitution.md line 124.** The initial match string missed the phrase "for the current feature" in the rule text. Fixed by re-reading the exact line range before retrying the edit. This is a recurring pattern -- always re-read the precise lines before constructing an Edit match string, especially after context compaction.

## Related

- [2026-02-06-parallel-plan-review-catches-overengineering.md](./2026-02-06-parallel-plan-review-catches-overengineering.md) -- First three cases (90% reduction)
- [2026-02-22-plan-review-collapses-agent-architecture.md](./2026-02-22-plan-review-collapses-agent-architecture.md) -- Agent architecture to inline instructions
- [2026-03-03-deviation-analyst-scope-reduction.md](./2026-03-03-deviation-analyst-scope-reduction.md) -- Two-layer system to single-file edit

## Tags
category: process_improvement
module: compound_skill
