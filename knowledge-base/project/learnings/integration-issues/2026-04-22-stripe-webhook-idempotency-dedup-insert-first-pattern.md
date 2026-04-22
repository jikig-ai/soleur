---
title: Stripe webhook idempotency via processed_stripe_events — insert-first-with-delete-on-error pattern
date: 2026-04-22
category: integration-issues
tags: [stripe, webhooks, idempotency, at-least-once, supabase, postgres, 23505, test-mocks]
symptoms:
  - payload columns overwritten by replayed webhook events
  - checkout.session.completed resurrecting cancelled rows
  - replay-safety limited to status field only, not arbitrary payload
module: apps/web-platform/app/api/webhooks/stripe
problem_type: integration_issue
severity: medium
synced_to: []
---

# Stripe webhook idempotency via processed_stripe_events

## Problem

PR #2701 closed the status-resurrection race on `customer.subscription.updated`
and `customer.subscription.deleted` via per-handler `.in(subscription_status,
[...])` guards. Two gaps remained:

- `checkout.session.completed` wrote `subscription_status: "active"` unconditionally
  (#2771). A Stripe replay after user cancellation resurrected the row.
- The `.in()` guards blocked **status** resurrection only. A replayed
  `customer.subscription.updated(active)` against an already-active row still
  overwrote `current_period_end` and `cancel_at_period_end` with stale values
  (#2772 — **payload-column resurrection**).

Stripe delivers webhooks at-least-once. Without a dedup gate, any event column
that a handler writes is a resurrection surface.

## Solution

**Migration 030** (`apps/web-platform/supabase/migrations/030_processed_stripe_events.sql`):
transaction-safe CREATE TABLE with `event_id text PRIMARY KEY`, `event_type text`,
`processed_at timestamptz DEFAULT now()`, plus `ENABLE ROW LEVEL SECURITY` with
zero policies (service-role bypasses RLS; defense-in-depth denies
anon/authenticated by default).

**Handler** (`apps/web-platform/app/api/webhooks/stripe/route.ts`):

1. Immediately after `constructEvent`, INSERT into `processed_stripe_events`
   with `{event_id, event_type}`.
2. On SQLSTATE `23505` (unique_violation): replay detected; short-circuit 200
   without re-running side effects.
3. On any other DB error: return 500. Stripe retries; no row was written, so
   the retry re-enters cleanly.
4. Define an inner `releaseDedupRow()` that DELETEs the row. Call it before
   every 5xx exit in the switch — this lets Stripe's retry re-enter on
   handler error. Silently tolerate DELETE failure (Stripe outer retry is
   the correction mechanism; per-handler `.in()` guards block double-apply).
5. Add `.in("subscription_status", SUBSCRIPTION_UPDATABLE_STATUSES).select("id")`
   to `checkout.session.completed` (#2771). Emits a `guard no-op` warn log on
   zero matched rows. Belt-and-suspenders with the dedup table.

**Test mocks:** Route `vi.mock("@/lib/supabase/server")` factory's `from()` by
table name so the dedup `insert`/`delete().eq()` chain is isolated from the
users-table `.update().eq().in().select()` chain. Without this, any test that
exercises the POST handler hits `processed_stripe_events` first and breaks
regardless of which handler it targets.

**Constants as non-mocked modules:** Extract `SUBSCRIPTION_UPDATABLE_STATUSES`
to `@/lib/stripe-subscription-statuses` and `PG_UNIQUE_VIOLATION` to
`@/lib/postgres-errors`. Tests import these directly instead of verbatim-copying
(the route module is fully `vi.mock()`'d, so importing from the route file
resolves to `undefined` per AGENTS.md `cq-test-mocked-module-constant-import`).

## Key Insight

**Insert-first-with-delete-on-error trades a narrow crash-window for
Stripe-retry-safe idempotency.** If the Node process dies between the INSERT
commit and the handler's 5xx response, the row is orphaned — Stripe's retry
23505-short-circuits and the event is lost (operator-replayable from the
Stripe dashboard). At Soleur's current scale (<10 events/day, handler p99
sub-second), this is <1 event/year and operationally recoverable. Alternatives
considered and deferred to follow-up #2789:

- **Commit-last.** INSERT after handler success. Breaks #2772's payload-column
  fix — replays re-run the full handler before seeing the dedup row.
- **TTL-reclaimable.** Add `state text` column; treat stale `in_progress` rows
  as reclaimable. Higher complexity, true crash-safety.
- **SECURITY DEFINER RPC transaction.** Wrap dedup INSERT + handler UPDATEs
  in a single Postgres function. Highest durability, highest complexity; per-
  event-type RPCs required.

**`event.id` is the canonical idempotency key** Stripe itself recommends for
dedup tables. No composite key is needed — `event.id` is unique per Stripe
account, and `evt_test_*` prefixes distinguish test from live mode.

**Test mocks must route `from()` by table name** whenever a handler gains a
new table interaction mid-flow. A single-table mock factory silently breaks
every sibling test the moment a second `.from()` call is added. Cheap
mitigation: the factory branches on `table === "<name>"`.

## Session Errors

- **Vitest ran from wrong CWD.** Attempted `./node_modules/.bin/vitest run`
  from the worktree root — the binary only exists under
  `apps/web-platform/node_modules/.bin/`. **Recovery:** Prefixed the call with
  `cd <abs-path-to-app> &&`. **Prevention:** Already covered by AGENTS.md
  `cq-for-local-verification-of-apps-doppler` — Bash tool does NOT persist
  CWD, always chain `cd <abs-path> && <cmd>` explicitly.
- **Pre-existing checkout-error test broke when the chain changed.** The
  existing "returns 500 when DB update fails on checkout.session.completed"
  test set the error via `mockEq.mockResolvedValue({error:...})` — correct for
  the old `.update().eq()` terminal. After #2771 added `.in().select()` to the
  checkout handler, the error surface moved to `mockSelect`. **Recovery:**
  Updated the test to set error on `mockSelect` with a comment citing the
  chain change. **Prevention:** Same class as AGENTS.md
  `cq-preflight-fetch-sweep-test-mocks` — when a handler gains chain steps,
  sweep existing tests' mock error levels at the terminal. No new rule
  needed; the class is already documented.

## References

- PR: #2787
- Closes: #2771 (checkout out-of-order guard), #2772 (dedup table)
- Ref: #2701 (original `.in()` guard pattern on .updated/.deleted), #2190 (original out-of-order class)
- Follow-ups filed: #2788 (pg_cron retention + BRIN index), #2789 (crash-window hardening)
- Stripe docs: <https://docs.stripe.com/webhooks#requirements> (at-least-once delivery), <https://docs.stripe.com/webhooks#debug-webhook-integrations> (retry semantics)

## See Also

- `knowledge-base/project/learnings/2026-04-13-stripe-status-mapping-check-constraint.md` —
  Sibling concern: Stripe → DB status mapping and webhook error-check
  discipline. The dedup table is the natural next layer above the
  `mapStripeStatus()` and error-check pattern established there.
- AGENTS.md rules: `cq-test-mocked-module-constant-import`,
  `cq-preflight-fetch-sweep-test-mocks`, `cq-nextjs-route-files-http-only-exports`,
  `cq-for-local-verification-of-apps-doppler`,
  `wg-when-a-pr-includes-database-migrations`.
