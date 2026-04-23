---
category: stripe
tags: [stripe, billing, activation, live-mode, kyc, webhooks, doppler]
date: 2026-04-23
---

# Stripe Live-Mode Activation -- Operator Runbook

Use this runbook once the founder has decided the five pricing gates
have cleared (4 of 5 previously; gate 5 is the live-activation decision
itself) and the business is ready to accept real payments. The
enforcing issue is [Issue #1444](https://github.com/jikig-ai/soleur/issues/1444).

This is a **multi-session runbook**. Stripe KYC (Phase A) runs on
wall-clock days-to-weeks while Stripe reviews business documents --
plan to resume at Phase B once the Stripe dashboard reports the account
as "activated for live payments". Phases B-G are a single sit-down once
KYC clears; Phase H is a break-glass rollback path.

The live flip is intentionally mechanical: all integration code
(webhook handler, checkout, portal, dedup table, enforcement) is
already shipped and exercised in test mode. This runbook only swaps
credentials, price IDs, and the pricing-page CTA.

## Prerequisites

Gather these BEFORE opening the Stripe dashboard -- KYC rejects
halfway-filled applications and resets the 1-2 business-day review
window.

- Legal business entity name, address, and country of registration.
- Business tax ID (EIN for US LLC, SIREN/VAT for EU, company number
  for UK Ltd, etc.).
- Bank account details for payouts (account + routing/IBAN/SWIFT).
- Representative identity documents: passport or government ID for the
  beneficial owner; a utility bill if Stripe requests proof of address.
- A founder-owned email that will own the live Stripe account for the
  life of the company (avoid personal aliases; use a role inbox if one
  exists).
- Doppler CLI auth with write access to config `prd`. Verify by reading
  any existing `prd` secret:

    ```bash
    doppler secrets get STRIPE_SECRET_KEY -p soleur -c prd --plain
    ```

  A non-empty `sk_test_...` value confirms auth and existing test-mode
  state. An auth error aborts the runbook here -- fix Doppler access
  before proceeding.

- Stripe CLI installed for Phase G price-object creation:
  `stripe --version` returns `1.x`. Install:
  <!-- TODO verify install URL before shipping -->
  `https://docs.stripe.com/stripe-cli` (placeholder -- confirm with
  WebFetch before committing).

## Phase A -- KYC (founder, wall-clock days-to-weeks)

This is the only founder-exclusive phase; an operator cannot complete
it on the founder's behalf.

1. Sign in to the Stripe Dashboard using the Prerequisites email.
   Confirm the dashboard is in **test mode** (toggle top-right); KYC
   happens against the one Stripe account, whose live mode is the
   thing being activated.

2. Open **Settings -> Business settings -> Activate account** (or the
   yellow "Activate payments" banner on the dashboard home).

3. Work through each section in order. Stripe rejects partial applies
   ~24h after starting if the representative-identity section is not
   complete -- plan for a single sitting.

   - **Business details:** legal name, address, tax ID, website URL
     (`https://soleur.ai`).
   - **Industry:** Software -- SaaS. The activation form surfaces a
     sub-industry picker; choose the closest match to "developer
     tools" or "business software".
   - **Product description:** 1-2 sentences describing what Soleur
     sells and who pays. Stripe Risk reads this verbatim -- vague
     descriptions ("AI tools") trigger extra review. Concrete: "Soleur
     is a Claude Code plugin and hosted platform for solo software
     founders; customers pay a monthly subscription for concurrency
     and team-size entitlements."
   - **Statement descriptor:** the short string that appears on
     customers' bank/card statements. Use `SOLEUR` (or `SOLEUR.AI` if
     within the 22-char limit). Once set, changes require re-review.
   - **Bank account:** enter payout details from Prerequisites.
   - **Representative identity:** upload passport/government ID for
     the beneficial owner. Stripe Identity runs OCR + liveness; if
     rejected, Stripe emails the reason within 24h.

4. Submit. Stripe returns one of:

   - **Activated:** live-mode toggle in dashboard now enables. Proceed
     to Phase B in a new session.
   - **Pending review:** typically 1-2 business days. Stripe emails
     the outcome.
   - **Additional information requested:** Stripe lists the specific
     docs needed; upload via the dashboard banner.

<!-- TODO verify source: fetch https://docs.stripe.com/get-started/account/activate before ship -->

Record the KYC start date as a comment on Issue #1444. If review
stretches beyond 5 business days, check the dashboard banner and the
founder's email for a document-request notice -- Stripe does not
retry automatically.

Do NOT start Phase B until the dashboard reports the account as
activated.

## Phase B -- Enable Stripe Tax

Stripe Tax must be enabled **before Phase C** so the live price
objects you create inherit `tax_behavior = "exclusive"` (or inclusive,
per the pricing decision) at creation time. Retrofitting tax on
existing price objects requires creating replacement prices.

1. Dashboard -> **Settings -> Tax**. Click "Get started" and set the
   origin address (the business address from Phase A).

2. Registrations. Stripe Tax calculates what it is told you are
   registered to collect. For Soleur's expected geometry:

   - **EU OSS (One-Stop-Shop):** register with your home EU
     member-state tax authority -- this is external to Stripe. Once
     you have the OSS number, add a registration entry in Stripe Tax
     covering all EU destinations under "Union-OSS".
   - **UK VAT:** register with HMRC if projected UK revenue exceeds
     GBP 90,000/year; add to Stripe Tax as "United Kingdom VAT".
   - **US sales tax:** Stripe Tax nexus thresholds are
     state-by-state. Enable the US state(s) where nexus is
     established (typically starts with the state of incorporation).
     Stripe surfaces nexus alerts once transaction volume approaches
     a threshold.

   <!-- TODO verify source: https://docs.stripe.com/tax/registering before ship -->

3. **Fee:** Stripe Tax costs 0.5% per transaction where tax is
   calculated. Budget this into the pricing model; it is on top of
   the standard Stripe processing fee.

4. Confirm Stripe Tax status on the Tax page reads "Active" before
   moving to Phase C.

## Phase C -- Create live-mode price objects

Flip the dashboard to **live mode** (top-right toggle). All commands
below run against the live account; double-check the sidebar footer
shows "LIVE" before each `stripe` CLI call.

The `apps/web-platform/lib/stripe-price-tier-map.ts` module requires
all four `STRIPE_PRICE_ID_*` env vars to resolve at boot
(`loadMap()` throws on any missing key). Enterprise is a placeholder:
the current checkout path in the app routes Enterprise to a
`contact@soleur.ai` mailto flow, not a Stripe Checkout session; the
placeholder price lets `verify-stripe-prices.ts` succeed and the
module cache warm.

Authenticate the Stripe CLI to the live account:

```bash
stripe login
# follow the browser prompt; pair the CLI with the LIVE account.
```

Create the four products and their recurring monthly prices. Prices
are in USD cents (`4900` = $49.00):

```bash
# Solo -- $49/month
SOLO_PROD=$(stripe products create --name "Soleur Solo" --description "Solo-founder plan" --query 'id' --output json | jq -r .)
stripe prices create \
  --product "$SOLO_PROD" \
  --currency usd \
  --unit-amount 4900 \
  -d "recurring[interval]=month" \
  --nickname "Solo monthly"

# Startup -- $149/month
STARTUP_PROD=$(stripe products create --name "Soleur Startup" --description "Startup plan" --query 'id' --output json | jq -r .)
stripe prices create \
  --product "$STARTUP_PROD" \
  --currency usd \
  --unit-amount 14900 \
  -d "recurring[interval]=month" \
  --nickname "Startup monthly"

# Scale -- $499/month
SCALE_PROD=$(stripe products create --name "Soleur Scale" --description "Scale plan" --query 'id' --output json | jq -r .)
stripe prices create \
  --product "$SCALE_PROD" \
  --currency usd \
  --unit-amount 49900 \
  -d "recurring[interval]=month" \
  --nickname "Scale monthly"

# Enterprise -- placeholder $0 (contact-sales mailto flow; see note above)
ENT_PROD=$(stripe products create --name "Soleur Enterprise" --description "Enterprise placeholder -- contact sales" --query 'id' --output json | jq -r .)
stripe prices create \
  --product "$ENT_PROD" \
  --currency usd \
  --unit-amount 0 \
  -d "recurring[interval]=month" \
  --nickname "Enterprise placeholder"
```

Capture each `price_...` ID from the CLI output. These go into
Doppler in Phase E. Record them in the founder's encrypted notes in
case of rollback/re-activation (Phase H).

<!-- TODO verify source: https://docs.stripe.com/cli/prices/create before ship -->

## Phase D -- Register the live webhook endpoint

Still in live mode. Dashboard -> **Developers -> Webhooks -> Add
endpoint**.

- **Endpoint URL:** `https://app.soleur.ai/api/webhooks/stripe`
- **Events to send:** subscribe to EXACTLY these five events. The
  handler at `apps/web-platform/app/api/webhooks/stripe/route.ts`
  ignores anything else, and subscribing to extra events increases
  delivery volume without adding behavior:

  - `checkout.session.completed`
  - `customer.subscription.updated`
  - `customer.subscription.deleted`
  - `invoice.payment_failed`
  - `invoice.paid`

- Click "Add endpoint", then "Reveal" next to the signing secret.
  The secret has form `whsec_...` -- copy it; it will go into
  Doppler as `STRIPE_WEBHOOK_SECRET` in Phase E. It is NOT the same
  as the test-mode webhook secret.

<!-- TODO verify source: https://docs.stripe.com/webhooks before ship -->

## Phase E -- Populate Doppler `prd` secrets

All live Stripe runtime secrets live in Doppler config `prd`, not
`prd_terraform`. Per AGENTS.md `cq-doppler-service-tokens-are-per-config`,
service tokens are per-config; `prd_terraform` scopes the Terraform
runner and will silently ignore app-facing keys.

**Frontend publishable key is NOT needed.** Grep of
`apps/web-platform` at plan time confirmed zero usage of
`NEXT_PUBLIC_STRIPE_*` or `loadStripe()`; the checkout flow redirects
to Stripe's hosted-checkout URL, so only the server-side secret is
required. Do not add `STRIPE_PUBLISHABLE_KEY` to Doppler.

Write the six secrets. Use `--silent` so values do not echo into
captured terminal history:

```bash
# 1. Live secret key (sk_live_...) from Dashboard -> Developers -> API keys (live mode)
doppler secrets set STRIPE_SECRET_KEY -p soleur -c prd --silent

# 2. Live webhook signing secret (whsec_...) from Phase D
doppler secrets set STRIPE_WEBHOOK_SECRET -p soleur -c prd --silent

# 3-6. The four price IDs captured in Phase C
doppler secrets set STRIPE_PRICE_ID_SOLO        -p soleur -c prd --silent
doppler secrets set STRIPE_PRICE_ID_STARTUP     -p soleur -c prd --silent
doppler secrets set STRIPE_PRICE_ID_SCALE       -p soleur -c prd --silent
doppler secrets set STRIPE_PRICE_ID_ENTERPRISE  -p soleur -c prd --silent
```

Each command prompts for the value on stdin; paste and press Ctrl-D.

Verify the write landed on all six keys:

```bash
for k in STRIPE_SECRET_KEY STRIPE_WEBHOOK_SECRET \
         STRIPE_PRICE_ID_SOLO STRIPE_PRICE_ID_STARTUP \
         STRIPE_PRICE_ID_SCALE STRIPE_PRICE_ID_ENTERPRISE; do
  printf '%-30s ' "$k"
  doppler secrets get "$k" -p soleur -c prd --plain | head -c 12
  echo "..."
done
```

Expected: `sk_live_`, `whsec_`, and four `price_` prefixes. Any
`sk_test_` or `whsec_test_` prefix means the write targeted the wrong
config -- retry with `-c prd`.

## Phase F -- Preflight

Run the machine-checkable gate before deploying. This script
dereferences each `STRIPE_PRICE_ID_*` against the live Stripe API --
missing env vars and 404'd price IDs fail loudly:

```bash
cd apps/web-platform
doppler run -p soleur -c prd -- bun run scripts/verify-stripe-prices.ts
```

Expected: exit 0, with four `✓` lines (Solo $49, Startup $149,
Scale $499, Enterprise $0 placeholder).

**This does NOT catch a mismatched `STRIPE_WEBHOOK_SECRET`** --
the script only touches the REST API, not the webhook path. Phase G
step 5 covers that gap with a real webhook-delivery probe.

## Phase G -- Deploy and smoke test

Merge the activation PR (if not already merged) and wait for the
release workflow to deploy the updated Doppler secrets to the live
runtime. Then:

### G.1 -- Create a $0.50/mo test price on the live Solo product

The smoke test runs against a real price so the full invoice chain
fires. **Use $0.50, not $0.** A $0 subscription skips the
`invoice.paid` event, breaking the chain the handler expects (see
webhook route line-by-line: `invoice.paid` restores `past_due`/`unpaid`
back to `active`, and the smoke test validates that path).

```bash
stripe prices create \
  --product "$SOLO_PROD" \
  --currency usd \
  --unit-amount 50 \
  -d "recurring[interval]=month" \
  --nickname "Live smoke-test price (DELETE AFTER)"
# Record the returned price ID as $SMOKE_PRICE.
```

### G.2 -- Run a real checkout from a founder-owned account

- Sign in to `https://app.soleur.ai` with a founder email (not the
  same user that will become the first real paying customer).
- Navigate to the billing/upgrade flow and complete Stripe Checkout
  against `$SMOKE_PRICE`. Use a real card (the $0.50 will be
  refunded in step G.6).
- Confirm Stripe Dashboard -> **Payments** shows a $0.50 succeeded
  charge within ~30 seconds of checkout completion.

### G.3 -- Verify the dedup table recorded the event

The webhook handler uses an insert-first idempotency pattern (see
`knowledge-base/project/learnings/integration-issues/2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md`):
every successfully delivered event creates a row in
`public.processed_stripe_events`.

```bash
export SUPABASE_URL=$(doppler secrets get SUPABASE_URL -p soleur -c prd --plain)
export SUPABASE_SERVICE_ROLE_KEY=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)

curl -sS "$SUPABASE_URL/rest/v1/processed_stripe_events?event_type=eq.checkout.session.completed&order=inserted_at.desc&limit=1" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq .
```

Expected: one row with `event_type = "checkout.session.completed"`
and `inserted_at` within the last 60s. Zero rows means the webhook
did not reach the handler -- skip to G.5's signing-secret check
before continuing.

### G.4 -- Verify the user row flipped

```bash
# <founder-email> is the account used in G.2
curl -sS "$SUPABASE_URL/rest/v1/users?email=eq.<founder-email>&select=subscription_status,plan_tier" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | jq .
```

Expected: `subscription_status = "active"`, `plan_tier = "solo"`.

If `subscription_status` is still `none` despite G.3 showing the
dedup row, the handler returned 5xx on the update -- check Sentry
for `stripe-webhook / op:checkout.session.completed` and see
`knowledge-base/project/learnings/2026-04-13-stripe-status-mapping-check-constraint.md`
for the CHECK-constraint class.

### G.5 -- Webhook-secret smoke test (catches Phase F's gap)

Even with all six secrets written and G.2-G.4 green, a subtly
mismatched `STRIPE_WEBHOOK_SECRET` can still be hiding (e.g., pasted
the test-mode secret into the prod slot). The real webhook in G.2
travelled through the signature path, so it did validate once --
re-confirm explicitly:

- Dashboard -> **Developers -> Webhooks -> [the live endpoint you
  created in Phase D] -> Send test webhook**.
- Pick event type `checkout.session.completed` and click "Send".

Within ~60s, re-run G.3's curl. Expected: a **second**
`processed_stripe_events` row (different `event_id`, the test-webhook
one). If the second row does not appear within 60s, the signing
secret is mismatched -- return to Phase E and re-paste
`STRIPE_WEBHOOK_SECRET` from the Phase D reveal.

### G.6 -- Tear down the smoke-test subscription

- In the app, go to `/dashboard/settings/billing` and cancel the
  subscription (end-of-period is fine; the intent is to stop future
  invoicing).
- Dashboard -> **Payments -> [the $0.50 charge] -> Refund**. Full
  refund, reason "Test charge".
- Dashboard -> **Products -> Soleur Solo -> Prices -> [$SMOKE_PRICE]
  -> Archive**. Archived prices cannot be resurrected; create a new
  smoke price if the runbook re-runs later.

### G.7 -- Swap the `/pricing` CTA from waitlist to checkout

This is the user-visible flip. Edit
`plugins/soleur/docs/pages/pricing.njk` on a follow-up PR: replace
the `<form class="newsletter-form waitlist-form">` block with an
anchor to the checkout route. Minimal shape:

```html
<a class="btn btn-primary" href="/api/checkout?tier=solo">
  Start with Solo - $49/month
</a>
```

After the docs-site deploy lands, confirm the HTML flipped:

```bash
# Either the relative-API link ...
curl -s https://soleur.ai/pricing/ | grep -E '/api/checkout'
# ... or, once a checkout has been initiated, the redirect target
# (Stripe's hosted checkout lives on checkout.stripe.com, NOT stripe.com/checkout):
curl -sIL https://soleur.ai/api/checkout?tier=solo | grep -i 'location:.*checkout.stripe.com'
```

Expected: at least one hit in each check. Zero hits means the build
did not include the CTA swap -- check the deploy workflow.

## Phase H -- Rollback

Rollback reverts the live flip without deleting audit history.
Trigger when: (a) G.3-G.4 failed and the fix is non-obvious, (b)
Sentry shows a spike of `stripe-webhook` errors post-deploy, (c)
real customers cannot check out and the fix-forward path is unclear.

### H.1 -- Revert `STRIPE_SECRET_KEY` AND `STRIPE_WEBHOOK_SECRET` together

Critical: revert **both** in a single logical operation (paste both
writes back-to-back within the same terminal session). A stale
pairing -- live secret key with test webhook secret, or vice versa
-- returns HTTP 400 on every incoming webhook delivery, so Stripe
retries exponentially and the subscription state falls out of sync.

```bash
# Paste the test-mode values (sk_test_..., whsec_test_... from
# pre-activation Doppler backup) into both prompts without pausing.
doppler secrets set STRIPE_SECRET_KEY     -p soleur -c prd --silent
doppler secrets set STRIPE_WEBHOOK_SECRET -p soleur -c prd --silent
```

### H.2 -- Revert all four `STRIPE_PRICE_ID_*` env vars

```bash
doppler secrets set STRIPE_PRICE_ID_SOLO        -p soleur -c prd --silent
doppler secrets set STRIPE_PRICE_ID_STARTUP     -p soleur -c prd --silent
doppler secrets set STRIPE_PRICE_ID_SCALE       -p soleur -c prd --silent
doppler secrets set STRIPE_PRICE_ID_ENTERPRISE  -p soleur -c prd --silent
```

Paste the test-mode price IDs from the pre-activation backup.
**Preserve the live `price_...` IDs from Phase C in an encrypted
note** -- re-activation re-uses them rather than creating a second
set of live products.

### H.3 -- Disable (don't delete) the live webhook endpoint

Dashboard -> **Developers -> Webhooks -> [live endpoint] ->
Disable**. Disabling stops delivery but keeps the endpoint
definition and event history for audit. Do NOT click Delete --
deletion loses the delivery log, which is the only record of
which events fired during the partial activation window.

### H.4 -- Revert the `/pricing` CTA

`git revert` the commit that swapped the waitlist form to the
checkout anchor. The pricing page returns to waitlist capture.

### H.5 -- Document the rollback on Issue #1444

Comment on the issue with: (a) what triggered rollback, (b) which
phase last succeeded (A-G.N), (c) the Sentry / Stripe Dashboard
link that motivated the rollback, (d) the live `price_...` IDs
preserved for re-activation.

## Cross-references

- Insert-first webhook dedup pattern (Phase G.3 relies on this):
  `knowledge-base/project/learnings/integration-issues/2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern.md`
- Stripe status -> DB CHECK constraint mapping (Phase G.4 failure
  class):
  `knowledge-base/project/learnings/2026-04-13-stripe-status-mapping-check-constraint.md`
- Billing review-findings batch fix (context for the webhook
  handler's current shape):
  `knowledge-base/project/learnings/2026-04-13-billing-review-findings-batch-fix.md`
- AGENTS.md rules: `cq-doppler-service-tokens-are-per-config`,
  `hr-menu-option-ack-not-prod-write-auth` (applies to every
  `doppler secrets set -c prd` call in this runbook --
  never pass `--yes`), `cq-docs-cli-verification` (run the
  TODO-verify tags through WebFetch before the runbook ships).
- Activation plan: `knowledge-base/project/plans/2026-04-23-feat-stripe-live-activation-plan.md`
- Enforcing issue: Issue #1444.
