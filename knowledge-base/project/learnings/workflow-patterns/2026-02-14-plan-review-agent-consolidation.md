---
module: soleur-plugin
date: 2026-02-14
problem_type: workflow-pattern
component: plan-review
tags: [plan-review, agent-design, simplification, ops-directory]
severity: info
---

# Plan Review Catches Agent Duplication

## Problem

Initial plan for ops directory proposed 3 separate agents (cost-tracker, domain-manager, hosting-advisor) and 3 data files (expenses.md, domains.md, hosting.md). All three agents performed identical operations: read/update a markdown table, summarize data, flag renewals.

## Solution

Running `/plan-review` with three parallel reviewers (DHH, Kieran, Simplicity) independently converged on the same simplification:

- 3 agents -> 1 agent (`ops-advisor.md`) that handles all ops data files based on prompt context
- 3 data files -> 2 data files (hosting merged into expenses.md as a Category value)
- ~40% reduction in surface area with 100% of Phase 1 value preserved

## Key Insight

When multiple agents perform the same operation type (read/update structured data) on different files, consolidate into one agent until automation introduces real behavioral divergence. The "split when it hurts" principle: one agent now, split when Phase 2 automation lands and agents need genuinely different capabilities. Also: hosting is just a recurring expense with metadata in the Notes column -- it does not justify its own entity until it has special behavior (API integration, cost optimization algorithms).

## Related

- Constitution: "plans consistently shrink by 30-50% after review"
- Constitution: "design for v2, implement for v1"
- `knowledge-base/plans/2026-02-14-feat-ops-directory-advisory-agents-plan.md`
