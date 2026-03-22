---
topic: strategy-review-cadence
date: 2026-03-22
status: complete
---

# Strategy Document Review Cadence Brainstorm

## What We're Building

Two deliverables:

1. **Frontmatter standard + CI cron** — A standardized review metadata schema for all strategy documents in knowledge-base, plus a scheduled workflow that detects overdue docs and creates GitHub issues.

2. **Business validation update + cascade** — Update `business-validation.md` with critical user research finding (2026-03-22: 5+ conversations, users reject plugin format, want native cross-platform). Then cascade to dependent docs via parallel domain leader sub-agents.

Approach: frontmatter standard first, then use it to drive the validation update as the first "cadence-driven review."

## Why This Approach

### The problem

Most strategy documents have no review metadata or scheduled cadence. Of 11 strategy docs audited:
- 6 have `review_cadence` in frontmatter, 5 have none
- Only 1 has an `owner` field (roadmap.md → CPO)
- Only 5 have `depends_on` fields
- Documents go stale ad hoc — the brand guide predates both the PIVOT (2026-03-12) and user research (2026-03-22)

### User research finding (2026-03-22)

From 5+ conversations with solo founders:
- **Plugin too limiting**: Users want capabilities beyond what a CLI plugin can offer (visual UI, dashboards, mobile access)
- **Don't use Claude Code**: Many aren't Claude Code users — the plugin assumes a tool they don't use
- **Want standalone product**: Users want a standalone app/platform accessible anywhere, not tied to a specific dev tool

This finding invalidates the plugin delivery mechanism and affects multiple validation gates (Customer, Competitive Landscape, Demand Evidence, Minimum Viable Scope).

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Approach order | Frontmatter standard first, then validation update | Cleaner process — validation update follows the new system |
| Scope | Product + Marketing + Sales, expand later | Highest-priority strategy docs, prove the pattern first |
| Enforcement | CI cron (periodic) + event-driven cascading | CI catches silent staleness, cascading catches upstream changes |
| Cascade model | Same-session parallel sub-agents | When upstream doc changes, spawn CPO/CMO/CRO in parallel to update dependents |
| Cadence tiers | Monthly (fast-moving: roadmap), Quarterly (stable: validation, brand), Event-driven (triggered by dependency changes) | Matches existing patterns in docs that have cadence |

## Frontmatter Schema

Standard fields for all strategy documents:

```yaml
---
last_updated: YYYY-MM-DD      # When content was last changed
last_reviewed: YYYY-MM-DD     # When someone last confirmed content is current (may not change content)
review_cadence: monthly|quarterly  # How often this doc should be reviewed
owner: CPO|CMO|CRO|CTO        # Which domain leader is responsible
depends_on:                     # Upstream documents — changes trigger cascade review
  - knowledge-base/product/business-validation.md
---
```

## Dependency Graph

```
business-validation.md
├── brand-guide.md (positioning depends on validation verdict)
├── roadmap.md (phases depend on validated direction)
├── pricing-strategy.md (pricing depends on delivery mechanism)
├── marketing-strategy.md (strategy depends on product direction)
├── content-strategy.md (content depends on marketing strategy)
└── competitive-intelligence.md (competitive framing depends on delivery mechanism)
```

## CI Cron Design

Scheduled workflow (`scheduled-strategy-review.yml`):
- Runs weekly (e.g., Monday 08:00 UTC)
- Scans all .md files in knowledge-base/product/, marketing/, sales/
- Parses frontmatter for `review_cadence` and `last_reviewed`
- If `last_reviewed` + cadence period < today → document is overdue
- Creates a GitHub issue per overdue document with label `scheduled-strategy-review`
- Skips docs without `review_cadence` (not yet opted in)

## Open Questions

1. **Should the cascade be a skill?** The same-session cascade (spawn domain leaders to update dependent docs) could be formalized as a `/soleur:strategy-cascade` skill, or it could be manual (just run the domain leaders).
2. **Frontmatter migration**: Should we add frontmatter to all docs in this PR, or only to docs that already have partial metadata?
3. **Review vs. Update semantics**: A review that finds no changes should still update `last_reviewed`. Should the CI workflow distinguish between "reviewed and confirmed current" vs "reviewed and updated"?
