# Competitive Intelligence Brainstorm

**Date:** 2026-02-27
**Issue:** #330
**Status:** Decided
**Participants:** CMO, CPO

## What We're Building

A recurring competitive intelligence capability for Soleur: a dedicated Product-domain agent (`competitive-intelligence`) and a corresponding skill (`competitive-analysis`) that runs monthly via `soleur:schedule`, producing a structured knowledge-base document that both Marketing and Product domains can consume.

The agent researches competitors using WebSearch/WebFetch, reads existing positioning context from `business-validation.md` and `brand-guide.md`, and writes/updates `knowledge-base/overview/competitive-intelligence.md` using the overlap matrix format established by the marketingskills analysis.

## Why This Approach

The Cowork Plugins competitive threat was discovered 22 days after launch because `business-validation.md` is a point-in-time snapshot with no review cadence. The platform risk learning explicitly called out: "Business validation documents should have a `last_reviewed` cadence, not be point-in-time snapshots."

Competitive analysis fragments already exist across 4+ agents (growth-strategist, pricing-strategist, deal-architect, programmatic-seo-specialist) but no one owns recurring intelligence. This creates the risk of contradictory positioning across downstream artifacts.

**Approach A (selected):** Single agent + skill. Ship fast, iterate later. Multi-agent orchestration (Approach B) and document cadence system (Approach C) are filed as separate issues for future work.

## Key Decisions

1. **Ownership:** Product domain (CPO orchestrates). The agent lives under `agents/product/`. Both Marketing and Product consume the output.
2. **Scope:** Tier 0 (Anthropic Cowork/platform threats) + Tier 3 (CaaS platforms) by default. Configurable via parameter to include other tiers.
3. **Cadence:** Monthly, scheduled via `soleur:schedule`. Each run produces a standalone report (no state across runs).
4. **Output:** Living document at `knowledge-base/overview/competitive-intelligence.md` using the overlap matrix format (competitor, our equivalent, overlap level, differentiation, convergence risk). Includes `last_reviewed` frontmatter field.
5. **Agent design:** New dedicated `competitive-intelligence` agent under `agents/product/`, not an extension of `business-validator`. The monitoring function is behaviorally distinct from the one-time validation workshop.
6. **Context loading:** Agent MUST read `brand-guide.md` and `business-validation.md` before producing assessments (per the agent context-blindness learning).
7. **Autonomous execution:** Designed for batch/autonomous execution from the start, not workshop-style. Must support `$ARGUMENTS` bypass for non-interactive invocation via schedule.

## Open Questions

- **Escalation threshold:** What constitutes a "material change" worth escalating vs. filing? The marketingskills cadence says "escalate if they add AEO or framework-specific modes" -- a similar threshold definition is needed.
- **New entrant discovery:** Should the agent actively scan for new competitors not yet in the landscape, or only monitor known ones? Active scanning is more valuable but harder to scope.
- **Polsia.com tier classification:** Not yet classified in the 6-tier model. The agent's first run should categorize it.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|-----------|
| Multi-agent CI orchestration | Product/Marketing | Approach B: agent coordinates growth-strategist, pricing-strategist, deal-architect to cascade CI updates to downstream artifacts (battlecards, comparison pages, pricing matrices). Filed as separate issue. |
| Document cadence enforcement | Product/Operations | Approach C: mechanism to add `last_reviewed` fields to knowledge-base docs and surface stale ones. Broader than CI -- addresses the root staleness problem. Filed as separate issue. |

## Related Artifacts

- **Business validation:** `knowledge-base/overview/business-validation.md` (6-tier competitive landscape)
- **Platform risk learning:** `knowledge-base/learnings/2026-02-25-platform-risk-cowork-plugins.md`
- **Marketingskills overlap analysis:** `knowledge-base/learnings/2026-02-20-marketingskills-overlap-analysis.md` (overlap matrix format template)
- **Schedule skill:** `plugins/soleur/skills/schedule/SKILL.md` (v3.5.0, cron infrastructure)
- **Cowork risk brainstorm:** `knowledge-base/brainstorms/archive/20260225-*-cowork-plugins-risk-analysis-brainstorm.md`
