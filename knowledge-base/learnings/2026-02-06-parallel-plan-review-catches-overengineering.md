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

## Second Case: Runtime Agent Discovery (#46) [Updated 2026-02-12]

Same pattern, same outcome. Plan for making review agents project-aware:

| Aspect | Original | After Review |
|--------|----------|--------------|
| Scope | 2 phases (local filtering + tessl.io integration) | 1 phase (conditional section edit) |
| New metadata | `frameworks` + `languages` on all 14 agents | None |
| New commands | `/soleur:discover` | None |
| New directories | `plugins/soleur/agents/community/` | None |
| Files modified | 14+ agent files + review.md + new command | 1 file (review.md) |

DHH's verdict: "You have 2 agents out of 10 that are Rails-specific. The plan proposes a metadata schema, a detection engine, a filtering pipeline, a community agent directory, a tessl.io integration, and a new command. This is solving a $2 problem with a $200 solution."

The fix: move 2 agents into the existing conditional section of review.md, using the same pattern already established for migration and test agents.

## Third Case: Brand Marketing Tools (#71) [Updated 2026-02-12]

Same pattern, third confirmation. Plan for brand vision and marketing tools:

| Aspect | Original | After Review |
|--------|----------|--------------|
| Phases | 5 | 2 |
| New agents | 2 (brand-architect + brand-voice-reviewer) | 1 (brand-architect) |
| New skills | 2 (discord-content + github-presence) | 1 (discord-content) |
| Total components | 4 | 2 |

All three reviewers converged again:
- **DHH**: "brand-voice-reviewer is premature -- inline it. github-presence conflates two unrelated things."
- **Kieran**: "Brand guide parsing contract underspecified. Skill-to-agent invocation unresolved."
- **Simplicity**: "Cut reviewer (inline instead), defer github-presence, slim brand guide to 3 sections. ~50% scope reduction."

Key cut: brand voice validation moved from a separate agent to an inline step within the discord-content skill. Simpler, no cross-component invocation needed.

## Key Insight

**Parallel specialized reviews are force multipliers.** A single reviewer sees some issues. Three reviewers with different perspectives (architecture, technical accuracy, simplicity) catch nearly everything. Same wall-clock time, dramatically better outcome.

This pattern has now been confirmed across 3 features (#12, #46, #71). Every time the plan shrunk by 50-90% after review.

## Prevention

Before implementing any plan with:
- New directories or file structures
- External API dependencies
- Multiple CLI flags
- Complex algorithms (clustering, caching)
- New metadata schemas or configuration systems

Run `/soleur:plan_review` first. Cost: 5 minutes. Savings: hours of wasted implementation.

## Related

- [spec-workflow-implementation.md](./2026-02-06-spec-workflow-implementation.md) - "Architect for v2, implement for v1"
- [adding-new-plugin-commands.md](./implementation-patterns/adding-new-plugin-commands.md) - Plugin patterns
