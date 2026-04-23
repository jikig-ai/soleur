# Tasks: Stripe Live Mode Activation

Plan: `knowledge-base/project/plans/2026-04-23-feat-stripe-live-activation-plan.md`
Spec: `knowledge-base/project/specs/feat-stripe-live-activation/spec.md`
Issue: [#1444](https://github.com/jikig-ai/soleur/issues/1444) | Draft PR: #2836

## Phase 1: Preflight

- [ ] 1.1 Read current `knowledge-base/product/pricing-strategy.md` and identify exact hunk line ranges (expect lines 17, 25, 121-126, 127-133, 188, 215).
- [ ] 1.2 Read `knowledge-base/engineering/ops/runbooks/supabase-migrations.md` to confirm runbook template structure.
- [ ] 1.3 Read `apps/web-platform/lib/stripe-price-tier-map.ts` to confirm the 4 tier IDs, concurrency limits, and Enterprise handling.
- [ ] 1.4 Re-grep `apps/web-platform/` for `STRIPE_PUBLISHABLE_KEY` / `NEXT_PUBLIC_STRIPE*` to reconfirm it is not needed.
- [ ] 1.5 Re-run the code-review overlap query (plan §Open Code-Review Overlap). If any new `code-review` labeled issue now touches the planned file paths, update plan disposition before proceeding.
- [ ] 1.6 Read `plugins/soleur/docs/pages/pricing.njk` around the waitlist form to confirm the CTA swap target for runbook Phase G (waitlist form → `/api/checkout?tier=solo` anchor).
- [ ] 1.7 WebFetch and pin three Stripe docs URLs for runbook annotations (per `cq-docs-cli-verification`): live-mode activation checklist, Stripe Tax setup, webhook endpoint creation. Annotate each cited URL in the runbook with `<!-- verified: YYYY-MM-DD source: <url> -->`.

## Phase 2: Runbook

- [ ] 2.1 Create `knowledge-base/engineering/ops/runbooks/stripe-live-activation.md` mirroring the `supabase-migrations.md` section structure.
- [ ] 2.2 Phase A (KYC): document founder dashboard walkthrough + rejection-appeal pointer.
- [ ] 2.3 Phase B (Stripe Tax): dashboard toggle, EU OSS / UK / US nexus registration with external links, 0.5%/tx fee note.
- [ ] 2.4 Phase C (price objects): `stripe prices create` invocations for Solo (4900), Startup (14900), Scale (49900), Enterprise placeholder (see plan §C). Verify against `stripe-price-tier-map.ts`.
- [ ] 2.5 Phase D (webhook endpoint): live URL `https://app.soleur.ai/api/webhooks/stripe` + the exact 5 events the handler supports (`checkout.session.completed`, `customer.subscription.updated`, `customer.subscription.deleted`, `invoice.payment_failed`, `invoice.paid`) and signing-secret capture.
- [ ] 2.6 Phase E (Doppler `prd`): exact `doppler secrets set` invocations for `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `STRIPE_PRICE_ID_SOLO|STARTUP|SCALE|ENTERPRISE`. Explicit "not needed" note for `STRIPE_PUBLISHABLE_KEY`. Note `prd` config scope (not `prd_terraform`) per `cq-doppler-service-tokens-are-per-config`.
- [ ] 2.7 Phase F (preflight): `doppler run -p soleur -c prd -- bun run apps/web-platform/scripts/verify-stripe-prices.ts`. Explicit note that this does NOT catch a mismatched webhook signing secret.
- [ ] 2.8 Phase G (deploy + smoke): all 7 sub-steps from plan — create $0.50 test price (NOT $0), real checkout, verify `processed_stripe_events` + `public.users` rows, Dashboard "Send test webhook" as webhook-secret smoke test, cancel + refund + archive, `/pricing` CTA swap with `curl | grep checkout.stripe.com` verification.
- [ ] 2.9 Phase H (rollback): simultaneous revert of `STRIPE_SECRET_KEY` + `STRIPE_WEBHOOK_SECRET` (same `doppler secrets set` transaction, call out pairing explicitly), `STRIPE_PRICE_ID_*` revert, disable-not-delete live webhook, CTA revert, `#1444` comment.
- [ ] 2.10 Cross-refs: `2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md` (full path), `2026-04-13-stripe-status-mapping-check-constraint.md`, `2026-04-13-billing-review-findings-batch-fix.md`.
- [ ] 2.11 `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/stripe-live-activation.md` → exit 0.

## Phase 3: pricing-strategy.md reconciliation

- [ ] 3.1 Edit `knowledge-base/product/pricing-strategy.md` Tier Structure table (lines 121-126): 2 rows → 4 rows (Solo/Startup/Scale/Enterprise), concurrency numbers sourced from `stripe-price-tier-map.ts`.
- [ ] 3.2 Add 1 paragraph to "Why $49/month" section explaining Startup/Scale pricing anchored to concurrency/team-size cohorts (not new market anchors).
- [ ] 3.3 Replace prose occurrences: line 25 ("Pro tier infrastructure" → "hosted-platform infrastructure"), line 188 (Mitigation column "Pro tier" → "Solo tier"), line 215 ("Pro tier" → "Solo tier").
- [ ] 3.4 Update Status block (line 17): change "Pricing is undecided" framing → "4-tier structure canonical; activation gated on pricing gates" with back-reference to #1444.
- [ ] 3.5 Run broadened grep: `rg -n "Pro tier|Team tier|Pro plan|Team plan|\\$99(/month| per month|/mo\\b| ?)" knowledge-base/product/pricing-strategy.md` → zero hits.
- [ ] 3.6 `npx markdownlint-cli2 --fix knowledge-base/product/pricing-strategy.md` → exit 0.

## Phase 4: Legal brief

- [ ] 4.1 Create `knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md` with 6 sections per plan Phase 3.
- [ ] 4.2 Section 1: EU 14-day cooling-off + SaaS digital-services opt-out consent wording proposal (draft checkout-copy text for CLO review).
- [ ] 4.3 Section 2: refund/cancellation policy — propose cancel-at-period-end, no pro-rata refunds for MVP, refund-request escalation to Stripe Dashboard.
- [ ] 4.4 Section 3: ToS subscription addendum brief (billing cycle, price changes, tax, data retention on cancellation).
- [ ] 4.5 Section 4: AUP/Privacy sub-processor confirmation (Stripe DPA covered by #670).
- [ ] 4.6 Section 5: Stripe Atlas alignment note (cross-ref `2026-02-25-stripe-atlas-legal-benchmark-mismatch.md`).
- [ ] 4.7 Section 6: explicit CLO sign-off line as final gate ("reviewed by CLO on YYYY-MM-DD").
- [ ] 4.8 `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md` → exit 0.

## Phase 5: Verification + Ship

- [ ] 5.1 AC5 verify: `npx markdownlint-cli2 knowledge-base/product/pricing-strategy.md knowledge-base/engineering/ops/runbooks/stripe-live-activation.md knowledge-base/engineering/ops/runbooks/stripe-live-legal-checklist.md` → exit 0.
- [ ] 5.2 AC6 verify: `cd apps/web-platform && ./node_modules/.bin/vitest run stripe` → exit 0 (regression baseline).
- [ ] 5.3 AC3 verify: re-run broadened grep from task 3.5 → zero hits.
- [ ] 5.4 AC4 verify: `git diff --stat main` shows only `*.md` files changed (no `.ts`, `.tsx`, `.sql`, `.njk`).
- [ ] 5.5 Update PR #2836 body: `Closes #1444` in body (not title per `wg-use-closes-n-in-pr-body-not-title-to`); reference `Ref #2841`; add post-merge handoff checklist.
- [ ] 5.6 Post-merge handoff (NOT a PR gate): comment on #1444 with (a) link to `stripe-live-legal-checklist.md` for CLO, (b) KYC start date line for the founder.
- [ ] 5.7 `/ship` skill runs compound + review + merge flow.
