# Status Page Setup Brainstorm

**Date:** 2026-04-07
**Status:** Decided
**Trigger:** BetterStack email proposing status page setup

## What We're Building

Activate BetterStack's free-tier status page to provide public incident communication. The page will show a curated subset of user-facing service monitors (not internal infrastructure). No custom domain or paid features at this stage.

## Why This Approach

- **Zero cost** -- BetterStack free tier includes 1 status page with subscriber notifications
- **Vendor consolidation** -- BetterStack already handles uptime monitoring; status page auto-populates from existing monitors with zero integration work
- **Ready when needed** -- infrastructure in place before first customer, not scrambled during an incident
- **Minimal overhead** -- no additional vendor, no self-hosting maintenance, no separate incident management workflow

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Vendor | BetterStack | Already our monitoring provider; native integration eliminates config overhead |
| Tier | Free | $0/mo; paid tiers ($15-265/mo) are 47-826% increase on current $32/mo spend |
| Domain | BetterStack subdomain (*.betteruptime.com) | Custom domain (status.soleur.ai) requires paid plan; not justified pre-revenue |
| Components | Curated user-facing services only | Hide internal infrastructure monitors; show Website, API, etc. |
| Upgrade trigger | First paying customer | Re-evaluate all paid options (custom domain, white-label, custom CSS) at that milestone |

## Non-Goals

- Custom domain (status.soleur.ai) -- deferred to post-first-customer
- White-label branding -- deferred to post-first-customer
- Incident communication runbooks -- greenfield area, build when patterns emerge
- Self-hosted alternatives (Cachet, Upptime) -- BetterStack vendor consolidation wins

## Open Questions

- Which specific monitors to expose as public components (needs BetterStack dashboard review)
- Whether to enable email/SMS subscriber notifications on the free tier immediately

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Operations (COO)

**Summary:** BetterStack is the right vendor due to native monitor integration. Recommended deferring entirely until first customer, but accepted free-tier activation as zero-cost, zero-risk. Flagged that Plausible Analytics trial expiry (2026-03-24) needs verification (since resolved -- Plausible is active at EUR 9/mo).

### Finance (CFO)

**Summary:** Free tier is financially sound at $0/mo. Paid tiers ($15-265/mo) are disproportionate to current $32/mo recurring spend. Recommended simple upgrade trigger at first paying customer rather than graduated thresholds. BetterStack is already tracked in expenses.md as $0 free-tier.

## Action Items

1. Activate free BetterStack status page via dashboard
2. Configure curated component list (user-facing services only)
3. Update expenses.md to note status page activation on free tier
