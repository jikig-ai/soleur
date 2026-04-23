# Feature: Stripe Live Mode Activation

Issue: [#1444](https://github.com/jikig-ai/soleur/issues/1444)
Brainstorm: `knowledge-base/project/brainstorms/2026-04-23-stripe-live-mode-activation-brainstorm.md`
Phase: 4 (Validate + Scale)
Trigger: 4 of 5 pricing gates pass (dashboard-verified)

## Problem Statement

Stripe is wired end-to-end in test mode — webhooks, portal, invoice history, tier mapping, concurrency enforcement, and webhook dedup all shipped and hardened through 2026-04-22. However:

1. **No mechanism exists to measure the 5 pricing gates.** Roadmap row 4.10 requires 4/5 to pass before flipping live, but "pass" is undefined in software. Founder judgment alone is not a commitment device against premature monetization.
2. **Pricing documentation contradicts the code.** `pricing-strategy.md` documents 2 tiers ($49 Pro / $99 Team); `stripe-price-tier-map.ts` and `verify-stripe-prices.ts` use 4 tiers (Solo / Startup / Scale / Enterprise). Marketing cannot write the live `/pricing` page against contradictory truth.
3. **Stripe account is pre-KYC.** Business verification, bank, tax ID, and Stripe Tax setup are untouched — this is days-to-weeks of wall-clock work that must begin before any flip is possible.
4. **No runbook exists.** Flipping test→live involves ~15 operator steps across Stripe Dashboard, Doppler, Cloudflare (webhook endpoint), and app config. Without a runbook, the flip is a scratch-built session and error-prone.

## Goals

- Resolve pricing-doc drift: `pricing-strategy.md`, brand guide, `/pricing` page, and homepage all reflect the 4-tier canonical structure encoded in the code.
- Produce an executable activation runbook covering: Stripe KYC, Stripe Tax enablement, live-mode price creation for 4 tiers, production webhook registration, Doppler `prd` secret population, `verify-stripe-prices` preflight, post-activation smoke test, and rollback.
- Define acceptance criteria for the readiness dashboard (deferred to a separate issue).
- Surface legal/compliance requirements (EU 14-day cooling-off, SaaS opt-out consent, ToS update, refund policy) to CLO for resolution before activation.

## Non-Goals

- Building or modifying Stripe integration code. Integration is mature; additional hardening items ship via their own issues.
- Building the readiness dashboard itself. Dashboard is tracked as a separate issue (milestoned Phase 4) that depends on #1053 (finance cost model).
- Changing the 4-tier structure. Tier changes (e.g., adding free cloud tier, shifting to usage-based) are a pricing-strategy revisit, not an activation task.
- Marketing launch campaign. Launch messaging, outbound, and paid activation are CMO scope post-flip.
- Multi-currency display. `/pricing` remains USD; Stripe Tax handles server-side VAT/sales tax.
- Enterprise tier self-service. Enterprise is "contact sales" mailto for MVP.

## Functional Requirements

### FR1: Pricing documentation reconciled to 4 tiers

- `knowledge-base/product/pricing-strategy.md` rewritten to document Solo $49 / Startup $149 / Scale $499 / Enterprise custom, matching `stripe-price-tier-map.ts` and `verify-stripe-prices.ts`.
- Brand guide (`knowledge-base/marketing/brand-guide.md`) and any `/pricing` page source under `apps/docs/` updated to same 4 tiers.
- Homepage hero or any other public surface that mentions tier count or tier names updated.
- `git grep` for "$49/month", "Pro tier", "Team tier" finds zero contradictions.

### FR2: Activation runbook is executable end-to-end

Runbook lives at `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md`. Contains:

- Prerequisites section (KYC complete, bank, tax ID, representative verified).
- Stripe Tax enablement step (dashboard toggle + jurisdiction registration).
- Live-mode price creation commands for all 4 tiers (via Stripe CLI or dashboard with screenshots), including matching product metadata to test-mode.
- Live webhook endpoint registration (production URL, events to subscribe to — mirrors test-mode subscription).
- Doppler `prd` secret population checklist (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID_SOLO`, `_STARTUP`, `_SCALE`, `_ENTERPRISE`).
- Preflight command: `doppler run -p soleur -c prd -- bun run apps/web-platform/scripts/verify-stripe-prices.ts` — must exit 0.
- Post-activation smoke test: create a $0.50 test coupon, run a real checkout, verify webhook processed, invoice appears, subscription cancels cleanly.
- Rollback: swap `STRIPE_SECRET_KEY` back to test-mode, disable live webhook endpoint, document state in incident log.

### FR3: Legal/compliance checklist created

- EU 14-day cooling-off: consent copy at checkout documented for CLO review.
- SaaS digital services opt-out language: documented for checkout flow.
- Terms of Service addendum for live-mode subscriptions drafted for CLO review.
- Cancellation policy: cancel-at-period-end as default (no pro-rata refunds for MVP), documented on `/pricing` and in ToS.

### FR4: Readiness dashboard acceptance criteria captured

Dashboard spec (to ship in a follow-up issue) must define:

- Data source per gate:
  - Gate 1 (demand validation): Supabase query for users with >= 14 days active + non-trivial KB growth.
  - Gate 2 (multi-domain): Supabase query for users with >= 2 non-engineering agent invocations.
  - Gate 3 (WTP): manual counter updated from exit interviews (#1443).
  - Gate 4 (infrastructure cost model): presence-check on finance artifact from #1053.
  - Gate 5 (cowork differentiation): manual counter updated from interview quotes.
- Visualization: single-page `/admin/activation-readiness` (admin-gated) with 5 gate cards, pass/fail per card, overall 4/5 indicator.
- Definition of "pass" per gate: documented threshold (e.g., gate 1 = >= 10 qualifying users).

## Technical Requirements

### TR1: Runbook is version-controlled and CI-verifiable where possible

- Runbook in the repo (`knowledge-base/engineering/ops/runbooks/`), not an external doc.
- The `verify-stripe-prices.ts` command is the machine-checkable preflight; runbook references it as the go/no-go gate before flip.
- Rollback procedure includes specific Doppler secret names and exact CLI commands.

### TR2: Pricing doc reconciliation does not touch runtime code

The reconciliation PR is docs-only. No changes to `stripe-price-tier-map.ts`, `verify-stripe-prices.ts`, migrations, or webhook code. Verified by `git diff --stat` excluding `*.md`, `*.njk`, `*.html`.

### TR3: Stripe Tax is enabled before live price creation

Stripe Tax must be enabled in the Stripe Dashboard before live-mode prices are created, so prices inherit Stripe Tax behavior. Runbook sequences accordingly.

### TR4: Webhook endpoint uses Cloudflare-protected production URL

Production webhook endpoint is behind Cloudflare with same security posture as current test endpoint. No new endpoint path; existing `/api/webhooks/stripe` gets a live-mode subscription registered at Stripe's live dashboard.

### TR5: Secret management follows Doppler per-config convention

`STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` live in Doppler `prd` config. Never committed. CI reads via service token `DOPPLER_TOKEN_PRD` (not bare `DOPPLER_TOKEN`, per `cq-doppler-service-tokens-are-per-config`).

## Acceptance Criteria

1. `pricing-strategy.md` documents 4 tiers matching `stripe-price-tier-map.ts`; no references to "Pro tier" or "Team tier" remain.
2. `/pricing` page renders 4 tiers matching canonical structure.
3. `stripe-live-activation.md` runbook exists, is readable end-to-end, and references `verify-stripe-prices.ts` as the preflight gate.
4. CLO has reviewed and signed off on EU cooling-off / opt-out / ToS addendum language (evidence: commit linking to CLO review or explicit CLO sign-off in PR).
5. Dashboard acceptance criteria documented in this spec (FR4 complete).
6. Dashboard tracked as a separate GitHub issue, milestoned Phase 4, blocked by #1053.
7. Existing Stripe webhook tests remain green (`bun vitest run stripe`).

## Dependencies

- **#1053** — Finance cost model. Gate 4 cannot be measured without this; dashboard is blocked on it.
- **#1443** — Exit interviews + willingness-to-pay. Gate 3 data source.
- **#1439** — Recruit 10 founders. Upstream of all gates.
- **#670** — Vendor DPA (closed). No blocker; DPA already covers Stripe.
- **#1162 / #2617** — Plan-based tier concurrency enforcement (merged). No dependency but tier behavior already enforced in code.

## Out-of-Scope Follow-Ups (New Issues)

- **Readiness dashboard implementation** — separate issue, milestoned Phase 4, depends on #1053. Acceptance criteria per FR4.
- **Enterprise quote flow** — separate issue, milestoned Post-MVP / Later, CRO scope.
- **Pricing page localization** — separate issue, milestoned Post-MVP / Later, CMO scope.
