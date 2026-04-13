# Subscription Management Brainstorm

**Date:** 2026-04-13
**Issue:** #1078
**Status:** Decisions captured
**Branch:** feat-subscription-management

## What We're Building

Portal-first subscription management: founders cancel or manage payment
methods via Stripe Customer Portal, with a custom pre-cancel interstitial
that uses loss aversion (compounding knowledge summary) as the retention
mechanism. Full access continues through the paid billing period after
cancellation. Billing management lives as a section within the Settings page.

Upgrade/downgrade is explicitly deferred until pricing tiers are committed
(currently single $49/mo hypothesis, pricing undecided per pricing strategy).

## Why This Approach

- **0 users, 1 tier** -- building custom tier-switching UI is speculative.
  Stripe Customer Portal handles cancel + payment method out of the box.
- **Phase 3 milestone due 2026-04-17** -- portal-first ships in ~3 days vs
  5-7 days for full custom.
- **Retention via loss aversion > discounts** -- with no churn data,
  discounts on an unvalidated price are meaningless. Showing compounding
  knowledge (KB entries, conversations, services) leverages the product's
  structural advantage.
- **Legal foundation exists** -- ToS Section 5 already covers cancellation,
  grace period, EU withdrawal rights from #893 work. Upgrade/downgrade terms
  deferred with the feature.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Scope | Portal-first (Stripe Customer Portal) | 0 users, 1 tier, 4-day deadline. Custom cancel/upgrade UI deferred. |
| Grace period | Full access until period end | Founder already paid. No degraded state needed. Simplest implementation. |
| Data model | Extend users table + fix RLS | Add billing columns, table-level REVOKE + column allowlist. Simpler than separate subscriptions table, no joins for auth checks. |
| Retention mechanism | Compounding knowledge summary | Show KB artifact count, conversation count, configured services, time since signup. Two CTAs: "Keep my account" (primary) / "Continue to cancel" (secondary). No discounts. |
| Navigation | Settings sub-section | Billing section in existing Settings page alongside Project, API Key, Connected Services, Account. Keeps account management in one place. |
| Upgrade/downgrade | Deferred | No second tier exists. Build when pricing tiers are committed (Phase 4+). |
| Cancel semantics | Cancel at period end (default) | Standard SaaS pattern. Immediate cancel not offered in v1. |
| Legal updates | Deferred with upgrade/downgrade | ToS Section 5 already covers cancellation. Upgrade/downgrade terms added when the feature ships. |

## Open Questions

1. **Cancellation reason survey** -- should the pre-cancel interstitial
   collect structured data on why founders leave? Valuable product
   intelligence but adds complexity. Could be a simple optional dropdown.
2. **Win-back email sequence** -- CMO suggested automated emails during
   grace period showing platform activity. Deferred to marketing planning
   but worth noting as a future retention layer.
3. **Post-period-end access** -- after the billing period expires and access
   is revoked, can the founder still log in to see a "reactivate" page? Or
   are they fully locked out? Needs decision during spec.
4. **Duplicate Stripe customers** -- CTO noted the checkout handler uses
   `customer_email` instead of `customer` param, allowing duplicate Stripe
   customers. Should be fixed in this work.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales,
Finance, Support

### Product (CPO)

**Summary:** Recommends portal-first approach. Flags that upgrade/downgrade
is premature with one tier and 0 users. Phase 3 exit criteria must be
updated if upgrade/downgrade is deferred. Current schema is insufficient --
missing stripe_subscription_id and period tracking. Plan enforcement (#1162)
ships in Phase 4, so middleware must check subscription_status independently.

### Marketing (CMO)

**Summary:** Retention offer needs strategy before code -- no churn data
means discounts are speculative. Recommends loss aversion (show compounding
knowledge at cancel) over financial incentives. Cancellation copy is
brand-critical -- must respect founder autonomy, no dark patterns. Current
billing page has zero brand alignment. Delegates to conversion-optimizer for
cancellation flow layout and retention-strategist for full cancel-to-win-back
journey.

### Engineering (CTO)

**Summary:** Current Stripe integration is minimal but functional. High-risk
gaps: RLS vulnerability (billing columns user-writable), webhook idempotency
(fire-and-forget updates), single-price architecture. Recommends Stripe
Customer Portal for v1 with schema migration adding stripe_subscription_id,
current_period_end, cancel_at_period_end. Fix duplicate Stripe customer
creation in checkout handler.

### Legal (CLO)

**Summary:** Legal foundation substantially in place from #893 cancellation
policy work. ToS Section 5 covers cancellation, grace period, EU withdrawal
rights, refunds. Primary gap: no language for upgrade/downgrade proration --
deferred with the feature. Secondary: confirm whether plan upgrades trigger
fresh EU withdrawal period. Privacy/GDPR/DPD already document Stripe as
processor.
