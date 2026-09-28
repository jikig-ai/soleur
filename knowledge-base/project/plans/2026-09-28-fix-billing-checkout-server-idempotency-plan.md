---
title: "fix(billing): /api/checkout lacks server-side idempotency — double-subscribe TOCTOU"
type: fix
date: 2026-09-28
slug: fix-billing-checkout-server-idempotency
branch: feat-one-shot-8918-checkout-idempotency
issue: 8918
closes: 8918
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(billing): /api/checkout lacks server-side idempotency — double-subscribe TOCTOU

## Enhancement Summary

**Deepened on:** 2026-09-28
**Sections enhanced:** Proposed Solution (marker-hit decision tree), Acceptance
Criteria (AC5b/AC5c), Dependencies & Risks (deploy ordering, FK lock), plus
`## Downtime & Cutover` added.
**Research agents used:** in-process sequential pass — plan-review panel lenses
(DHH/simplicity, Kieran/correctness, architecture-strategist, spec-flow,
CPO/CTO named-panel) run by the orchestrating subagent; `Reviewed-Coverage:
sequential-fallback` — no independent subagent review was spawned (no Task
surface in this pipeline context). External evidence: Stripe API reference +
onetimesecret PR #3690 (deterministic-key failure modes).

### Key Improvements (deepen pass)

1. Marker-hit tree gained two correctness arms found by the in-process review:
   `open`-but-different-tier reclaims via `sessions.expire` instead of reusing a
   wrong-price session, and retrieve-failure is fail-closed (marker kept — a
   transient Stripe outage must not unlock a second session).
2. Double-completion anomaly now asserts the real invariant
   (`subscriptions.list({customer, status:"active"})` count > 1) — the first
   draft's subscription-id-mismatch proxy would false-alarm on every legitimate
   plan-switch checkout.
3. 409 body carries human-readable `error` plus machine `code` —
   `billing-section.tsx` renders `data.error` verbatim, so a snake_case slug
   would reach users.

### New Considerations Discovered

- Stripe `checkout.sessions.expire` / `retrieve` / `subscriptions.list` verified
  against installed `stripe@^17.7.0` type defs (`SessionsResource.d.ts:2924`,
  `Sessions.d.ts:80` `client_secret: string | null`, `:277` status enum).
- `CREATE TABLE … REFERENCES users(id)` takes a brief ShareRowExclusive lock on
  the hot `users` table — evaluated under `## Downtime & Cutover` (sub-second
  on a new empty table; NOT VALID dance unnecessary).
- Cited issues verified live: #2046 CLOSED, #2772 CLOSED, #2036 MERGED, #8904
  MERGED; `web-platform-release.yml` runs `migrate` + `verify-migrations`
  before `deploy`.

## Overview

`POST /api/checkout` creates a Stripe checkout session on every call with no
server-side deduplication. The existing "already subscribed" guard
(`apps/web-platform/app/api/checkout/route.ts:53-60`) reads
`subscription_status` and then creates a session as two non-atomic steps, so two
near-simultaneous POSTs both pass the guard and produce two checkout sessions —
and, worst case, two live Stripe subscriptions on one customer. The webhook
dedup table (`processed_stripe_events`, migration 030) deduplicates webhook
*events*, not checkout *sessions*, so it cannot collapse the race. This plan
adds a Postgres-claimed pending-checkout marker — one open checkout session per
user — plus open-session reuse on marker-hit, closing the race at the same layer
that already deduplicates webhook events.

The client-side pending latch shipped in PR #8904 (`feat-ui-action-feedback`,
merged 2026-09-28) reduces the click-level window but cannot close it: double
tabs, cross-render clicks, and direct API calls still reach the route
concurrently. The issue's re-evaluation criterion (a) — "fix when the
ui-action-feedback PR merges" — is met.

## Problem Statement / Motivation

A user double-clicking Subscribe (or clicking in two tabs) before the pending
state lands can be presented with two concurrent checkout sessions. If both
complete, two `checkout.session.completed` events fire with distinct event ids,
both pass the `SUBSCRIPTION_UPDATABLE_STATUSES` guard (`active` is updatable),
and the second overwrites `users.stripe_subscription_id` — leaving **two live
Stripe subscriptions** while the DB row shows only the later one. That is a
real-money single-user incident: the user is double-charged until someone
notices and refunds.

This is the unresolved residue of #2046 (learning
`2026-04-13-billing-review-findings-batch-fix.md`): the fix shipped then was
migration 021's partial unique index on `users(stripe_subscription_id)`, which
enforces cross-*user* subscription-id uniqueness — it does nothing to stop one
customer from holding two different subscriptions.

## Proposed Solution

Insert-first dedup at the checkout layer, mirroring the `processed_stripe_events`
precedent (migration 030 / #2772): a `pending_checkout_sessions` table keyed on
`user_id` is the atomic serialization point. Postgres's primary-key constraint
is the only lock that survives Vercel's per-invocation concurrency model —
any in-process or read-then-write guard is the TOCTOU this plan exists to
remove.

Route flow (`app/api/checkout/route.ts`, after the existing
origin/auth/tier/already-subscribed checks):

1. `INSERT INTO pending_checkout_sessions (user_id, target_tier)` via
   `getServiceClient()` (service-role-only table, RLS enabled zero policies —
   same posture as migration 030).
   - **Insert succeeds** → this request owns the slot. Call
     `stripe.checkout.sessions.create(params, { idempotencyKey:
     crypto.randomUUID() })`, then `UPDATE` the marker with `session_id`, then
     return `{ clientSecret, url }`. On Stripe failure, `DELETE` the marker
     before returning 5xx (mirrors `releaseDedupRow()` in the webhook route) so
     a retry re-enters cleanly.
   - **23505 conflict** → a marker exists. `SELECT` it:
     - `session_id` present → `stripe.checkout.sessions.retrieve(session_id)`:
       - `open` AND `target_tier` on the marker equals this request's tier
         (legacy `null` ≡ `"legacy"`) → return that session's
         `client_secret`/`url` (second POST joins the same session instead of
         erroring). If `status: open` but `client_secret` is absent, respond
         `409` — conservative: do not reclaim a session Stripe reports open.
       - `open` AND a **different** tier → the pending session is stale-for-
         purpose (a wrong-price reuse is worse than no reuse): call
         `stripe.checkout.sessions.expire(session_id)`, `DELETE` the marker,
         and retry the claim once.
       - `complete`/`expired` → `DELETE` the marker and retry the claim once.
       - Retrieve **throws** → fail-closed: `logger.error` + Sentry, return
         500, and do NOT delete the marker — reclaiming on a transient Stripe
         outage would let a second session coexist with the open first, the
         exact defect being fixed.
     - `session_id` null and `created_at` < 90s old → a sibling request is
       mid-`create`; return
       `409 { error: "Checkout is already starting — please wait a moment.", code: "checkout_in_progress" }`
       (the body text is user-visible via `billing-section.tsx`'s `data.error`
       render path — snake_case must not reach it).
     - `session_id` null and `created_at` ≥ 90s old → crashed-claim residue;
       `DELETE` and retry once.
   - Claim/reclaim is a bounded single retry — the PK constraint arbitrates any
     residual interleaving; a loser simply re-enters the marker-hit path.
2. `client_secret` is **never persisted** — the marker stores only `session_id`;
   the reuse path re-reads `client_secret` and `status` from Stripe's retrieve,
   which is also the authoritative staleness check (no TTL guesswork for the
   common case).
3. Webhook (`app/api/webhooks/stripe/route.ts`,
   `checkout.session.completed` block): `DELETE FROM pending_checkout_sessions
   WHERE session_id = <session.id>` for hygiene (mirrored on
   `checkout.session.expired`), plus a **double-completion
   anomaly check** that asserts the *invariant*, not a proxy: a legitimate
   plan-switch checkout also produces `session.subscription ≠
   row.stripe_subscription_id` on an `active` row, so subscription-id mismatch
   alone would false-alarm on every upgrade. Instead call
   `stripe.subscriptions.list({ customer, status: "active", limit: 100 })` —
   **two active subscriptions whose `created` timestamps are within
   `DOUBLE_COMPLETION_PROXIMITY_MS` (15 min)** is the race signature —
   `logger.warn` + `Sentry.captureMessage` (detection, never auto-cancel on a
   money path). Legit upgrade pairs are created days/months apart and stay
   silent.

## Technical Considerations

- **Atomicity boundary:** Postgres PK on `pending_checkout_sessions.user_id`
  serializes concurrent claims across lambda invocations; Stripe `status` on
  retrieve serializes reuse-vs-reclaim decisions. No application-level check is
  load-bearing for safety.
- **Reuse UX:** a racing second POST returns the *same* session's client_secret
  (embedded-checkout mounts converge on one session) rather than an error —
  better than a bare 409 for the double-tab case.
- **`idempotencyKey` posture:** fresh UUID per attempt (belt for SDK-level
  retries / network blips), never a deterministic `user_id+tier` key — Stripe
  replays the cached first response for a repeated key, which onetimesecret
  PR #3690 documents as serving stale/completed sessions and throwing
  `IdempotencyError` on param drift.
- **NFR:** +1 small Postgres insert per checkout POST (p99 sub-ms at our scale),
  +1 Stripe `sessions.retrieve` only on the race path. No new dependencies.
- **Security:** `client_secret` is a bearer capability — kept out of at-rest
  storage; the table is service-role-only behind `getServiceClient()`.

## User-Brand Impact

- **If this lands broken, the user experiences:** two concurrent Stripe checkout
  sessions from double-click/double-tab Subscribe, worst case two live
  subscriptions and duplicate monthly charges on `billing-section.tsx` →
  `/api/checkout`.
- **If this leaks, the user's money is exposed via:** duplicate subscription
  charges created by a second `checkout.session.completed` overwriting
  `users.stripe_subscription_id` while both Stripe subscriptions stay live.
- **Brand-survival threshold:** `single-user incident`

**Residual modes this diff introduces (review-surfaced, mitigations noted):**

- *Availability widening (accepted):* every new DB/Stripe call is a new 500 on
  checkout — degraded Supabase ⇒ degraded checkout. The trade is deliberate
  (fail-closed prevents double-charges) and the migrate→verify→deploy chain
  keeps the code-before-table window closed.
- *Webhook-lag re-checkout:* a `complete` Stripe session reclaimed before the
  `checkout.session.completed` webhook flips `subscription_status` could mint a
  second completable session — mitigated by `FRESH_COMPLETION_MS` (15 min):
  fresh completions return 409 `checkout_completed` instead of reclaiming.
  Residual: a marker already deleted by the webhook re-enters via the
  active-subscription guard (legacy path); the targetTier path is upgrade-by-
  design and covered by the anomaly probe.
- *Modal 409 copy:* `upgrade-at-capacity-modal.tsx` previously discarded the
  409 body and Sentry-warned on every `!res.ok` — now renders `body.error` and
  suppresses the warn on the expected-race 409.
- *Cross-tab tier ping-pong (latent):* different-tier POSTs expire each
  other's open session — bounded to one open session per user; no client
  mounts embedded sessions today so the dying-form artifact is theoretical.
- *Cutover seam (latent, bounded):* sessions created pre-deploy carry no
  marker; a post-deploy POST mints a second session — bounded by Stripe's
  ≤24h embedded-session TTL and by the fact no client can complete embedded
  sessions yet.
- *Previously-silent failure now visible (favorable):* an authenticated user
  with no `public.users` row previously could pay and never activate (the
  webhook's users update matched 0 rows); the claim INSERT now fails closed
  with FK 23503 → 500, no charge.

Per plan Phase 2.6 Step 3: `requires_cpo_signoff: true` is set in frontmatter.
CPO-scope assessment was performed in-process during the domain sweep (see
`## Domain Review` — this session runs as a Task subagent with no spawn
surface, `Reviewed-Coverage: sequential-fallback`). At review time
`soleur:engineering:review:user-impact-reviewer` runs per the review skill's
conditional-agent block.

## Research Insights

**Relevant file paths:**

- `apps/web-platform/app/api/checkout/route.ts` — the route; guard at :53-60,
  `sessions.create` at :107-116 (no idempotency options arg today).
- `apps/web-platform/app/api/webhooks/stripe/route.ts` — dedup insert at
  :118-139, `releaseDedupRow()` at :145-160, `checkout.session.completed` at
  :163-209.
- `apps/web-platform/supabase/migrations/030_processed_stripe_events.sql` —
  insert-first dedup precedent (service-role-only, RLS zero policies).
- `apps/web-platform/supabase/migrations/021_unique_stripe_subscription.sql` —
  prior fix (#2046): partial unique index on `stripe_subscription_id`.
- `apps/web-platform/lib/stripe-subscription-statuses.ts` — `active` is in
  `SUBSCRIPTION_UPDATABLE_STATUSES`, so a second completed session overwrites.
- `apps/web-platform/lib/postgres-errors.ts` — `PG_UNIQUE_VIOLATION = "23505"`.
- `apps/web-platform/lib/supabase/server.ts` — exports `getServiceClient`
  (re-export from `./service`); the webhook already uses it.
- `apps/web-platform/components/settings/billing-section.tsx:75-106` —
  `usePendingAction` latch shipped in PR #8904 (client-side mitigation only).
- `apps/web-platform/test/api-checkout.test.ts`, `api-checkout-tiers.test.ts` —
  existing vitest coverage; mocks will need a `getServiceClient` entry.

**Institutional learnings:**

- `2026-04-13-billing-review-findings-batch-fix.md` — this exact race was filed
  as #2046; its fix (unique index on `stripe_subscription_id`) protects a
  different invariant. The learning's own prevention line names the remedy:
  "Enforce partial unique indexes or idempotency keys for payment-related
  writes."
- `2026-03-20-websocket-first-message-auth-toctou-race.md` — analogous TOCTOU
  pattern cross-reference (read-then-act on shared state is never safe).
- `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr` —
  webhook-side marker cleanup must ship wired in this PR, not deferred.

**External research:**

- Stripe `checkout.sessions.create` accepts `idempotencyKey` in request options
  (Stripe API reference, `stripe@^17.7.0` SDK). onetimesecret PR #3690 documents
  the deterministic-key failure modes (stale cached sessions, param-mismatch
  `IdempotencyError`) and concludes fresh UUID keys are correct for session
  creation — adopted here.

**Related issues/PRs:** #8918 (this fix), #2046 + PR #2036 (prior partial fix),
#2772 + migration 030 (dedup precedent), PR #8904 (client-side latch, merged
2026-09-28 — re-evaluation criterion met).

**Premise Validation (Phase 0.6):** Issue #8918 verified OPEN. `route.ts`
exists and matches the issue's citations (guard :53-60, unkeyed `create` :107).
`processed_stripe_events` confirmed to dedupe events only. Re-evaluation
criterion (a) confirmed met: PR #8904 merged. Prior fix (#2046/migration 021)
verified present and confirmed to guard a different invariant — premise "the
race is real" holds; nothing was stale. ADR corpus grep on the mechanism
keywords (idempotency, checkout) returned no rejecting ADR; ADR-037-style
composite dedup is the established house pattern this fix mirrors.

**Property List (Phase 0.6b):**

1. Two concurrent POSTs by one user can never yield two open checkout sessions
   (atomic serialization point required — Postgres unique constraint).
2. A second POST while a session is open returns a usable response — reuse the
   existing session's client_secret, not a dead end.
3. Self-healing: crashed claims, expired sessions, and completed sessions must
   not wedge the user out of future checkouts.
4. SDK/network-level retries of `sessions.create` must not double-create.

**Cut List (Phase 0.6b):**

- Deterministic `user_id+tier` idempotency key → property 1 only within Stripe's
  key-retention window, with documented stale-cache/param-mismatch failures
  (onetimesecret #3690); superseded by the DB claim. Retained solely as a
  fresh-UUID per-attempt key for property 4.
- `checkout.sessions.list`-then-create reuse → property 2 without property 1
  (the list→create gap is itself a TOCTOU); superseded by marker+retrieve.
- `pg_advisory_lock` RPC → same property 1 via a SECURITY DEFINER surface
  (`cq-pg-security-definer-search-path-pin-pg-temp` review burden) with no gain
  over a PK claim → cut.
- Client-side disabled-during-pending → already shipped (PR #8904); existing
  mechanism covers the click-level slice only.
- Webhook auto-cancel of a second subscription → auto-mutation on the money
  path is riskier than the anomaly it repairs; replaced by a Sentry anomaly
  alert (detection, not remediation).

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| "Fix-Size: 120 lines / 3 files" | Correct fix needs a migration pair, route change, webhook cleanup, and test updates across ≥4 files (~200 lines incl. tests) | Plan enumerates the real file set; size drift noted, not silently absorbed |
| "no idempotency key or session reuse" on `create` | Confirmed — `route.ts:107-116` calls `create` with params only | Add both claim-based reuse and a per-attempt UUID key |
| Webhook dedup dedupes "events, not sessions" | Confirmed — and additionally, a second `checkout.session.completed` *overwrites* `stripe_subscription_id` because `active` ∈ `SUBSCRIPTION_UPDATABLE_STATUSES` | Webhook gains marker cleanup + double-completion anomaly alert |

## Open Code-Review Overlap

None — queried open `code-review`-labeled issues on 2026-09-28 for
`app/api/checkout/route.ts`, `app/api/webhooks/stripe/route.ts`,
`api-checkout.test.ts`, `api-checkout-tiers.test.ts`, `pending_checkout_sessions`:
zero matches.

## Implementation Phases

### Phase 1: Migration

Create `apps/web-platform/supabase/migrations/143_pending_checkout_sessions.sql`
(number provisional — take next free at implementation time) **and**
`143_pending_checkout_sessions.down.sql` (the recent-migration convention):

```sql
-- LAWFUL_BASIS: Art. 6(1)(b) contract — pending-checkout linkage is necessary
-- to provision the subscription the user initiated.
CREATE TABLE IF NOT EXISTS public.pending_checkout_sessions (
  user_id     uuid        PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  session_id  text,
  target_tier text,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.pending_checkout_sessions ENABLE ROW LEVEL SECURITY; -- zero policies: service-role only
COMMENT ON TABLE public.pending_checkout_sessions IS
  'One-pending-checkout-per-user claim (#8918). Transient: DELETEd on
   checkout.session.completed, reclaimed on expired/stale markers; Art. 5(1)(e)
   retention = session lifecycle, no long-term retention.';
```

`ON DELETE CASCADE` on the `user_id` FK satisfies the Art. 17 erasure path.

### Phase 2: Route claim + reuse

`app/api/checkout/route.ts`: claim→create→record→return, marker-hit→
retrieve→reuse-or-reclaim, release-on-error — per Proposed Solution. Keep the
existing origin/auth/tier/already-subscribed checks unchanged and upstream of
the claim so error paths don't hold a slot. Wire `PG_UNIQUE_VIOLATION` from
`@/lib/postgres-errors` and `Sentry.captureException` on unexpected claim
failures (per `cq-silent-fallback-must-mirror-to-sentry`).

### Phase 3: Webhook cleanup + anomaly

`app/api/webhooks/stripe/route.ts`: inside `checkout.session.completed`,
`DELETE` the marker by `session_id` (and likewise on
`checkout.session.expired`); before the existing users update, log +
`Sentry.captureMessage` when `subscriptions.list` shows ≥2 active subs
created <15 min apart (`DOUBLE_COMPLETION_PROXIMITY_MS`).

### Phase 4: Tests

Update `test/api-checkout.test.ts` + `test/api-checkout-tiers.test.ts` (add
`getServiceClient` mock; assert the `{ idempotencyKey }` options arg —
`toHaveBeenCalledWith` arg-count exactness means the new second arg must be
asserted, not ignored). New `test/api-checkout-idempotency.test.ts` for the
race paths; new `test/supabase-migrations/143-pending-checkout-sessions.test.ts`
per the `test/supabase-migrations/` convention.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Deterministic `user_id+tier` idempotency key on `create` | Stripe replays the cached first response within key retention — serves stale/completed sessions and throws on param drift (onetimesecret #3690); does not span past retention |
| `sessions.list({status:'open'})` then reuse | List→create gap is itself the TOCTOU; no serialization point |
| `pg_advisory_lock` via RPC | Adds a SECURITY DEFINER surface for the same property a PK constraint gives for free |
| Unique index on `users` checkout columns | Pollutes the hot `users` row; service-role table matches the 030 precedent and keeps `client_secret`-adjacent data off the authenticated-GRANT surface entirely |
| Client-side pending latch only | Already shipped (PR #8904); cannot cover double-tab/cross-render/direct-API |

## Files to Create

- `apps/web-platform/supabase/migrations/143_pending_checkout_sessions.sql` (number provisional)
- `apps/web-platform/supabase/migrations/143_pending_checkout_sessions.down.sql`
- `apps/web-platform/test/api-checkout-idempotency.test.ts`
- `apps/web-platform/test/supabase-migrations/143-pending-checkout-sessions.test.ts`

## Files to Edit

- `apps/web-platform/app/api/checkout/route.ts`
- `apps/web-platform/app/api/webhooks/stripe/route.ts`
- `apps/web-platform/test/api-checkout.test.ts`
- `apps/web-platform/test/api-checkout-tiers.test.ts`

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed; no
`specs/feat-one-shot-8918-checkout-idempotency/spec.md` exists — one-shot
entry).

## Observability

```yaml
liveness_signal:
  what: "POST /api/checkout auth-gate liveness — unauthenticated POST returns 401"
  cadence: "on-demand (preflight Check 10 probe)"
  alert_target: "Sentry web-platform (captureException/captureMessage on claim/retrieve/create failures)"
  configured_in: "apps/web-platform/app/api/checkout/route.ts (Sentry import + reportSilentFallback); apps/web-platform/server/observability.ts"
error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN; pino logger via @/server/logger"
  fail_loud: "HTTP 5xx on claim/retrieve/create failure + Sentry event tagged feature:checkout"
failure_modes:
  - mode: "pending-marker INSERT fails (non-23505)"
    detection: "Sentry captureException tagged op:claim-insert + 500 to client"
    alert_route: "Sentry issue → ops"
  - mode: "Stripe create throws after claim won"
    detection: "Sentry captureException + marker row DELETEd (release path); log line 'checkout create failed — marker released'"
    alert_route: "Sentry issue → ops"
  - mode: "double checkout completion (two live subs)"
    detection: "Sentry captureMessage 'checkout multiple-active-subscriptions anomaly' when ≥2 active subs on one customer are created <15 min apart"
    alert_route: "Sentry issue → ops (manual refund/cancel — never auto-mutated)"
  - mode: "wedged marker (session_id null > 90s)"
    detection: "reclaim path executes; logger.warn on reclaim of stale marker"
    alert_route: "log volume spike visible in web-platform log stream"
logs:
  where: "pino logger (@/server/logger) → web-platform log sink; Sentry events tagged feature:checkout, feature:stripe-webhook"
  retention: "per existing Sentry/log-sink retention"
discoverability_test:
  command: curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST -H "Origin: https://app.soleur.ai" https://app.soleur.ai/api/checkout
  expected_output: "401"
```

## Encryption Posture

```yaml
at_rest:
  - store: "supabase.prd — public.pending_checkout_sessions (same Postgres cluster as processed_stripe_events)"
    mechanism: "provider-managed:Supabase disk-level encryption at rest"
    evidence: "Supabase Security attestation — 'All databases are encrypted at rest' (https://supabase.com/security, retrieved 2026-09-28)"
    defends_against: "raw disk/snapshot exfiltration of the checkout-claim rows"
    does_not_defend: "leaked service-role key, RLS misconfig, SQLi — mitigated by zero-policy RLS + service-role-only access path, not by at-rest encryption"
    disclosed_as: "knowledge-base/legal/article-30-register.md billing processing entry; same store class as processed_stripe_events (migration 030)"
    live_verification: "unavailable:provider-managed attestation, no customer-facing toggle"
in_transit:
  - connection: "web-platform -> Supabase Postgres (marker INSERT/SELECT/UPDATE/DELETE)"
    enforced_at: "apps/web-platform/lib/supabase/service.ts (getServiceClient — supabase-js HTTPS client)"
    tls: "HTTPS/TLS via supabase-js"
    cert_verification: "on"
    does_not_defend: "service-key theft — key is a bearer credential by design"
    disclosed_as: "not-publicly-claimed"
  - connection: "web-platform -> Stripe API (sessions.create / sessions.retrieve)"
    enforced_at: "apps/web-platform/lib/stripe.ts (stripe-node HTTPS client)"
    tls: "HTTPS/TLS via stripe-node"
    cert_verification: "on"
    does_not_defend: "STRIPE_SECRET_KEY theft"
    disclosed_as: "not-publicly-claimed"
```

## Downtime & Cutover

**Offline-inducing operation:** the only lock-taking DDL is
`CREATE TABLE … REFERENCES public.users(id)` — Postgres takes a
ShareRowExclusive lock on the referenced `users` table for the duration of the
constraint check. On a brand-new empty table the check is sub-second; the lock
window is bounded by statement time, not data size. No table-rewriting DDL, no
non-CONCURRENTLY index, no `ADD CONSTRAINT` on an existing hot table, no
backfill — the migration is `CREATE TABLE` + `ENABLE RLS` + `COMMENT` +
`DROP` (down), all transaction-safe under the Supabase runner (sibling
precedent: migration 030's header comment).

**Zero-downtime evaluation:** default satisfied — the change is additive.
Expand-contract is unnecessary (new table, no existing-column change); a
`NOT VALID` FK + later `VALIDATE` would matter only if the new table were
pre-populated, which it is not. The FK's brief referenced-table lock is the
only residual; at Soleur's `users` write rate it is unmeasurable. Route code
ships after the migration lands (`web-platform-release.yml` orders `migrate` +
`verify-migrations` before `deploy`), so there is no window where the code
references a missing table on the normal path — a rollback that inverts the
order fails closed (claim insert errors → 500 + Sentry).

## Domain Review

**Domains relevant:** engineering, legal (assessed in-process — this session is
a one-shot Task subagent with no subagent spawn surface; `Reviewed-Coverage:
sequential-fallback`, never claimed as independent leader review)

### Engineering

**Status:** reviewed (in-process)
**Assessment:** Concurrency primitive choice is the only architecture-shaped
decision: a Postgres-PK claim mirrors the proven `processed_stripe_events`
precedent instead of inventing a third dedup mechanism. New table is additive;
no ownership/tenancy boundary moves; no ADR warranted — the pattern is already
the recorded house pattern (migration 030 comments, #2772). Risks: wedged
markers (mitigated by retrieve-status + 90s null-marker reclaim), and
second-arg `idempotencyKey` breaking arg-count-exact test assertions (covered
in Phase 4).

### Legal

**Status:** reviewed (in-process)
**Assessment:** Regulated-data surfaces touched (`app/api/**` route + a new
migration with a `users` FK). GDPR gate ran per Phase 2.7 — findings baked into
the migration spec: `ON DELETE CASCADE` (Art. 17), `-- LAWFUL_BASIS:` contract
annotation (Art. 6), retention lifecycle in table COMMENT (Art. 5(1)(e)). No
Art. 9 columns; no new vendor/env var (Chapter V silent). Table stores
`user_id` + Stripe `session_id` only — `client_secret` deliberately not
persisted (data-minimization, Art. 5(1)(c)).

### Product/UX Gate

**Tier:** none — Files to Create/Edit are backend-only (`app/api/**`,
`supabase/migrations/**`, `test/**`); the ui-surface glob superset matches
nothing and backend work is on the exclusion list. The new `409
checkout_in_progress` response reuses the existing error surface in
`billing-section.tsx` — no new copy string lands in components (the fetch error
path renders `data.error`, which is server text on an existing surface).

## GDPR Gate (Phase 2.7 findings)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

| `check_id` | Severity | Disposition |
|---|---|---|
| `GDPR-Art-6` | Important | Resolved in plan — migration carries `-- LAWFUL_BASIS: Art. 6(1)(b)` header |
| `GDPR-Art-5e` | Important | Resolved in plan — transient-table lifecycle + retention documented in `COMMENT ON TABLE` |
| `GDPR-Art-17` | Important | Resolved in plan — `user_id` FK declared `ON DELETE CASCADE` |
| `GDPR-Art-17-caller` | — | N/A (CASCADE, not RESTRICT; no anonymise RPC) |
| `GDPR-Chapter-V` | — | N/A (no new vendor env var/SDK — Stripe is an existing processor) |
| `GDPR-Art-9` | — | N/A (no special-category columns) |

## Acceptance Criteria

- [x] AC1: Migration `NNN_pending_checkout_sessions.sql` + `.down.sql` create/drop the table with PK on `user_id`, `ON DELETE CASCADE` FK, RLS enabled with zero policies, LAWFUL_BASIS annotation, and a migration test under `test/supabase-migrations/`.
- [x] AC2: Two sequential POSTs with a live marker return the SAME checkout session — the second response's `client_secret`/`url` belongs to the session created by the first (covered by a vitest case simulating the 23505 → retrieve → open path).
- [x] AC3: A marker-hit where retrieve reports `complete` or `expired` deletes the marker, re-claims, and creates a NEW session (vitest case).
- [x] AC4: A null-`session_id` marker younger than 90s returns `409` with a human-readable `error` string plus `code: "checkout_in_progress"`; older than 90s it is reclaimed (vitest cases).
- [x] AC5: Stripe `create` failure after a won claim deletes the marker before the 5xx (vitest case asserting the DELETE was issued).
- [x] AC5b: A marker-hit whose `sessions.retrieve` throws returns 500 + Sentry and does NOT delete the marker (vitest case — fail-closed on transient Stripe outage).
- [x] AC5c: A marker-hit on an `open` session for a DIFFERENT `target_tier` calls `sessions.expire`, deletes the marker, and creates a new session for the requested tier (vitest case — never reuse a wrong-price session).
- [x] AC6: `sessions.create` is called with a fresh `idempotencyKey` string in the options arg (asserted in updated `api-checkout*.test.ts`).
- [x] AC7: Webhook `checkout.session.completed` deletes the matching marker row, and when `stripe.subscriptions.list({customer, status:"active"})` returns >1 it logs + captures a Sentry anomaly message (test update — asserts the live-subscription invariant, not a subscription-id mismatch proxy that legit plan-switches would trip).
- [x] AC8: `cd apps/web-platform && ./node_modules/.bin/vitest run` passes with no regressions in `api-checkout.test.ts` / `api-checkout-tiers.test.ts` / webhook tests (vitest is the sole runner — `bunfig.toml` sets `pathIgnorePatterns = ["**"]` so `bun test` discovers nothing).

## Test Scenarios

- Given two interleaved POSTs where the first claims the marker, when the second POST inserts and hits 23505, then it retrieves the first session, finds `status: open`, and returns that session's `client_secret` — `sessions.create` was called exactly once.
- Given a marker whose session is `expired` in Stripe, when the POST runs, then the marker is deleted, a fresh claim succeeds, and a new session is created.
- Given a marker with `session_id: null` created 5s ago, when a POST arrives, then response is 409 `checkout_in_progress` and no Stripe call is made.
- Given `sessions.create` rejects, when the route returns 5xx, then a `DELETE` on `pending_checkout_sessions` was issued for that `user_id`.
- Given an authenticated user already `active` without `targetTier`, when POST runs, then the existing 400 "Already subscribed" path still short-circuits before any marker write.
- **API verify:** `curl -s -o /dev/null -w "%{http_code}" --max-time 10 -X POST -H "Origin: https://app.soleur.ai" https://app.soleur.ai/api/checkout` expects `401` (auth gate alive — also the Observability probe).

## Success Metrics

- A second concurrent POST can never reach `sessions.create` while a sibling
  claim is in flight or an open session exists — enforced by PK + code path,
  asserted by the vitest interleaving case.
- Zero `checkout multiple-active-subscriptions anomaly` Sentry events post-deploy.
- `pending_checkout_sessions` stays near-empty (rows only while a session is
  open); no wedged markers blocking repeat checkouts.

## Dependencies & Risks

- **Migration ordinality:** `143` is provisional; a sibling PR can claim it —
  renumber both `.sql` and `.down.sql` plus the test filename at work time.
- **Deploy ordering:** `web-platform-release.yml` runs `migrate` +
  `verify-migrations` before `deploy` in the same pipeline (verified), so the
  table exists before the route code ships. A rollback ordering it backwards
  degrades to claim-insert failures → 500 + Sentry — fail-closed, loud.
- **Precedent-diff (Phase 4.4):** the claim mechanism follows the repo's
  canonical insert-first dedup — `processed_stripe_events` (migration 030:
  service-role-only table, RLS enabled zero policies, PK-claim insert, unique
  violation short-circuit, delete-on-error via `releaseDedupRow()` at
  `webhooks/stripe/route.ts:145-160`). This plan's `pending_checkout_sessions`
  differs by design in exactly two places, both deliberate: the claim is
  *owned* (the winner must UPDATE the row with `session_id` — 030 rows are
  write-once tombstones) and the row is *reclaimable* (030 rows persist for
  the retention window; pending rows are deleted on completion/reclaim). No
  other precedent-bearing surface is touched.
- **Vercel/dev parity:** dev and prd are distinct Supabase projects
  (`hr-dev-prd-distinct-supabase-projects`); verify the migration applied in
  both before exercising the race end-to-end.
- **Webhook `checkout.session.expired`:** not currently in the handler's event
  set — reclaim relies on retrieve-status (authoritative), so the missing event
  is not load-bearing; adding the event to the Stripe endpoint is optional
  hygiene and deliberately NOT a plan dependency.
- **Risk — retrieve latency on race path:** one extra Stripe call only when a
  marker exists; bounded, off the hot path.
- **Risk — embedded checkout with a reused client_secret across tabs:** both
  mounts converge on one Stripe session; completion still single-fires
  `checkout.session.completed` (deduped by event id anyway).

## References & Research

- Issue: #8918 (this fix); prior partial fix #2046 / PR #2036 / migration 021;
  dedup precedent #2772 / migration 030; client-side latch PR #8904.
- Code: `apps/web-platform/app/api/checkout/route.ts:46-60,107-116`;
  `app/api/webhooks/stripe/route.ts:118-209`;
  `supabase/migrations/030_processed_stripe_events.sql`;
  `lib/postgres-errors.ts`; `lib/stripe-subscription-statuses.ts`.
- Learning: `knowledge-base/project/learnings/2026-04-13-billing-review-findings-batch-fix.md`.
- External: Stripe API reference — Create a Checkout Session (idempotency
  request-options support); onetimesecret PR #3690 (deterministic-key failure
  modes → fresh UUID keys).
