# Marketing Strategy Review Brainstorm

**Date:** 2026-03-03
**Issue:** #236
**Status:** Decided — ready for execution

## What We're Building

A unified marketing strategy document for Soleur, replacing the fragmented collection of audits, plans, and reports that currently exist. Alongside this, regenerating and committing the 7 cascade documents that were generated during competitive intelligence analysis but never landed on main.

### Context

The last comprehensive marketing audit was Feb 19, 2026 (content audit + content plan). Since then:
- Product grew from 32 to 61 agents and 41 to 55 skills
- Anthropic launched Cowork Plugins (first-party competition)
- Competitive landscape shifted significantly
- Zero content from the 15-piece content plan was executed
- Blog infrastructure was never built
- SEO content score remains 2/10, AEO score 1.6/10

### Root Cause of Stalled Execution

A mix of **capacity constraints** (competing priorities consumed all bandwidth) and **strategic shift** (market changed with Cowork Plugins, making parts of the original strategy outdated).

## Why This Approach

**CMO-led orchestration** was chosen over manual assembly because:
- The CMO agent can delegate to specialists (growth-strategist, pricing-strategist, programmatic-seo-specialist, deal-architect) in parallel
- Specialists regenerate cascade docs aligned with the unified strategy
- CMO ensures cross-domain consistency across all artifacts
- Existing brand guide, competitive intelligence, and content audit provide a strong foundation

## Key Decisions

1. **Update strategy, not resume old plan** — The Feb 19 content plan isn't wrong, but needs to be reassessed given Cowork Plugins, doubled component count, and capacity realities
2. **Full scope** — Unified strategy doc + regenerate all 7 lost cascade documents (content-strategy.md, pricing-strategy.md, 4 battlecards, SEO refresh queue)
3. **CMO orchestration** — Domain leader runs assess → recommend → delegate cycle with specialist agents
4. **Three validated moats inform positioning** — Compounding knowledge base, cross-domain coherence, workflow orchestration depth (per Cowork Plugins risk analysis)
5. **Capacity-aware** — New strategy must be realistic for limited bandwidth, not a 15-piece content calendar that never ships

## Existing Artifacts to Incorporate

| Artifact | Path | Status |
|----------|------|--------|
| Brand guide | `knowledge-base/overview/brand-guide.md` | Current (reviewed 2026-03-02) |
| Business validation | `knowledge-base/overview/business-validation.md` | Current (PIVOT verdict) |
| Competitive intelligence | `knowledge-base/overview/competitive-intelligence.md` | Current (2026-03-02) |
| Content plan | `knowledge-base/audits/soleur-ai/2026-02-19-content-plan.md` | Stale, 0% executed |
| Content audit | `knowledge-base/audits/soleur-ai/2026-02-19-content-audit.md` | Stale, 0% applied |
| AEO audit | `knowledge-base/audits/soleur-ai/2026-02-19-aeo-audit.md` | Stale, 1.6/10 score |
| Cowork Plugins risk | `knowledge-base/learnings/2026-02-25-platform-risk-cowork-plugins.md` | Critical input |
| marketingskills overlap | `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md` | Quarterly review May 2026 |

## Open Questions

- Should the vision page be rewritten to align with brand guide, or removed?
- What is the primary conversion goal: installs, Discord signups, GitHub stars?
- Is "Company-as-a-Service" or "agentic company" the primary category term?
- Should pricing be addressed in this strategy cycle?

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|------------|
| Blog infrastructure (Eleventy collection + layout) | Engineering | Blocks all content marketing execution |
| Email capture / nurture | Marketing | No mechanism to capture interested users (contradicts PIVOT "source 10 founders" directive) |
