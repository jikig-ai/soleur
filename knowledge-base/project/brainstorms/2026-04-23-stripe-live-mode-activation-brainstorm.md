---
title: Stripe Live Mode Activation
date: 2026-04-23
issue: 1444
related_issues:
  - 1053
  - 1439
  - 1443
  - 2626
phase: 4
status: brainstorm-complete
owner: Jean Deruelle
---

# Stripe Live Mode Activation — Brainstorm

## What We're Building

The operational framework for flipping Stripe from test mode to live mode when Phase 4 validation gates are met. Scope is **runbook + dashboard + documentation reconciliation + tax plan**, not a new Stripe integration — the code is already mature.

This brainstorm covers roadmap row 4.10 (#1444). It reframes the feature from "build live mode" to "activate what's already built, once we can trust the trigger."

### Current Code State (2026-04-23)

Verified via `git show main:<path>`:

- `apps/web-platform/lib/stripe.ts` — 82 lines; tier memo cache with LRU-ish eviction; webhook-lag fallback for slot-acquire cap-hit
- `apps/web-platform/lib/stripe-price-tier-map.ts`, `stripe-subscription-statuses.ts`, `stripe-subscription-transition.ts`
- Migrations: `002_byok_stripe_columns`, `020_subscription_billing`, `021_unique_subscription`, `030_processed_stripe_events` (webhook dedup)
- Endpoints: `api/checkout/route.ts`, `api/billing/invoices/route.ts`, `api/billing/portal/route.ts`, `api/webhooks/stripe/route.ts`
- Tests: 7 files covering webhooks, invoice, plan-tier, billing enforcement, rate limiting
- Design: 7 billing screenshots (active/cancelling/none, retention modal, 3× upgrade modals)
- Preflight: `scripts/verify-stripe-prices.ts` — checks 4 tier price IDs exist in configured Stripe environment
- Recent hardening merged 2026-04-22: `#2787` (dedup + out-of-order guard), `#2772`, `#2771`, `#2701` (out-of-order subscription-deleted), `#2619` (exhaustive status mapping)

### Current Documentation State

- `knowledge-base/product/pricing-strategy.md` — documents 2 tiers (Pro $49, Team $99), status "undecided"
- Code + env vars use **4 tiers**: `STRIPE_PRICE_ID_SOLO`, `_STARTUP`, `_SCALE`, `_ENTERPRISE`
- Drift between doc and code is a silent contradiction that must be resolved before marketing writes the live `/pricing` page

### Current Validation State

- 0 beta users recruited (#1439 open)
- 0 exit interviews (#1443 open)
- Finance cost model not started (#1053, #2626 open) → blocks gate 4
- Stripe account is **test-mode only**, no business verification / bank / tax setup

## Why This Approach

### Decision: Runbook-first sequencing (Approach A)

Chosen over dashboard-first and monolithic-spec alternatives because:

1. **KYC is a wall-clock blocker.** Stripe business verification (representatives, bank account, tax ID, business profile) takes days to weeks and is not parallelizable with any code work. It must start the moment the founder decides to commit, regardless of gate status.
2. **Gate 4 depends on #1053.** The finance cost model is a hard prerequisite for gate 4 ("infrastructure cost per-user understood, margin positive"). A readiness dashboard that renders gate 4 without cost-model data is a zero-reader artifact.
3. **Runbook is usable today.** Every step (Stripe Tax enablement, live-mode price creation, webhook endpoint, Doppler `prd` population, `verify-stripe-prices` against prd, pricing-strategy doc update) is executable without new user data.
4. **Dashboard ROI curves with user count.** At 0–5 users, subjective judgment matches automated measurement at lower cost. Dashboard investment belongs later in Phase 4 when quantitative signal exists.

### Decision: 4-tier is canonical

Four tiers in `stripe-price-tier-map.ts` and `verify-stripe-prices.ts` are the source of truth. `pricing-strategy.md` will be rewritten to match. Brand guide, homepage, and `/pricing` page follow. This decision is load-bearing for the runbook (live price creation for 4 tiers, not 2) and for all marketing updates.

### Decision: Strict 4/5 via dashboard-driven telemetry

Activation fires only when the readiness dashboard shows 4/5 gates passing. Founder judgment does not override the dashboard — this is a deliberate commitment device against premature monetization. Dashboard ships late in the feature train (after #1053); until then, activation is simply not possible.

### Decision: Stripe Tax for VAT/sales tax

Stripe Tax handles EU VAT, UK VAT, and US sales tax nexus automatically. 0.5% fee per transaction. The alternative (manual VAT MOSS/OSS filing) costs a solo founder weeks of ongoing compliance burden for a near-zero revenue base. At Solo tier ($49) × projected low-double-digit subscribers, the fee is negligible.

### Decision: Activation trigger fires when dashboard shows 4/5, not when issue #1444 "starts"

Issue #1444 is the roadmap row for activation but the activation moment is data-driven, not calendar-driven. The spec produced by this brainstorm ships the runbook and dashboard; the flip itself is a runbook-execution session that happens whenever the data says go.

## Key Decisions

| # | Decision | Rationale |
|---|---------|-----------|
| 1 | 4-tier pricing is canonical (Solo $49 / Startup $149 / Scale $499 / Enterprise custom) | Code + preflight script already encode this; changing direction now would require dropping shipped hardening work |
| 2 | Gate measurement via readiness dashboard (telemetry + interview hybrid) | Strict 4/5 gate requires verifiable signal; founder judgment alone is not a commitment device |
| 3 | Stripe Tax enabled for EU VAT + US sales tax | 0.5% fee < compliance burden of manual VAT MOSS/OSS |
| 4 | Stripe account KYC starts in parallel with code work | Days–weeks wall-clock blocker, not parallelizable with engineering |
| 5 | Runbook-first sequencing (Approach A) | KYC wall-clock + #1053 dependency + YAGNI on dashboard until user data exists |
| 6 | Dashboard deferred to a separate issue, depends on #1053 | Gate 4 (cost model) has no data source until #1053 ships; empty dashboard is waste |
| 7 | Pricing docs reconciliation is in-scope for #1444 | Live-mode flip without updated `/pricing` page is a broken promise to first paying user |
| 8 | Soft-launch to single tier NOT adopted | All 4 tiers activate together; `plan-based agent concurrency enforcement` (#1162, merged) already gates tier behavior in code |

## Non-Goals

- No new Stripe integration code (webhooks, endpoints, tier logic). Integration is mature; don't rebuild.
- No refund/dispute workflow changes. Existing code handles standard cases; edge cases can be manual in Stripe Dashboard.
- No new tier structure (e.g., free cloud tier, usage-based pricing). Decided out — `#1444` is flip-the-switch, not redesign.
- No marketing launch campaign. Separate concern — addressed by CMO during/after activation window.
- No changes to `verify-stripe-prices.ts` beyond ensuring it runs green against Doppler `prd`.
- No currency localization on `/pricing`. Stripe Tax handles tax; display stays USD for now.

## Open Questions

- **Willingness-to-pay gate 3 threshold:** "3+ founders say they would pay $49/month" — does this mean 3 for Solo tier specifically, or 3 for any tier? Resolve before the dashboard defines the metric.
- **Enterprise tier activation path:** Enterprise is custom-priced. Does live mode require a manual quote flow or is "contact sales" mailto sufficient for MVP?
- **EU 14-day consumer cooling-off period:** SaaS with digital services opt-out requires explicit consent copy at checkout. CLO assessment needed before activation.
- **Cancellation policy:** Pro-rata refund on mid-cycle cancel, or cancel-at-period-end? Design screenshots show retention modal but policy not documented.
- **Multi-currency display on /pricing:** Stripe Tax handles back-end; front-end `/pricing` currently USD-only. Acceptable for EU customers or do we need a currency toggle?
- **Dashboard ownership:** Once gate-measurement dashboard ships, who owns keeping it green? (CPO proposed — to confirm.)

## Deliverables

This brainstorm produces a spec for #1444 with three tracked work items:

1. **Activation runbook** (docs/ops, no code): operator checklist covering Stripe KYC steps, live-mode price creation for 4 tiers, Stripe Tax enablement, webhook endpoint registration, Doppler `prd` population, pre-activation validation via `verify-stripe-prices`, post-activation smoke test, rollback procedure.
2. **Pricing docs reconciliation** (small code + docs PR): rewrite `pricing-strategy.md` for 4 tiers; update brand guide tier references; update `/pricing` page copy (Eleventy `apps/docs`); update homepage if tier count mentioned. Pre-activation, test-mode pricing IDs still apply.
3. **Readiness dashboard (deferred to new issue)** — depends on #1053 (finance cost model). Will be tracked as a separate GitHub issue, milestoned to Phase 4. Brainstorm defines acceptance criteria so the spec is ready when #1053 completes.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Domain leaders were not spawned during this brainstorm because the scope questions were product-/founder-decidable (tier canon, gate mechanism, tax strategy, trigger policy, sequencing) and the user answered them directly. Domain leaders will be spawned during `soleur:plan` with focused briefs:

### Finance (CFO)

**Summary:** Must validate Stripe Tax fee economics against current margin model; hard prerequisite #1053 (finance cost model) gates both gate 4 measurement and dashboard build. CFO also consulted on revenue recognition and Stripe reporting integration.

### Legal (CLO)

**Summary:** EU 14-day cooling-off language, SaaS digital services opt-out consent copy, refund policy documentation, Terms of Service update for live-mode subscriptions. Vendor DPA for Stripe already closed in #670.

### Operations (COO)

**Summary:** Stripe KYC workflow (business profile, representatives, bank, tax ID), Stripe Tax enablement in dashboard, live-mode webhook endpoint registration, Doppler `prd` secret management. Owns the runbook execution.

### Product (CPO)

**Summary:** Final tier canonicalization, gate threshold definitions (especially WTP gate 3), dashboard acceptance criteria, decision authority on activation flip.

### Marketing (CMO)

**Summary:** `/pricing` page rewrite for 4 tiers, `pricing-strategy.md` rewrite, brand guide update, homepage tier references. Launch messaging is out of scope for #1444 itself.

### Sales (CRO)

**Summary:** Enterprise tier activation path (manual quote vs. mailto), upgrade path from Solo → Startup → Scale based on usage signals. Deal-architect may own Enterprise quote template.

## Capability Gaps

None reported. Existing agents (CFO, CLO, COO, CPO, CMO, CRO, plus `deal-architect`, `pricing-strategist`, `financial-reporter`) cover all consultation needs during planning.

## References

- Issue: <https://github.com/jikig-ai/soleur/issues/1444>
- Roadmap: `knowledge-base/product/roadmap.md` row 4.10
- Pricing strategy (to be reconciled): `knowledge-base/product/pricing-strategy.md`
- Related PRs (recent Stripe hardening): #2787, #2772, #2771, #2701, #2619, #2617, #2186, #2081, #2036
- Depends on: #1053 (finance cost model, open) — gate 4 and readiness dashboard
- Related open issues: #1439 (recruit 10 founders), #1443 (exit interviews + WTP), #2626 (per-concurrent-agent infra cost)
