# Support Domain Brainstorm

**Date:** 2026-02-22
**Participants:** User, CTO, CPO
**Issue:** #251 (closed, replaced by new issue)
**Status:** Complete

## What We're Building

A Support domain for the Soleur plugin with 4 agents:

1. **CCO (Chief Customer Officer)** -- Domain leader. Assesses support posture, routes to specialists, handles cross-domain escalations. Covers both reactive support and proactive customer success.
2. **ticket-triage** -- Classifies GitHub issues by severity and domain. Routes bugs to Engineering, feature requests to Product, questions to Support. Uses `gh` CLI for GitHub Issues integration.
3. **knowledge-base-curator** -- Maintains support documentation. Identifies FAQ gaps from issue patterns, drafts help articles, flags stale docs.
4. **community-manager** -- Moved from Marketing. Handles Discord digests, GitHub activity tracking, community health metrics. Unchanged functionality, new organizational home.

Integration: Advisory + GitHub Issues (via `gh` CLI). No external helpdesk integration for v1.

## Why This Approach

- **Completeness of the "Company-as-a-Service" metaphor.** The user wants all business domains represented before shipping to users. Support is a recognized gap in the current 7-domain roster.
- **Prerequisites resolved.** Token budget trimmed (346 words headroom), brainstorm routing table-driven (one row to add), plugin.json description fixed. All blockers from the original #251 deferral are cleared.
- **Minimal scope.** 2 new agents + 1 moved agent + leader. Token budget impact ~180 words (fits within headroom). No external integrations beyond GitHub.
- **community-manager relocation.** Community management is closer to support than marketing. Discord questions are often support requests. The CTO assessment confirmed the boundary: community engagement for individual problem resolution = Support; community content for audience growth = Marketing.

**CPO dissent (noted):** The CPO assessment recommended deferral. Business validation says "stop adding features." Solo founders with 0 users have no support load. The user acknowledged this but chose completeness over strict validation adherence -- the "Company-as-a-Service" pitch needs a complete roster.

## Key Decisions

- **Domain name: `support`** -- More widely recognized than `customer`. Directory: `agents/support/`.
- **Leader title: CCO (Chief Customer Officer)** -- Encompasses support + customer success. Avoids "CSO" collision with Chief Security Officer. Consistent with C-suite naming pattern (CTO, CMO, CLO, COO, CPO, CRO).
- **Include customer success in scope** -- Not just reactive support. The CCO covers proactive customer health, not just ticket resolution.
- **Move community-manager from Marketing to Support** -- Community engagement is closer to support. Marketing retains brand, content, SEO, and paid acquisition functions.
- **Advisory + GitHub Issues integration only** -- No Zendesk/Intercom. Uses `gh` CLI for issue triage. Full helpdesk integration deferred to when actual support volume warrants it.
- **3 agents minimum (+ 1 moved)** -- CCO + ticket-triage + knowledge-base-curator + community-manager (moved). No escalation-manager for v1.

## Cross-Domain Boundaries

| Boundary | Support Owns | Other Domain Owns |
|----------|-------------|-------------------|
| Support <-> Sales | Post-sale customer issues | Pre-sale prospects, renewal negotiations |
| Support <-> Engineering | Bug classification and reproduction | Bug investigation and fix |
| Support <-> Product | Aggregate feature request patterns ("N users asked for X") | Feature prioritization and roadmap |
| Support <-> Marketing | Individual customer problem resolution, community health | Brand content, audience growth, SEO, retention system design |
| Support <-> Operations | Uses support tooling | Procures and provisions support tooling |

## Open Questions

- **What artifacts does the CCO assess?** Candidates: `knowledge-base/support/runbooks/`, GitHub issue data via `gh`, community health metrics. Need to define the assessment inputs when building the agent.
- **community-manager skill (`/soleur:community`):** The skill references the community-manager agent. After the move, the skill routing should still work (plugin loader discovers agents recursively), but verify the skill's Task calls use the correct agent name.
- **CSS color for Support domain:** Need to pick a color for `--cat-support` that's distinct from existing domain colors. Candidates: purple (#9B59B6), warm red (#E74C3C), or coral.

## Capability Gaps

| Gap | Domain | Why Needed |
|-----|--------|------------|
| Disambiguation updates across 5+ existing agents | Engineering (review) | Moving community-manager and adding CCO requires disambiguation sentences in CRO, CMO, CPO, CTO, and COO descriptions. |
