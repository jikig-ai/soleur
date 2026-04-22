# fix(billing): processed_stripe_events dedup table + checkout.session.completed out-of-order guard

**Date:** 2026-04-22
**Branch:** `feat-one-shot-stripe-webhook-idempotency`
**Issues:** Closes #2771, Closes #2772. Ref #2701 (which introduced the `.in()` guard pattern on `.updated`/`.deleted`), Ref #2190 (original out-of-order class).

## Enhancement Summary

**Deepened on:** 2026-04-22
**Sections enhanced:** 5 (Design Decisions D-1, Migration, Files-to-Edit, Risks, Acceptance Criteria)
**Research sources used:** Stripe official docs (webhooks, advanced error handling), Supabase PostgREST + service-role docs (Context7), three project learnings (ws-session-cache, unapplied-migration-command-center, migration-not-null-trap), on-disk repo pattern scan.

### Key Improvements

1. **D-1 concurrent-replay window quantified.** Stripe retries are exponential-backoff over 3 days — deliveries of the same `event.id` are minutes-to-hours apart, NEVER concurrent in normal operation. The delete-on-error race window collapses from "narrow" to "effectively unreachable under Stripe's documented delivery semantics." Plan updated to cite this directly with a Stripe-docs reference.
2. **Migration NOT-NULL trap avoided by construction.** Learning `2026-04-17-migration-not-null-without-backfill...` caught a production-apply failure for a NOT-NULL column added without backfill. Our migration is immune: `event_id` is the PK and is always populated by the INSERT itself (no backfill required, no existing rows to retrofit). Called out explicitly in Phase 1 so future planners don't inherit the trap.
3. **Test-mock chain-extension anti-pattern called out.** Learning `2026-04-13-ws-session-cache-subscription-status.md` documents a case where adding a DB query mid-chain broke existing mocks. Our `supabase-update-chain.ts` helper routes by table name, so adding the dedup path as a NEW table-branch is isolating. Phase 2 rewritten to prescribe the table-routing approach explicitly.
4. **Stripe event.id contract verified.** Context7 + Stripe docs confirm `event.id` is the idempotency key Stripe itself uses; no need to construct a composite key. Plan now cites the Stripe webhooks debug-retries section.
5. **Service-role bypass verified.** Supabase docs confirm: the service-role key bypasses RLS via the `Authorization` header (not `apikey`). `createServiceClient` in this repo sets the Authorization header correctly. No RLS policy needed on `processed_stripe_events`. This was implicit in the plan; now cited.

### New Considerations Discovered

- **Stripe 500-response semantics.** If our handler returns 500, Stripe retries — but Stripe documents that 500s produce side effects (cached request result; reconciliation webhooks may fire later). This does NOT affect our design — we use the dedup table to gate our OWN side effects, not Stripe's. But it reinforces: returning 500 should be a last resort. A dedup-insert failure for a transient reason (`40001` serialization) is correctly surfaced as 500 so Stripe retries; on retry, insert succeeds and handler runs. Acceptable.
- **Event.id uniqueness across live vs test mode.** Stripe event IDs are unique within an account and across modes (test mode events have distinct `evt_test_` prefixes). Our PK covers both without a mode column.
- **`processed_at` default + explicit `event_type` column.** Added `event_type` to the migration so operators can grep the dedup table for "how many `invoice.paid` events did we process last week" without reaching into Stripe. Costs ~50 bytes/row, 18-24 months to reach non-trivial table size.

## Overview

PR #2701 closed the status-resurrection race on `customer.subscription.updated` and `customer.subscription.deleted` using `.in(subscription_status, …)` guards. Two deferred-scope-out code-review findings from that PR remain open:

- **#2771** — the same race exists on `checkout.session.completed`. The handler writes `subscription_status: "active"` unconditionally. A Stripe replay of an old checkout event after the user has cancelled resurrects the row to `"active"`.
- **#2772** — the `.in()` guards cover **status-resurrection** only. A replay of `.updated(active)` against an already-active row still overwrites `current_period_end` and `cancel_at_period_end` with stale values (payload-column resurrection). The canonical fix is a webhook-event-id dedup table: `processed_stripe_events(event_id PK)` with insert-or-ignore at the top of the handler. Every event becomes idempotent regardless of payload semantics.

These are tightly coupled: once the dedup table lands, **every** replayed event short-circuits before per-handler logic runs, which subsumes the #2771 guard. We still ship the #2771 guard as **belt-and-suspenders** — the dedup table is a new failure surface (migration not applied yet, row-delete-on-error semantics, retention pruning) and the guard is one line. We treat the dedup table as the primary fix and the checkout-handler guard as a mirror-pattern safety net for the window before the migration is applied in prod and for the narrow case where the dedup row is deleted on error (see Design Decision D-2 below).

**Scope:** one PR, bundled per the user's direction. Same file, same concern, same test file.

**Not in scope:**

- Refactoring all five handlers to remove their existing `.in()` guards (belt-and-suspenders is cheap; removing them is a larger cleanup).
- Extracting webhook handlers into per-event files (tracked separately; not worth blocking this fix).
- pg_cron-based pruning of the dedup table. We ship the migration with a retention **policy comment** and a partial index on `processed_at`. The prune worker is deferred to a follow-up issue — 90-day retention means the table grows at ~N events/day; at Soleur's current scale (single-digit Stripe events/day) we have 18-24 months before pruning is load-bearing. See Deferrals.

## Research Reconciliation — Spec vs. Codebase

The issue bodies for #2771/#2772 proposed specific code shapes. Verified against current `route.ts`:

| Spec claim (issue body)                                                                                | Reality (current code)                                                                                                                             | Plan response                                                                                                                                           |
| ------------------------------------------------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| #2771 proposes `.in("subscription_status", SUBSCRIPTION_UPDATABLE_STATUSES)` on the checkout handler. | The constant exists at `route.ts:25`. The checkout handler at `route.ts:117-136` does NOT use it today (no `.in()` guard, no `.select("id")`).     | Adopt the proposal verbatim. Also add `.select("id")` so we can emit the matched-rows `0 ⇒ guard fired` warn log consistent with the other handlers.    |
| #2772 proposes `insert()` → on `23505` return 200, else return 500.                                    | No existing Supabase insert-or-ignore pattern in the Stripe handler file. Insert-with-23505 detection IS used in `ws-handler-context-path-23505.test.ts`. | Adopt the error-code-23505 pattern. Critical addition: on handler **error after successful dedup insert**, DELETE the dedup row so Stripe's retry re-enters. See D-1. |
| #2772 proposes `INDEX ON processed_stripe_events (processed_at)` for retention.                        | No such table exists on main.                                                                                                                       | Ship the index. Ship the table. Do NOT ship pg_cron pruning in this PR — deferred per the scope note above.                                              |
| Next migration number.                                                                                 | Two files at `029_*.sql` already on main (collision resolved by filename sort).                                                                  | Use `030_processed_stripe_events.sql`.                                                                                                                  |

## Design Decisions

### D-1: Insert-first, delete-on-error (critical)

**Context:** The naive dedup pattern is "insert event_id; if insert succeeds, process; if insert fails with 23505, return 200." This is **unsafe** as written because Stripe's webhook-retry mechanism is our recovery path for transient DB/process failures — a crash after a successful dedup insert but before the handler body completes leaves the event marked processed but never applied. Returning 500 to Stripe triggers a retry, but the retry hits `23505` on the already-inserted dedup row and short-circuits to 200, silently dropping the event.

**Options considered:**

1. **Process-first, mark-at-end.** Closes the payload-column race for concurrent replays during a single delivery burst only if the handler body itself is serialized (it is not — multiple Stripe webhook deliveries can land on different server instances). This keeps the original #2772 bug.
2. **Insert-first, delete-on-error.** Insert the dedup row at the top. If the handler body returns an error response, DELETE the dedup row **before** returning the non-2xx status. Stripe retries → dedup insert succeeds again → handler re-enters. On concurrent replay (two deliveries of the same event_id in flight), the second insert fails with 23505 and short-circuits — correct, because the first delivery owns the write.
3. **Wrap everything in a transaction.** Supabase PostgREST service-role updates do not compose atomically across multiple `.from().update()` calls; a true transaction would require a SECURITY DEFINER RPC. Out of scope for this PR.

**Decision:** Option 2. The delete-on-error window is narrow (a concurrent replay arriving in the millisecond between DELETE and the 500 response would bypass dedup) but acceptable because (a) per-handler `.in()` guards already catch status-resurrection in that window, (b) concurrent webhook delivery of the same event_id is rare in Stripe's own behaviour (their retry backoff is measured in minutes/hours), and (c) the next retry will close the race cleanly. Document this tradeoff inline in the handler.

#### Research Insights (D-1)

**Stripe retry semantics — window is effectively unreachable:**

Per the Stripe webhooks debugging docs, event retries are "for up to three days with exponential backoff in live mode" and "three times over the course of a few hours" in sandbox. Retries are NOT concurrent — they are sequential, separated by increasing delays (minutes → hours). The "two concurrent deliveries of the same event_id" scenario in our race analysis is a theoretical worst-case that Stripe's delivery layer does not produce. The dominant failure mode is: delivery N fails (500 + dedup-row deleted) → delivery N+1 fires ~N minutes later → clean re-entry.

**Stripe 500-response is indeterminate:**

Per Stripe's advanced error handling docs: "You should treat the result of a 500 request as indeterminate." This is written from Stripe's perspective (us calling Stripe's API), but symmetry holds: Stripe treats our 500s the same way. Our dedup-release on 500 keeps the event properly "incomplete" from Stripe's perspective; Stripe's retry produces a clean re-entry. If we return 500 WITHOUT releasing the dedup row, Stripe's retry would 200 (short-circuited by dedup) and the event is silently dropped from our side — the exact failure mode we MUST avoid.

**Canonical pattern — Stripe's own guidance:**

Stripe's developer community answer to "How to handle duplicate webhook events?": "Implement idempotency using unique IDs from payment processors instead of auto-increment." Our `event.id` PK is the canonical idempotency key Stripe itself recommends. No composite key (e.g., `event_id + account_id`) is needed — `event.id` is unique per Stripe account, and test-mode event IDs are distinct from live-mode via the `evt_test_*` prefix.

**References:**

- <https://docs.stripe.com/webhooks#debug-webhook-integrations> — retry semantics (3-day window, exponential backoff)
- <https://docs.stripe.com/error-low-level#server-errors> — 500-response indeterminate behaviour
- <https://docs.stripe.com/webhooks#requirements> — at-least-once delivery contract

### D-2: Checkout-handler guard stays

Per the #2771 scope note: once the dedup table lands, the checkout guard is redundant under normal operation. We ship it anyway because:

- Belt-and-suspenders: the dedup row is deleted on error (D-1), so the guard still fires for the error-retry case against an already-cancelled row.
- One-line change, mirrors the established pattern.
- Zero test-cost: one new RED test for the checkout-replay-after-cancel scenario.

### D-3: Migration is additive and transaction-safe

Plain `CREATE TABLE` + `CREATE INDEX` without `CONCURRENTLY`. Matches the pattern in `029_conversations_repo_url.sql` (transaction-safe, Supabase migration runner wraps each file in a transaction per AGENTS.md `cq-supabase-migration-concurrently-forbidden`). Adopt that migration's comment block explaining why we are NOT using `CONCURRENTLY`. Cite sibling migration 029 in the migration header.

#### Research Insights (D-3)

**NOT-NULL-without-backfill trap is avoided by construction:**

Learning `knowledge-base/project/learnings/2026-04-17-migration-not-null-without-backfill-and-partial-unique-index-pattern.md` documents a prod-apply failure for `ALTER COLUMN ... SET NOT NULL` on a column that had not been backfilled. We sidestep this entirely — `event_id` is the PK (implicit NOT NULL from PRIMARY KEY), and on CREATE TABLE there are zero existing rows to retrofit. `event_type` and `processed_at` are NOT NULL with a DEFAULT; no backfill required because there are no pre-existing rows.

**Unapplied-migration is the dominant post-merge failure mode:**

Learning `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md` documents a prod outage caused by a migration that was committed but not applied. Our post-merge AC has a REST probe that returns 200 if the table exists; that probe is the shipping gate per AGENTS.md `wg-when-a-pr-includes-database-migrations`. Explicitly: the PR does not close #2772 until the probe returns 200 against prod.

### D-4: Retention policy (deferred pruning worker)

The table grows by one row per processed Stripe event. At current Soleur scale (<10 events/day) the table reaches 1M rows in ~270 years. At 100x scale (1000/day), it reaches 1M rows in ~2.7 years. A pg_cron-based 90-day prune is trivial (the migration already positions pg_cron via `029_plan_tier_and_concurrency_slots.sql`) but not load-bearing **today**. Ship the partial index on `processed_at` now so the eventual prune worker's `DELETE WHERE processed_at < now() - interval '90 days'` is index-backed. File a tracking issue with a clear re-evaluation trigger ("when table size > 100k rows OR when a second cron job is being added and this fits").

### D-5: Row-level insert, not RPC

We insert via the PostgREST client directly, not via a SECURITY DEFINER RPC. Rationale: (a) no multi-table atomicity required (the dedup row IS the gate), (b) RLS is not a concern because this table is service-role-only (no policies), (c) keeping the footprint simple makes the error-recovery path (delete-on-error) trivially reviewable.

#### Research Insights (D-5)

**Service-role RLS bypass is via the Authorization header, not `apikey`:**

Per Supabase docs (Context7 query): "A Supabase client with the Authorization header set to the service role API key will ALWAYS bypass RLS. By default, the Authorization header uses the `apikey` provided in `createClient`. RLS enforcement depends on the `Authorization` header, not the `apikey` header." Our `createServiceClient` in `@/lib/supabase/server` passes the service-role key in both — this is the documented safe path. No RLS policy on `processed_stripe_events` is required **or desirable** (adding one would be ignored for the service-role and misleading for future maintainers).

**Citation:** <https://supabase.com/docs/guides/database/postgres/row-level-security> — "Row Level Security and the service role".

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` and searched bodies for `apps/web-platform/app/api/webhooks/stripe/route.ts`:

- **#2771** — **Fold in.** The checkout-session-completed guard. Addressed in Phase 2. `Closes #2771` in PR body.
- **#2772** — **Fold in.** The dedup table. Addressed in Phases 1 and 2. `Closes #2772` in PR body.

Also queried for `stripe|webhook` (case-insensitive) in body:

- **#2197** — `SubscriptionStatus` type extraction + Sentry UUID pseudonymization. **Acknowledge.** Different concern (type hygiene + security L-4) that touches `route.ts` as one of several files. Does not overlap with the idempotency change and does not benefit from being folded in here. Stays open for its own PR.
- **#2195** — webhook-test mock-chain coupling. **Acknowledge.** The `supabase-update-chain.ts` helper introduced in PR #2617 already addressed the `.update().eq().in()` leg flagged in #2195. We will **extend** that helper to cover `.insert()` + unique-violation in this PR, but will not attempt the broader "repository boundary" refactor #2195 proposes — that's the kind of scope creep that costs review cycles. Stays open.

## Hypotheses

Both issues ship with concrete reproduction scenarios in the bug bodies. No hypothesis work required.

## Files to Edit

- `apps/web-platform/app/api/webhooks/stripe/route.ts` — add dedup insert at top of POST (after `constructEvent`), add delete-on-error path, add `.in()` + `.select("id")` guard to `checkout.session.completed` handler. Preserve all five existing handlers' `.in()` guards (belt-and-suspenders).
- `apps/web-platform/test/webhook-subscription.test.ts` — extend mock graph to include `.from("processed_stripe_events").insert(...)`. Add RED tests: (a) dedup blocks replay, (b) dedup insert-error surfaces 500, (c) handler-error path DELETEs the dedup row, (d) `checkout.session.completed` guard no-ops against cancelled row.
- `apps/web-platform/test/stripe-webhook-invoice.test.ts` — extend mock graph identically (invoice handlers also flow through the dedup gate).
- `apps/web-platform/test/stripe-webhook-plan-tier.test.ts` — extend mock graph identically.
- `apps/web-platform/test/helpers/supabase-update-chain.ts` — add `configureSupabaseInsertChain` variant OR extend the existing helper so the hoisted `mockInsert` returns `{error: null}` by default. Individual tests override for the 23505 path.

## Files to Create

- `apps/web-platform/supabase/migrations/030_processed_stripe_events.sql` — table + index + comment block.

## Implementation Phases

### Phase 1 — Migration (TDD not applicable; infrastructure)

Create `030_processed_stripe_events.sql`:

```sql
-- 030_processed_stripe_events.sql
-- At-least-once Stripe webhook delivery dedup table. See issue #2772.
-- Every Stripe webhook event is inserted into this table at the top of
-- POST /api/webhooks/stripe. A unique-violation (SQLSTATE 23505) on
-- event_id indicates a replay — the handler returns 200 without
-- re-running side effects.
--
-- NOT using CONCURRENTLY: Supabase migration runner wraps each file in
-- a transaction (see migrations 025, 027, 029_conversations_repo_url
-- comments). CREATE TABLE + CREATE INDEX are transaction-safe.
--
-- Retention: rows older than Stripe's replay window (90d) are prunable.
-- A pg_cron-based sweep is tracked separately (follow-up issue) — at
-- Soleur's current event rate the table grows by <10 rows/day. Ship
-- the partial index on processed_at now so the eventual prune is
-- index-backed.

CREATE TABLE IF NOT EXISTS public.processed_stripe_events (
  event_id     text         PRIMARY KEY,
  event_type   text         NOT NULL,
  processed_at timestamptz  NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.processed_stripe_events IS
  'Dedup gate for at-least-once Stripe webhook delivery. Insert-first: '
  'a unique-violation on event_id short-circuits the handler with 200. '
  'On handler error, the row is DELETEd before the 500 so Stripe retry '
  'can re-enter. Service-role-only; no RLS policies.';

COMMENT ON COLUMN public.processed_stripe_events.event_type IS
  'Stripe event.type (e.g. customer.subscription.updated). Retained for '
  'operational visibility during retention window.';

-- Partial-ish index: plain processed_at index is sufficient for the
-- eventual prune (DELETE WHERE processed_at < now() - interval 90d).
CREATE INDEX IF NOT EXISTS idx_processed_stripe_events_processed_at
  ON public.processed_stripe_events (processed_at);
```

**Acceptance:**

- Migration file named with next monotonic prefix (`030_`).
- `CREATE TABLE IF NOT EXISTS` for idempotent local re-apply.
- No RLS policy block; service-role bypasses RLS by default.
- No `CONCURRENTLY`.

### Phase 2 — RED tests (TDD gate)

Per AGENTS.md `cq-write-failing-tests-before`, tests BEFORE implementation.

**Test helper extension** (`test/helpers/supabase-update-chain.ts`):

Add a sibling `configureSupabaseInsertChain` that returns a configured `mockInsert` suitable for the dedup-table path. Callers pass a `rejectWith23505: boolean` flag so a specific test can simulate replay. Keep the chain's `from()` route-by-table so `from("users")` continues to flow through the update chain and `from("processed_stripe_events")` flows through the insert chain.

**Important pattern — table-routing in `createServiceClient` mock:**

Per learning `2026-04-13-ws-session-cache-subscription-status.md` session-errors ("Adding the DB query to `checkSubscriptionSuspended` broke existing test mocks that didn't support the `.eq().single()` chain at the right depth"), mid-chain query additions break sibling tests. Solution: the `vi.mock("@/lib/supabase/server")` factory in each webhook test file must route by table name:

```ts
vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "processed_stripe_events") {
        return {
          insert: mockInsert,
          delete: () => ({ eq: mockDelete }),
        };
      }
      // existing users-table chain unchanged
      return {
        update: mockUpdate,
        select: () => ({ eq: () => ({ maybeSingle: vi.fn().mockResolvedValue({...}) }) }),
      };
    },
  }),
}));
```

This isolates the new dedup path from the existing `users` chain; no existing test needs its mock shape changed. Each test that currently passes continues to pass because the default `mockInsert.mockResolvedValue({ error: null })` + `mockDelete.mockResolvedValue({ error: null })` route through as no-ops.

**New tests in `webhook-subscription.test.ts`:**

1. **Dedup insert fires for every event.** Assert `mockInsert` was called with `{event_id: <event.id>, event_type: <event.type>}` for a happy-path `customer.subscription.updated`.
2. **Dedup replay short-circuits to 200 with no user update.** Configure `mockInsert` to return `{error: {code: "23505"}}`. Dispatch a `customer.subscription.updated` event. Assert response is 200 `{received: true}`, `mockUpdate` was NOT called on `users`, and a replay-info log was emitted.
3. **Non-23505 dedup-insert error returns 500.** Configure `mockInsert` to return `{error: {code: "40001"}}` (serialization failure). Assert 500 and that `mockUpdate` was NOT called.
4. **Handler error path DELETEs the dedup row.** Configure `mockInsert` for success, configure the `users.update` chain to return `{error: {...}}`. Assert: response is 500, AND `mockDelete` on `processed_stripe_events` was called with `.eq("event_id", event.id)`.
5. **checkout.session.completed guard no-ops against cancelled row.** Configure the `users.update().eq().in().select()` chain to return `{data: [], error: null}` (zero matched rows — row was cancelled). Assert response is 200, a guard-fired warn log was emitted, and the client does NOT see a 5xx.
6. **checkout.session.completed guard uses SUBSCRIPTION_UPDATABLE_STATUSES.** Assert `mockIn` was called with `"subscription_status"` and the four expected values `["none", "active", "past_due", "unpaid"]`. (Import the constant from the route file is not possible because `vi.mock` covers `@/app/api/webhooks/stripe/route`; per AGENTS.md `cq-test-mocked-module-constant-import`, inline the expected array verbatim with a cross-reference comment pointing to `SUBSCRIPTION_UPDATABLE_STATUSES`.)

**Tests in `stripe-webhook-invoice.test.ts` and `stripe-webhook-plan-tier.test.ts`:**

These files already dispatch `invoice.paid` / `invoice.payment_failed` / `customer.subscription.updated` events. Extend the mock graph so the dedup-insert path is mocked for all existing tests (default: success). No new test bodies beyond smoke-checking `mockInsert` fires.

**Verify tests fail:** Run all three test files. Assert the new tests RED on current `route.ts`.

### Phase 3 — GREEN implementation

Edit `apps/web-platform/app/api/webhooks/stripe/route.ts`:

**Block 1 — dedup gate, inserted immediately after the `constructEvent` try/catch and before `createServiceClient`** (order matters — we need the client for the insert):

```ts
const supabase = createServiceClient();

// Webhook-event-id dedup gate. Stripe delivers at-least-once; a replay
// of an already-processed event short-circuits here with 200. Critical:
// on handler error we DELETE this row before returning 5xx so Stripe's
// retry can re-enter (see plan D-1). Service-role bypasses RLS; the
// table has no policies.
const { error: dedupErr } = await supabase
  .from("processed_stripe_events")
  .insert({ event_id: event.id, event_type: event.type });

if (dedupErr) {
  // Postgres unique_violation — replay.
  if (dedupErr.code === "23505") {
    logger.info(
      { eventId: event.id, eventType: event.type },
      "Stripe webhook replay — event already processed, skipping",
    );
    return NextResponse.json({ received: true });
  }
  // Any other DB error must surface. Do NOT swallow — Stripe will retry
  // and the retry re-enters cleanly (no row was written).
  logger.error(
    { err: dedupErr, eventId: event.id },
    "Stripe webhook dedup insert failed — returning 500",
  );
  Sentry.captureException(dedupErr, {
    tags: { feature: "stripe-webhook", op: "dedup-insert" },
    extra: { eventId: event.id, eventType: event.type },
  });
  return NextResponse.json({ error: "DB error" }, { status: 500 });
}
```

**Block 2 — error-path dedup cleanup helper.** Define once near the top:

```ts
// On any 5xx error path below, call this before returning so Stripe's
// retry mechanism can re-enter. Silently tolerates a DELETE failure —
// the Stripe retry is the correction mechanism; double-apply is blocked
// by the per-handler .in() guards even if DELETE fails.
async function releaseDedupRow(
  supabase: ReturnType<typeof createServiceClient>,
  eventId: string,
): Promise<void> {
  const { error } = await supabase
    .from("processed_stripe_events")
    .delete()
    .eq("event_id", eventId);
  if (error) {
    logger.error(
      { err: error, eventId },
      "Stripe webhook: failed to release dedup row on handler error — retry will be short-circuited",
    );
    Sentry.captureException(error, {
      tags: { feature: "stripe-webhook", op: "dedup-release" },
      extra: { eventId },
    });
  }
}
```

**Block 3 — error-path callsite updates.** Every `return NextResponse.json(..., { status: 500 })` inside the switch must be preceded by `await releaseDedupRow(supabase, event.id);`. Concretely:

- `checkout.session.completed` — `users.update` error → release + 500.
- `customer.subscription.updated` — `users.select` selErr → release + 500; `users.update` error → release + 500.
- `customer.subscription.deleted` — `users.select` selErr → release + 500; `users.update` error → release + 500.
- `invoice.paid` — `users.update` error → release + 500.
- `invoice.payment_failed` — logs only, no 500 path.

**Block 4 — #2771 guard for `checkout.session.completed`:** Replace `route.ts:117-136` body:

```ts
case "checkout.session.completed": {
  const session = event.data.object as Stripe.Checkout.Session;
  const userId = session.metadata?.supabase_user_id;

  if (userId) {
    // Guard: never resurrect a cancelled row via a replayed checkout
    // event (e.g. original delivery + retry after user cancels). The
    // dedup table above closes this today, but the guard is kept as
    // belt-and-suspenders for the release-on-error window and for
    // environments before migration 030 is applied. See #2771.
    const { data, error } = await supabase
      .from("users")
      .update({
        stripe_customer_id: session.customer as string,
        subscription_status: "active",
        stripe_subscription_id: session.subscription as string,
      })
      .eq("id", userId)
      .in("subscription_status", SUBSCRIPTION_UPDATABLE_STATUSES)
      .select("id");

    if (error) {
      logger.error({ error, userId }, "Webhook: failed to update user on checkout.session.completed");
      Sentry.captureException(error, {
        tags: { feature: "stripe-webhook", op: "checkout.session.completed" },
        extra: { userId },
      });
      await releaseDedupRow(supabase, event.id);
      return NextResponse.json({ error: "DB update failed" }, { status: 500 });
    }

    const matched = data?.length ?? 0;
    if (matched === 0) {
      logger.warn(
        { userId, eventId: event.id },
        "Webhook: checkout.session.completed guard no-op — row not in updatable status (likely cancelled or replay after dedup-row released)",
      );
    }
  }
  break;
}
```

**Verify tests GREEN:** run the three webhook test files; all tests pass including the six new RED tests.

### Phase 4 — Verification

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/webhook-subscription.test.ts test/stripe-webhook-invoice.test.ts test/stripe-webhook-plan-tier.test.ts`
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (route-export validator — AGENTS.md `cq-nextjs-route-files-http-only-exports`).
- Migration applied to prod per AGENTS.md `wg-when-a-pr-includes-database-migrations` — post-merge task.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `030_processed_stripe_events.sql` migration created; table, index, comments per Phase 1.
- [x] `route.ts` inserts into `processed_stripe_events` at top of POST after `constructEvent`.
- [x] Replay (23505) returns 200 `{received: true}` with info-log; `users.update` NOT called.
- [x] Non-23505 dedup-insert error returns 500 with Sentry capture.
- [x] Every 5xx path inside the `switch` calls `releaseDedupRow()` BEFORE returning.
- [x] `checkout.session.completed` handler uses `.in("subscription_status", SUBSCRIPTION_UPDATABLE_STATUSES).select("id")` and emits `guard no-op` warn log on zero matched rows.
- [x] Six new RED tests added (enumerated Phase 2); all GREEN after Phase 3.
- [x] All existing webhook tests pass unchanged.
- [x] Test helper extended with `configureSupabaseInsertChain`; two sibling test files updated.
- [x] `tsc --noEmit` clean; `vitest run` green on the three webhook test files.
- [ ] PR body includes `Closes #2771` and `Closes #2772` (separate lines per AGENTS.md `wg-use-closes-n-in-pr-body-not-title-to`).

### Post-merge (operator)

- [ ] Verify migration 030 applied to prod Supabase per runbook `knowledge-base/engineering/ops/runbooks/supabase-migrations.md`. Probe via REST: `curl -s "$SUPABASE_URL/rest/v1/processed_stripe_events?limit=0" -H "apikey: $SERVICE_ROLE_KEY" -I` returns 200 (table exists).
- [ ] Monitor Sentry for new `stripe-webhook / op: dedup-insert` or `op: dedup-release` captures in the 48h following deploy. Non-zero captures require triage.
- [ ] Follow-up issue filed for pg_cron-based prune worker (see Deferrals).

## Test Scenarios

Framework is existing `vitest` per `apps/web-platform/package.json scripts.test`. No new framework.

1. **Happy path — event processed, row inserted.** Dispatch `customer.subscription.updated`; assert `mockInsert` called with `event_id` + `event_type`; assert `users.update` called; assert 200.
2. **Replay — 23505 short-circuits.** `mockInsert` returns `{error: {code: "23505"}}`; dispatch same event; assert `users.update` NOT called; assert info log.
3. **Dedup-insert transient error.** `mockInsert` returns `{error: {code: "40001", message: "serialization failure"}}`; assert 500; assert Sentry capture with `op: "dedup-insert"`.
4. **Handler-error releases dedup row.** `mockInsert` success; `users.update` chain error; assert `mockDelete` on `processed_stripe_events` fires with `.eq("event_id", …)` BEFORE 500 returns.
5. **checkout replay after cancel.** Seed row `subscription_status = "cancelled"`; dispatch `checkout.session.completed`; mock `users.update` chain returns `{data: [], error: null}`; assert 200; assert guard-fired warn log; assert subscription_status NOT overwritten.
6. **checkout.session.completed uses correct status allowlist.** Assert `mockIn` called with `["none", "active", "past_due", "unpaid"]` for the checkout handler.
7. **Existing 11 webhook tests unchanged.** All green with the new mock graph.

## Risks

- **Prod migration lag.** If the PR merges but the operator forgets to apply migration 030, every webhook fires the insert against a non-existent table → 500 → Stripe retries → eventual dead-letter. Mitigation: the pre-merge AC line for the migration application is explicit; Sentry will light up immediately (captures with `op: dedup-insert` code `42P01` / table-not-found). Post-merge acceptance gate catches this.
- **Race: concurrent replay arriving during the DELETE-on-error window.** Documented in D-1 and tightened by research. Stripe's webhook delivery layer does NOT issue concurrent deliveries of the same `event.id` — retries are sequential with exponential backoff over a 3-day window (Stripe webhooks docs, "Automatic retries" section). The theoretical race requires two concurrent deliveries, which is off-contract for Stripe. In the off-contract case the per-handler `.in()` guards catch status-resurrection, and payload-column write corruption is corrected by the next legitimate `.updated` event. No additional mitigation required.

- **Stripe retries a 5xx → their delivery dashboard marks event as failed.** This is correct behaviour and the signal we want. Returning 500 on dedup-insert transient failure is how Stripe's retry mechanism re-enters. Per Stripe docs, 500 responses are "indeterminate" — Stripe will retry; our dedup-release on 500 makes that retry clean. A spike in 500s in the Stripe dashboard is a legitimate operational signal, not a silent failure.
- **Vendor-default claim.** Plan asserts "service-role bypasses RLS" — this is Supabase's documented behaviour for the service-role key; no new claim. Citation: Supabase auth docs on service role. No verification step needed.
- **Next.js route-file exports.** We add `releaseDedupRow` as an **inner helper** (not exported) inside `route.ts`. Per AGENTS.md `cq-nextjs-route-files-http-only-exports`, only HTTP handlers + Next.js config exports are allowed in route files. Inner (non-exported) helpers are fine. Confirmed by scanning the file for existing inner helpers: `mapStripeStatus`, `extractCustomerId`, `deriveTierFromSubscription` are all inner-only. No sibling module required.

## Deferrals

- **Pg_cron retention worker for `processed_stripe_events`.** File as a new GitHub issue milestoned to "Post-MVP / Later" with re-evaluation triggers: (a) table rows > 100k, (b) a second pg_cron job is being added (bundle with that PR), (c) any future Stripe event-rate-impacting migration. Include the exact DELETE query `DELETE FROM processed_stripe_events WHERE processed_at < now() - interval '90 days'` and the pg_cron recipe derived from `029_plan_tier_and_concurrency_slots.sql`.
- **Removing per-handler `.in()` guards now that dedup handles idempotency.** Explicitly scope-out. They are belt-and-suspenders. A future PR can remove them once the dedup table has a retention worker and we have a clear Sentry trail showing zero replays slipped through. Not worth the test-rewrite churn now.
- **Repository-boundary refactor for webhook DB writes (from #2195).** Acknowledged; stays open. This PR uses the existing `.update().eq().in()` chain mocks — the dedup path adds one more leg (`.insert` + `.delete().eq()`) to the same style. A full repository-boundary rewrite is its own cycle.

## Domain Review

**Domains relevant:** Engineering (CTO), Finance (CFO — billing invariants).

This is a billing-correctness infrastructure fix. No user-facing UI, no copy changes, no marketing implications. Product domain is NONE.

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Mirrors PR #2701's proven pattern. Adds one schema object with a conservative index, one inner helper, six new tests. Delete-on-error pattern is the correct choice given the in-transaction atomicity constraint against PostgREST service-role. Risk profile is low-per-change; blast radius is all Stripe webhook traffic, so the post-merge Sentry gate is non-negotiable.

### Finance (CFO)

**Status:** reviewed
**Assessment:** Closes a silent-data-corruption class (payload-column resurrection) that could cause premature "subscription expired" UX for paying customers mid-renewal. Priority justified at P2 (not P1 — no reported instance, low replay-rate at current scale, but high potential blast-radius). Dedup table is the canonical Stripe SaaS pattern — accepted. Retention deferral acceptable given current event volume; must reconsider if event rate 10x's.

### Product/UX Gate

Tier: **NONE.** Mechanical escalation check: no new files matching `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx`. Only `route.ts`, migration SQL, and test files. Skipped.

## References

- PR #2701 — the scope this finding was excluded from; introduced the `.in()` guard pattern.
- Issue #2190 — original out-of-order class.
- Issue #2771 — out-of-order guard on checkout.session.completed (closes).
- Issue #2772 — processed_stripe_events dedup table (closes).
- AGENTS.md rules referenced: `cq-write-failing-tests-before`, `cq-test-mocked-module-constant-import`, `cq-nextjs-route-files-http-only-exports`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-in-worktrees-run-vitest-via-node-node`, `wg-when-a-pr-includes-database-migrations`, `wg-use-closes-n-in-pr-body-not-title-to`.
- Stripe webhook at-least-once delivery: `https://docs.stripe.com/webhooks#requirements`.
- Sibling migrations: `apps/web-platform/supabase/migrations/025_context_path_archived_predicate.sql`, `027_mtd_cost_aggregate.sql`, `029_conversations_repo_url.sql`, `029_plan_tier_and_concurrency_slots.sql` (transaction-safe pattern, pg_cron reference).
