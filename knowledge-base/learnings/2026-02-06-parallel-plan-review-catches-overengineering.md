---
module: soleur
date: 2026-02-06
problem_type: developer_experience
component: planning
tags: [plan-review, over-engineering, yagni, api-validation]
severity: medium
---

# Parallel Plan Reviews Catch Over-Engineering and Factual Errors

## Problem

Initial plan for fuzzy deduplication feature (#12) was over-engineered:
- Proposed Claude embeddings for semantic similarity (API doesn't exist)
- 65+ implementation tasks
- 3 new CLI flags
- New skill directory with TypeScript files
- Clustering algorithm (union-find)
- Merge UX with multiple options

## Root Cause

1. **Unchecked assumption**: "Claude API has an embed endpoint" - it doesn't
2. **No counterweight to complexity**: Without review, scope naturally expands
3. **Solving future problems**: Designed for v3 when v1 would suffice

## Solution

Run `/soleur:plan_review` with three specialized reviewers in parallel:

1. **DHH reviewer** - Catches architecture astronautics and over-engineering
2. **Kieran reviewer** - Catches factual/technical errors (API assumptions)
3. **Simplicity reviewer** - Applies YAGNI ruthlessly, cuts scope

All three converged on the same verdict: rewrite with 90% less complexity.

## Result

| Aspect | Original | After Review |
|--------|----------|--------------|
| Tasks | 65+ | 4 |
| New files | 3+ | 0 |
| CLI flags | 3 | 0 |
| Dependencies | Embeddings API | None |
| Lines added | ~300+ | ~50 |

Feature shipped in PR #23, fully functional.

## Key Insight

**Parallel specialized reviews are force multipliers.** A single reviewer sees some issues. Three reviewers with different perspectives (architecture, technical accuracy, simplicity) catch nearly everything. Same wall-clock time, dramatically better outcome.

## Prevention

Before implementing any plan with:
- New directories or file structures
- External API dependencies
- Multiple CLI flags
- Complex algorithms (clustering, caching)

Run `/soleur:plan_review` first. Cost: 5 minutes. Savings: hours of wasted implementation.

## Related

- [spec-workflow-implementation.md](./2026-02-06-spec-workflow-implementation.md) - "Architect for v2, implement for v1"
- [adding-new-plugin-commands.md](./implementation-patterns/adding-new-plugin-commands.md) - Plugin patterns
