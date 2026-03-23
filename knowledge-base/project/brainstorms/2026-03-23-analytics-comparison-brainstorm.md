# Analytics Comparison: Plausible vs Cloudflare Web Analytics

**Date:** 2026-03-23
**Status:** Decision Made
**Decision:** Keep Plausible Analytics ($9/mo Starter plan)

## What We Were Evaluating

Whether to switch from Plausible Analytics (free trial ending 2026-03-24) to Cloudflare Web Analytics (free, already proxied through Cloudflare) to save $108/year.

## Why We're Keeping Plausible

The migration cost significantly exceeds the annual savings. Plausible is deeply integrated across 6+ systems, and Cloudflare Web Analytics lacks parity in three critical areas: custom events, API access, and EU data residency.

## Key Decisions

- **Keep Plausible on the Starter plan ($9/mo)** — the $108/year cost is justified by the automation, legal simplicity, and custom event tracking it enables
- **No migration needed** — all existing CI workflows, legal documents, growth tracking, and custom events remain intact
- **Revisit at scale** — if traffic grows past 10k pageviews/mo, evaluate plan upgrades vs alternatives at that point

## Feature Comparison

| Capability | Plausible ($9/mo) | Cloudflare Web Analytics (Free) |
|---|---|---|
| Basic metrics | Yes | Yes |
| Cookie-free | Yes | Yes |
| Custom events/goals | Yes (Newsletter Signup, page goals) | No |
| API access | Yes (Stats API v1, Goals API) | Limited GraphQL |
| Data retention | 3 years | ~6 months |
| EU data residency | Yes (Hetzner, Germany) | No (US company) |
| Open source | Yes | No |
| Data export | Yes (API) | No |
| Formal DPA | Yes (analytics-specific) | Generic only |

## Migration Cost Analysis (If We Had Switched)

| Component | Effort | Detail |
|---|---|---|
| `base.njk` JS snippet | Low | Swap script tag |
| 4 legal documents | High | Privacy policy, cookie policy, GDPR policy, data protection disclosure all name Plausible and cite EU residency |
| 2 CI workflows + 2 scripts | Medium | Weekly analytics snapshots and goal provisioning |
| Marketing strategy docs | Low | Update references |
| Growth targets spec | Medium | New data source for WoW tracking |

## Legal/Privacy Assessment

- Both tools are cookie-free — no consent banner needed for either
- Plausible advantage: EU data residency, formal analytics-specific DPA, open-source auditability
- Cloudflare risk: US company, EU-US Data Privacy Framework durability uncertain (Schrems precedent)
- Switching would require rewriting all four privacy/GDPR documents

## Financial Context

- Current recurring spend: ~$32/mo
- Plausible adds $9/mo = $41/mo total (+28%)
- Current traffic: ~160 pageviews/month (well within 10k Starter ceiling)
- Pre-revenue stage — $108/year is small relative to engineering time to migrate

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Operations

**Summary:** Plausible touches 9 integration points across the codebase. Switching to Cloudflare Web Analytics would save $108/year but require disabling 2 CI workflows, rewriting scripts, and updating legal docs — engineering effort far exceeds the savings.

### Legal

**Summary:** Both tools are cookie-free and exempt from ePrivacy consent requirements. The key legal risk of switching is losing EU data residency (Plausible: Hetzner Germany, Cloudflare: US-based), requiring rewrites of 4 legal documents and weakening the GDPR posture around international data transfers.

### Finance

**Summary:** At $9/mo, Plausible represents a 28% increase to recurring spend but is justified by the automation infrastructure it powers. The engineering opportunity cost of migration exceeds the annual savings. No formal budget exists — recommend establishing a monthly spending ceiling.

## Open Questions

- When traffic exceeds 10k pageviews/mo, should we upgrade Plausible or evaluate alternatives?
- Should we establish a formal monthly budget ceiling? (CFO flagged this gap)
