# Domain Prerequisites Brainstorm

**Date:** 2026-02-22
**Participants:** User, CTO, CPO
**Issue:** #251 (Support department is missing)
**Status:** Complete

## What We're Building

Three prerequisite fixes that unblock future domain additions (like Support) without adding domains now:

1. **Token budget trim** -- Audit and trim all 54 agent descriptions to recover 200+ words of headroom from the current 2,497/2,500 ceiling.
2. **Brainstorm routing refactor** -- Replace the 7 inline routing blocks in Phase 0.5 (~250 lines) with a single markdown config table + generic loop (~60 lines).
3. **plugin.json description fix** -- Add "sales" to the domain list string (currently missing).

## Why This Approach

The original request was to add a Support domain. CTO and CPO assessments converged on deferral:

- **Token budget is at capacity** (2,497/2,500 words). Adding any domain requires trimming first.
- **Brainstorm routing is past its refactor threshold.** The code itself flags this at 5+ domains; we're at 6.
- **Business validation says freeze features.** The 2026-02-22 validation report recommends customer discovery over new capabilities.
- **Support is a post-PMF function.** It becomes relevant when customer volume exceeds one person's capacity.

Fixing prerequisites now means future domain additions (when validated by user demand) are mechanical rather than architectural.

## Key Decisions

- **Defer Support domain** -- No new domain until business validation shows demand. Close #251 with this analysis as rationale.
- **Table-driven brainstorm routing** -- Replace per-domain inline blocks with a config table. Maximum compression, best scalability. Each future domain becomes ~3 lines of config instead of ~35 lines of template.
- **Token trim target: 200+ words recovered** -- Audit all 54 descriptions. Target 35-45 words per specialist, ~30 words per leader.
- **All three fixes in one branch** -- `feat/domain-prerequisites`. Independent changes but small enough to ship together.
- **No other domains needed now** -- Finance is the only moderate candidate (as Operations sub-domain). HR, Data/Analytics, standalone Security, QA all covered or irrelevant for solo founders.

## Domain Gap Analysis (from CTO + CPO)

| Domain | Status | Recommendation |
|--------|--------|----------------|
| Support | Missing | Defer. Post-PMF concern. |
| Finance | Missing | Future Operations sub-domain if needed. |
| HR/People | N/A | Irrelevant for solo founders. |
| Customer Success | Overlap | If needed, lives inside Support or Sales. |
| Data/Analytics | Partial | Marketing analytics-analyst covers current need. |
| Security | Partial | Engineering security agents are sufficient. |
| QA/Testing | Covered | Engineering test agents + ATDD skill. |

## Open Questions

- **Token budget enforcement:** Should we add a CI check or pre-commit hook to prevent token budget overflows? (CTO flagged this as a capability gap.)
- **community/ directory:** Currently empty with .gitkeep. Clarify purpose -- is it for external agent installs (agent-finder) or a future domain? If the former, document it; if the latter, decide what goes there.

## Capability Gaps (from CTO)

| Gap | Domain | Why Needed |
|-----|--------|------------|
| Table-driven domain routing | Engineering (workflow) | Current approach requires ~35 lines per new domain. Table-driven reduces to ~3 lines. |
| Token budget CI check | Engineering (workflow) | No automated guard prevents merging agents that exceed 2,500-word limit. |
