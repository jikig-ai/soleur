# Brainstorm: Invoice History + Failed Payment Recovery

**Date:** 2026-04-13
**Issue:** #1079
**Branch:** feat-invoice-recovery
**Status:** Decided

## What We're Building

Invoice history display and failed payment recovery flow for the Soleur cloud platform's Stripe billing integration. This completes the billing trilogy alongside the pricing page (#656, done) and subscription management (#1078, done).

**Scope (minimal viable):**

- Webhook handlers for `invoice.payment_failed`, `invoice.paid`, and `customer.subscription.updated` to track subscription status transitions (`active` → `past_due` → `unpaid`)
- Invoice list page fetching from Stripe API on demand (no local DB table)
- In-app banner when payment has failed, linking to Stripe Customer Portal
- Middleware enforcement: read-only mode when subscription is `unpaid`
- Database migration: add `suspended_at` timestamp to users table

**Explicitly deferred (separate issue):**

- 3-month auto-deletion cron for unpaid accounts (GDPR data minimization)
- Recurring email reminders during grace period
- Pre-deletion warning sequence (30 days, 7 days, 1 day)

## Why This Approach

**Stripe-native over custom.** The CTO assessment identified that building custom card-update forms requires PCI SAQ-A compliance and expands scope from 3-5 days to 1-2 weeks. Stripe's Customer Portal handles card updates, and Stripe's Smart Retries handle the retry schedule (4 attempts over ~3 weeks). We track status transitions via webhooks rather than managing retry logic ourselves.

**Fetch invoices on demand.** Stripe's `invoices.list()` API returns current data with hosted PDF URLs. Storing invoice metadata locally adds migration complexity, stale data risk, and webhook sync logic — all unnecessary when the Stripe API is the source of truth.

**Stripe built-in emails.** Zero implementation effort for MVP. The Resend infrastructure exists (`send.soleur.ai` with DKIM) but adding the SDK, templates, and brand-aligned dunning copy is unnecessary for 1-2 initial users. Can upgrade to custom Resend emails later.

**Read-only grace over full lockout.** The founder's KB artifacts, conversations, and project data represent accumulated value. Full lockout risks permanent churn. Read-only mode preserves trust — the founder can view and export their data while resolving payment. After 3 months unpaid, data is deleted per GDPR data minimization (deferred to separate issue).

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Card update flow | Stripe Customer Portal (redirect) | Avoids PCI scope expansion, zero maintenance |
| Retry logic | Stripe Smart Retries | 4 attempts over ~3 weeks, battle-tested |
| Invoice storage | Fetch from Stripe API on demand | Always fresh, no migration needed |
| Failed payment emails | Stripe built-in | Zero effort for MVP, upgrade path exists via Resend |
| Dunning state | Read-only grace period | Preserves trust, data accessible for export |
| Data retention | 3 months then deletion | GDPR data minimization (deferred to separate issue) |
| Subscription status tracking | Extend existing `subscription_status` column | DB already has `past_due` in CHECK constraint, just needs webhook wiring |
| Idempotency | Deduplicate by Stripe `event.id` | CTO flagged: Stripe can deliver duplicate events |
| Middleware pattern | Follow T&C check pattern | Existing pattern queries `users` table per request |
| Fail-open vs fail-closed | Fail-open for billing checks | Learnings doc recommends fail-open for compliance, fail-closed for security |

## Open Questions

1. **Stripe portal URL:** Currently hardcoded as test URL in billing page. Needs to be dynamized via `stripe.billingPortal.sessions.create()`. Implementation detail for the plan.
2. **Webhook event selection:** CTO recommends `customer.subscription.updated` over `invoice.payment_failed` for tracking `past_due` transitions. Plan should validate which events Stripe fires in which order.
3. **Banner dismissibility:** Should the "payment failed" banner be dismissible or persistent? Product decision for spec.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Prerequisite feature for Phase 4 Stripe live mode — not premature scope. Key product decisions: dunning state (resolved: read-only grace) and retry count (resolved: Stripe-managed). Phase 3 deadline is tight (4/17) but this is the last blocking billing feature. Webhook idempotency is an engineering constraint, not a product decision.

### Marketing (CMO)

**Summary:** Invoice history is table stakes for B2B SaaS — removes a conversion objection. Failed payment recovery is the highest-ROI retention investment at this stage. Dunning copy must match brand voice (honest, actionable). Recommended delegating to conversion-optimizer for layout and copywriter for dunning messaging. Deferred: since Stripe handles emails for now, custom copy is not needed yet.

### Engineering (CTO)

**Summary:** Use Stripe-native features throughout. Extend existing `subscription_status` column (CHECK constraint already allows `past_due`). Add idempotency guard to webhook handler (deduplicate by `event.id`). Middleware already queries users table per request — adding `subscription_status` check is cheap. Medium complexity (3-5 days) with Stripe-native approach. Key risk: existing webhook handler has no idempotency guard and needs one before adding new event types.

### Finance (CFO)

**Summary:** Financially sound with zero incremental cost. Stripe webhooks, hosted PDFs, and retry APIs are included in standard pricing. This is the single most important revenue-protection mechanism at the 1-2 user scale — a single recovered payment per quarter justifies the development time. Recommended generous dunning defaults (resolved: Stripe manages the schedule).
