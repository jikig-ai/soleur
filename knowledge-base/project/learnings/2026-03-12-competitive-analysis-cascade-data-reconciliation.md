---
category: integration-issues
module: competitive-intelligence
tags: [competitive-analysis, cascade-architecture, data-consistency]
date: 2026-03-12
---

# Learning: Competitive Analysis Cascade Data Reconciliation

## Problem

Adding Paperclip (<https://paperclip.ing/>) as a Tier 3 CaaS competitor exposed a cross-phase data inconsistency in the competitive analysis pipeline.

The pipeline runs through distinct phases: brainstorm, one-shot, plan+deepen, work, competitive-analysis scan, review, resolve-todos, compound. Two of these phases independently fetch live data from external sources (GitHub API, product pages). The plan phase fetched GitHub data showing 19.6k stars for Paperclip. The competitive-intelligence agent independently fetched the same data and found 14.6k stars. Neither phase is aware of the other's results.

This divergence propagated into the deliverables: `business-validation.md` (populated during plan) showed 19.6k stars, while all cascade outputs (competitive-intelligence.md, battlecards, pricing-strategy, content-strategy, seo-refresh-queue) used the agent's 14.6k figure. Review flagged this as a P1 inconsistency requiring reconciliation across 6+ files.

A secondary problem surfaced: the cascade architecture has a structural gap where the competitive-intelligence agent reads `business-validation.md` as input but never writes back to it. This means upstream data drifts from downstream reality over time. Pre-existing entries like Polsia ($50 vs $29-59 actual) and Lovable ($20M ARR vs $300M actual) were already stale in business-validation.md while downstream files carried current data.

Additionally, the session produced out-of-scope file modifications: `stop-hook.sh` had TTL logic deleted and a learnings file was modified despite this being a documentation-only PR. These required manual revert.

## Solution

1. **Data reconciliation**: Manually reconciled all 6+ files to use the competitive-intelligence agent's 14.6k figure, since the agent's fetch was more recent and its value was corroborated by the agent's own analysis context.

2. **Out-of-scope reverts**: Reverted stop-hook.sh and the spurious learnings modification to keep the PR scoped to competitive analysis documentation only.

3. **Upstream staleness**: Updated the stale business-validation.md entries (Polsia, Lovable, etc.) to match the cascade's current data as part of the reconciliation pass.

The structural gap remains unresolved: there is no 5th specialist in the cascade responsible for writing reconciled data back to business-validation.md.

## Key Insight

When a pipeline has multiple independent data-fetching phases (planning vs. execution), the later phase's data should govern because it is temporally closer to truth. However, governing alone is insufficient -- the later phase must also reconcile upstream documents, or the source of truth diverges from its derivatives.

The competitive analysis cascade needs either:

- A 5th specialist agent whose sole job is to reconcile business-validation.md with the cascade's output, or
- An explicit step in the competitive-intelligence agent prompt to update business-validation.md after completing its scan

This is a specific instance of a general multi-agent pattern: **read-only input files that are also sources of truth create drift**. If an agent reads a file as input and produces more accurate data, it must write back or the system accumulates contradictions.

## Session Errors

1. **Cross-phase data inconsistency**: Plan phase fetched 19.6k GitHub stars for Paperclip; competitive-intelligence agent fetched 14.6k stars. The divergence required manual reconciliation across 6+ files.
2. **Out-of-scope file modifications**: stop-hook.sh had TTL logic deleted and a learnings file was modified during a documentation-only PR. Required revert.
3. **Pre-existing upstream staleness**: business-validation.md entries for Polsia, Lovable, and others were outdated compared to cascade outputs, discovered only during reconciliation.

## Related Learnings

- [Competitive Intelligence Agent + Skill Implementation](./2026-02-27-competitive-intelligence-agent-implementation.md) -- Original agent+skill design, including the cascade architecture and agent/skill responsibility boundary
- [Multi-Agent Cascade Orchestration Checklist](./2026-03-02-multi-agent-cascade-orchestration-checklist.md) -- Cascade silent-failure modes (tool permissions, write targets, artifact verification); this learning adds data-consistency as a fourth failure mode
- [Business Validation Agent Pattern](./2026-02-22-business-validation-agent-pattern.md) -- How business-validation.md is structured as a point-in-time snapshot, which is the root cause of the upstream staleness problem

## Tags

category: integration-issues
module: competitive-intelligence
