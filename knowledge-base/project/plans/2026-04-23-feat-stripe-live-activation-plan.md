---
title: "feat: Stripe Live Mode Activation — runbook, docs reconciliation, legal checklist"
date: 2026-04-23
issue: 1444
brainstorm: knowledge-base/project/brainstorms/2026-04-23-stripe-live-mode-activation-brainstorm.md
spec: knowledge-base/project/specs/feat-stripe-live-activation/spec.md
branch: feat-stripe-live-activation
worktree: .worktrees/feat-stripe-live-activation
pr: 2836
depends_on: []
deferred_follow_ups:
  - 2841 # readiness dashboard
---

# Plan: Stripe Live Mode Activation

Issue: [#1444](https://github.com/jikig-ai/soleur/issues/1444) | Branch: `feat-stripe-live-activation` | Draft PR: #2836
Deferred follow-up: [#2841](https://github.com/jikig-ai/soleur/issues/2841) (readiness dashboard)

## Overview

Docs-only PR that makes the live-mode flip a mechanical operator session. Three deliverables:

1. **Operator runbook** (new): `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md`
2. **Pricing-strategy reconciliation** (edit one file): `knowledge-base/product/pricing-strategy.md` — 2-tier → 4-tier to match code and marketing
3. **Legal brief** (new): `knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md` — CLO hand-off

Alternative sequencing options are in the brainstorm; this plan executes Approach A (runbook-first).

## Research Reconciliation — Spec vs. Codebase

Pre-plan grep verification materially shrinks the spec's FR1 scope:

| Spec claim | Codebase reality (2026-04-23) | Plan response |
|---|---|---|
| `pricing-strategy.md` is 2-tier (Pro/Team) | Confirmed. Tier Structure table + ~3 prose references. | **In scope.** |
| `/pricing` page needs 4-tier rewrite | **Already 4-tier**: `plugins/soleur/docs/pages/pricing.njk` shows Solo/Startup/Scale/Enterprise at lines 215-263. | **Out of scope.** |
| Brand guide references Soleur Pro/Team | No hits. Only "Claude Pro" (Anthropic's product). | **Out of scope.** |
| Homepage has tier refs | `index.njk` links to `/pricing` but has no direct tier mentions. | **Out of scope.** |
| Webhook requires `STRIPE_PUBLISHABLE_KEY` (frontend) | Grep: no `NEXT_PUBLIC_STRIPE*` usage. Current flow redirects to hosted Stripe Checkout URL; no `loadStripe()` call. | **Not needed in Doppler.** Runbook explicitly states this. |
| `processed_stripe_events` dedup table exists | Migration 030 shipped. | **Referenced**, no work. |
| 7 Stripe test files | Confirmed. | **No changes.** |

Net effect: the pricing-doc reconciliation touches **one file**: `pricing-strategy.md`.

## Implementation Phases

### Phase 1: Runbook

Create `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md` following the structure of `supabase-migrations.md`. The runbook's 8 phases (summary — full content lives in the runbook itself):

- **A. KYC (founder)** — business profile, industry, product description, statement descriptor, bank, representative identity. Wall-clock days–weeks; the only founder-exclusive phase.
- **B. Stripe Tax enablement** — dashboard toggle, jurisdiction registration (EU OSS, UK, US nexus). Fee: 0.5%/transaction. Must precede Phase C.
- **C. Live-mode price object creation** — 4 tiers: Solo (4900), Startup (14900), Scale (49900), Enterprise (no default price — "contact sales" flow). Enterprise's `STRIPE_PRICE_ID_ENTERPRISE` will use a $0 placeholder price ID so `verify-stripe-prices.ts` passes; the Enterprise checkout path is a mailto, not the Stripe Checkout session (verify at runbook-write time by reading `stripe-price-tier-map.ts`).
- **D. Live webhook endpoint registration** — `https://app.soleur.ai/api/webhooks/stripe` (live mode). Subscribe to the exact 5 events the handler supports (extracted from `apps/web-platform/app/api/webhooks/stripe/route.ts`): `checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`, `invoice.paid`. Capture signing secret.
- **E. Doppler `prd` secret population** — `doppler secrets set` for: `STRIPE_SECRET_KEY` (sk_live_), `STRIPE_WEBHOOK_SECRET` (whsec_ from Phase D), and all 4 price IDs (`STRIPE_PRICE_ID_SOLO|STARTUP|SCALE|ENTERPRISE`). Config scope: `prd` (not `prd_terraform`). Frontend `STRIPE_PUBLISHABLE_KEY` is **NOT** needed — confirmed by grep of `apps/web-platform` (hosted-checkout flow).
- **F. Preflight** — `doppler run -p soleur -c prd -- bun run apps/web-platform/scripts/verify-stripe-prices.ts` → exit 0. Catches missing env vars and 404'd price IDs; does NOT catch a mismatched webhook signing secret (see Phase G).
- **G. Deploy + smoke test** — after merge + deploy:
    1. Create `stripe prices create --product <Solo product ID> --unit-amount 50 --currency usd --recurring[interval]=month` — a one-time $0.50/mo test price on the live account (NOT $0, which skips `invoice.paid`).
    2. Run a real checkout from a founder-owned account against the test price. Verify Stripe Dashboard → Payments shows the $0.50 charge.
    3. Verify the live webhook delivered: Supabase → `processed_stripe_events` table has a row with `event_type = checkout.session.completed` timestamped within 60s of the test.
    4. Verify `public.users` row for the test email has `subscription_status = active` and `plan_tier = solo`.
    5. **Webhook-secret smoke test** (catches the gap Phase F can't): trigger a second webhook via Stripe Dashboard → Developers → Webhooks → [live endpoint] → "Send test webhook" with `checkout.session.completed`. Confirm a second `processed_stripe_events` row appears. If no row appears within 60s, `STRIPE_WEBHOOK_SECRET` is mismatched — return to Phase E.
    6. Cancel the test subscription via `/dashboard/settings/billing`. Refund the $0.50 via Stripe Dashboard. Archive the test price object.
    7. Swap `/pricing` waitlist CTA → Stripe Checkout link (one-line edit to `plugins/soleur/docs/pages/pricing.njk` — replace `<form class="newsletter-form waitlist-form">` block with a `<a class="btn btn-primary" href="/api/checkout?tier=solo">` anchor, with the existing form hidden behind a build-time env flag if the founder wants rollback optionality). Verify by `curl -s https://soleur.ai/pricing/ | grep checkout.stripe.com` once the deploy lands (or grep `/api/checkout` for the relative link).
- **H. Rollback** — revert `STRIPE_SECRET_KEY` to `sk_test_…` AND `STRIPE_WEBHOOK_SECRET` to test-mode `whsec_…` in the SAME `doppler secrets set` transaction (stale pairing causes 400 on every webhook). Revert `STRIPE_PRICE_ID_*` to test-mode IDs (preserve live IDs in an encrypted note for re-activation). Disable (don't delete) the live webhook endpoint in Stripe Dashboard — preserves audit trail. Revert `/pricing` CTA change. Document state in #1444 comment.

Runbook cross-refs: full path `knowledge-base/project/learnings/integration-issues/2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md`, `knowledge-base/project/learnings/2026-04-13-stripe-status-mapping-check-constraint.md`, `knowledge-base/project/learnings/2026-04-13-billing-review-findings-batch-fix.md`.

### Phase 2: pricing-strategy.md reconciliation

One-file edit. Specific hunks:

- **Tier Structure table** (lines 121-126): replace 2 rows with 4, mirroring `stripe-price-tier-map.ts` and the concurrency numbers already visible in `pricing.njk`. Verify concurrency numbers by reading `apps/web-platform/lib/stripe-price-tier-map.ts` at work time.
- **"Why $49/month" section** (lines 127-133): retain the $49 anchor; add 1 paragraph explaining Startup/Scale pricing anchored to concurrency/team-size cohorts.
- **Risks / Next Steps prose** (lines 25, 188, 215): replace "Pro tier infrastructure" → "hosted-platform infrastructure"; "Pro tier" → "Solo tier".
- **Status block** (line 17): update from "Pricing is undecided" to reflect 4-tier canon + activation gated on the 5 pricing gates.

### Phase 3: Legal brief

Create `knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md`. This is a CLO hand-off brief, not final legal text. Sections: (1) EU 14-day cooling-off + SaaS digital-services opt-out consent wording proposal, (2) refund/cancellation policy proposal (cancel-at-period-end, no pro-rata), (3) ToS subscription addendum brief (billing cycle, price changes, tax, data retention on cancellation), (4) AUP/Privacy Policy sub-processor confirmation (Stripe DPA already covered by #670), (5) Stripe Atlas alignment note (cross-ref `2026-02-25-stripe-atlas-legal-benchmark-mismatch.md`), (6) explicit CLO sign-off line.

## Files to Create

- `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md`
- `knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md`

## Files to Edit

- `knowledge-base/product/pricing-strategy.md`

Scope fence: no `.ts`, `.tsx`, `.sql`, or `.njk` changes in this PR. AC3 enforces via `git diff --stat`.

## Acceptance Criteria

### Pre-merge (PR)

1. `stripe-live-activation.md` exists, is end-to-end readable by an operator unfamiliar with Stripe, and references `verify-stripe-prices.ts` as the machine-checkable preflight.
2. `stripe-live-legal-checklist.md` exists with 6 sections and an explicit CLO sign-off line as the final gate.
3. `pricing-strategy.md` has 4 tiers matching `stripe-price-tier-map.ts`. Broadened grep gate (cover plan/tier/price variants):
   `rg -n "Pro tier|Team tier|Pro plan|Team plan|\\$99(/month| per month|/mo\\b| ?)" knowledge-base/product/pricing-strategy.md` → zero hits.
4. `git diff --stat` shows only `*.md` files changed.
5. `npx markdownlint-cli2 knowledge-base/product/pricing-strategy.md knowledge-base/engineering/ops/runbooks/stripe-live-activation.md knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md` → exit 0.
6. Regression baseline: `cd apps/web-platform && ./node_modules/.bin/vitest run stripe` → exit 0. (Per `cq-in-worktrees-run-vitest-via-node-node`.)

### Post-merge handoff (operator tasks, not PR gates)

- `Closes #1444` in PR body.
- CLO notified via comment on #1444 linking to `stripe-live-legal-checklist.md`.
- Stripe KYC start date noted in a comment on #1444.
- Dashboard work tracked in #2841 (blocked on #1053), not in this PR.

## Test Strategy

Docs-only PR; no unit/integration tests beyond the regression baseline in AC6. Verification is AC5 (markdownlint) + manual read-through: a reviewer unfamiliar with Stripe should execute the runbook without external doc lookup, or every external link must be explicit.

## Domain Review

**Domains relevant:** Finance, Legal, Operations, Product, Marketing, Sales. All carry forward from brainstorm's `## Domain Assessments` section — no re-review for a docs-only PR. Only CLO has a post-merge action (draft final legal text from `stripe-live-legal-checklist.md`).

**Product/UX Gate:** NONE (no `components/**/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`). Skipped.

## Open Questions

1. **`/pricing` waitlist → checkout CTA swap mechanics.** Is it safe to hard-replace the `<form>` with an anchor, or does the founder want a feature-flag rollback path? Plan defaults to hard-replace as a Phase G runbook step; revisit if rollback optionality is preferred.

Other brainstorm-era open questions (WTP gate 3 threshold, Enterprise quote flow, cancellation policy wording, multi-currency display, dashboard ownership) are deferred to brainstorm follow-ups or #2841 — not plan-level gates.

## Open Code-Review Overlap

Verified at plan time (2026-04-23) per plan skill §1.7.5. Queried 26 open `code-review` issues against every file this plan touches (`pricing-strategy.md`, `stripe-live-activation.md`, `stripe-live-legal-checklist.md`): **no matches**. Three open Stripe code-review issues (#2197, #2195, #2191) target `apps/web-platform/lib/**` and `apps/web-platform/test/**` — explicitly in "Files to Edit" scope fence; orthogonal, **disposition: acknowledge**.

## Non-Goals

- Integration code changes (webhooks, checkout, portal, enforcement) — mature and shipped.
- Readiness dashboard — tracked in #2841, blocked on #1053.
- CLO-approved final legal text — follow-up PR.

## Dependencies

- **#1053** (finance cost model): gate 4 prerequisite for #2841 dashboard. Not a blocker for #1444.
- **#1443** (exit interviews + WTP): gate 3 data source; post-merge handoff.
- **#1439** (recruit 10 founders): upstream of all gates; post-merge handoff.
- **#670** (vendor DPA — closed): covers Stripe as sub-processor.
