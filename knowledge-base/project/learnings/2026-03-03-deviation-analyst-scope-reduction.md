---
title: "Deviation Analyst: multi-agent review reduced two-layer system to single-file edit"
date: 2026-03-03
category: process_improvement
tags: [compound_skill, scope_reduction, multi_agent_review, workflow_enforcement, plan_review]
---

# Learning: Deviation Analyst scope reduction via multi-agent review

## Problem

The original plan for self-healing workflow (#397) proposed a two-layer system:

- Layer 1: Deviation Analyst as parallel subagent #7 in compound (schema extension, proposals directory, hook staging)
- Layer 2: Weekly CI sweep with GitHub Actions workflow, auto-PRs, idempotency mechanism, rule retirement automation

This was 7+ files, 30 acceptance criteria, and 4 implementation phases.

## Solution

Three parallel plan reviewers (DHH, Code Simplicity, Architecture Strategist) all converged on the same conclusion: Layer 2 is premature, schema extension unnecessary, proposals directory over-complicated.

Applied their feedback:

- **Removed Layer 2 entirely** -- no CI sweep, no GitHub Actions workflow, no auto-PRs
- **Removed schema extension** -- existing `workflow_issue` problem type covers the use case
- **Removed proposals directory** -- hook proposals shown inline during Constitution Promotion
- **Changed from parallel to sequential** -- Phase 1.5 (sequential) avoids exceeding max-5 subagent limit
- **Removed rule retirement** -- manual retirement sufficient at current scale (3 hooks, 194 rules)

Result: ~60 lines added to 1 file (`compound/SKILL.md`). Everything else deferred to v2 with clear "Future Work" section.

## Key Insight

Plan review consistently reduces scope by 30-70%. This is the third time the pattern has appeared (see related learnings). The reduction follows a predictable shape: remove infrastructure that serves hypothetical future needs, keep the behavior change that delivers immediate value. "Design for v2, implement for v1" (constitution.md line 146) is the governing principle.

## Session Errors

1. **CWD drift at work skill start.** Shell was in main repo root instead of worktree when the work skill ran pre-flight checks. `git branch --show-current` returned `main`. Required manual navigation to `.worktrees/feat-self-healing-workflow/`. This is a recurring pattern -- the work skill should inherit the worktree context from the calling session, but shell state doesn't persist between tool calls.

## Tags

category: process_improvement
module: compound_skill
