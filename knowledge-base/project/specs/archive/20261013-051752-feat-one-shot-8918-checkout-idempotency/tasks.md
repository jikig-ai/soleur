---
title: "Tasks — fix(billing): /api/checkout server-side idempotency (#8918)"
plan: knowledge-base/project/plans/2026-09-28-fix-billing-checkout-server-idempotency-plan.md
branch: feat-one-shot-8918-checkout-idempotency
issue: 8918
lane: cross-domain
---

# Tasks — /api/checkout server-side idempotency

Derived from the finalized plan. Order follows the plan's Implementation Phases.

## Phase 1 — Migration

- 1.1 Create `apps/web-platform/supabase/migrations/NNN_pending_checkout_sessions.sql`
  (NNN = next free number at implementation time; `143` was free at plan time —
  re-check `ls apps/web-platform/supabase/migrations/ | sort -n | tail` first):
  - `pending_checkout_sessions(user_id uuid PK REFERENCES public.users(id) ON DELETE CASCADE,
    session_id text, target_tier text, created_at timestamptz NOT NULL DEFAULT now())`
  - `ALTER TABLE … ENABLE ROW LEVEL SECURITY` with zero policies (service-role only)
  - `-- LAWFUL_BASIS: Art. 6(1)(b) contract` header annotation
  - `COMMENT ON TABLE` documenting transient lifecycle (Art. 5(1)(e) retention)
  - No `CONCURRENTLY` / non-transactional DDL (Supabase runner wraps each file
    in a transaction — sibling precedent: migration 030)
- 1.2 Create `apps/web-platform/supabase/migrations/NNN_pending_checkout_sessions.down.sql`
  (drop table; mirrors the recent .sql/.down.sql pair convention)
- 1.3 Create `apps/web-platform/test/supabase-migrations/NNN-pending-checkout-sessions.test.ts`
  asserting: PK on user_id, CASCADE FK, RLS enabled with zero policies, columns
  per spec

## Phase 2 — Route claim + reuse (`app/api/checkout/route.ts`)

- 2.1 Keep existing origin/auth/targetTier/already-subscribed checks unchanged
  and upstream of the claim (error paths must not hold a slot)
- 2.2 Add `getServiceClient()` import; implement claim:
  `INSERT INTO pending_checkout_sessions (user_id, target_tier)` —
  success → own the slot; `PG_UNIQUE_VIOLATION` (`@/lib/postgres-errors`) →
  marker-hit path; other error → Sentry + 500
- 2.3 Own-slot path: `sessions.create(params, { idempotencyKey: randomUUID() })`
  (`node:crypto`), `UPDATE` marker with `session_id`, return `{clientSecret, url}`;
  on Stripe throw → `DELETE` marker → 5xx + Sentry
- 2.4 Marker-hit path (`SELECT` marker):
  - `session_id` present → `sessions.retrieve(session_id)`:
    - `open` + same `target_tier` (null ≡ `"legacy"`) → return that session's
      `client_secret`/`url`
    - `open` + `client_secret` absent → 409 (conservative, no reclaim)
    - `open` + different tier → `sessions.expire(session_id)` → `DELETE`
      marker → retry claim once
    - `complete`/`expired` → `DELETE` marker → retry claim once
    - retrieve throws → Sentry + 500, marker untouched (fail-closed)
  - `session_id` null + `created_at` < 90s →
    `409 { error: "Checkout is already starting — please wait a moment.", code: "checkout_in_progress" }`
  - `session_id` null + `created_at` ≥ 90s → `DELETE` → retry claim once
  - Bounded single retry; the PK arbitrates residual interleavings
- 2.5 `client_secret` is never persisted — reuse re-reads it from retrieve

## Phase 3 — Webhook (`app/api/webhooks/stripe/route.ts`)

- 3.1 In `checkout.session.completed`: `DELETE` from
  `pending_checkout_sessions` where `session_id = session.id`
- 3.2 Double-completion anomaly: `stripe.subscriptions.list({ customer:
  session.customer, status: "active" })` — `> 1` → `logger.warn` +
  `Sentry.captureMessage` (detection only; never auto-cancel)

## Phase 4 — Tests

- 4.1 Update `apps/web-platform/test/api-checkout.test.ts` —
  add `getServiceClient` mock; update `mockCreateSession` call assertions to
  cover the `{ idempotencyKey }` options arg (arg-count-exact matching)
- 4.2 Update `apps/web-platform/test/api-checkout-tiers.test.ts` — same mock +
  options-arg updates
- 4.3 Create `apps/web-platform/test/api-checkout-idempotency.test.ts`:
  - 23505 → retrieve `open` + same tier → same `client_secret` returned,
    `create` called once
  - retrieve `complete`/`expired` → marker DELETEd, re-claim, new session
  - null `session_id` < 90s → 409 + `code: "checkout_in_progress"`, no Stripe call
  - null `session_id` ≥ 90s → reclaim + new session
  - `create` throws after claim → marker DELETEd + 5xx
  - retrieve throws → 500 + Sentry, marker NOT deleted
  - `open` + different tier → `sessions.expire` called → new session created
- 4.4 Update webhook test(s) (closest existing file per implementer) — marker
  DELETE on `checkout.session.completed`; anomaly fires when active-subs
  list > 1 and stays silent on legit plan-switch (single active sub)
- 4.5 Verify: `cd apps/web-platform && ./node_modules/.bin/vitest run`

## Exit

- 5.1 All AC1–AC8 verified; no operator post-merge steps (migration applies via
  `web-platform-release.yml` migrate job before deploy)
