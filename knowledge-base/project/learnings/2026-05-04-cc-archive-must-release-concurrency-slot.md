---
title: "Slot lifecycle invariants must live at the DB layer when multiple writers bypass the application path"
date: 2026-05-04
type: bug-fix
related_pr: 3217
related_migration: 036_release_slot_on_archive.sql
tags: [supabase, postgres-trigger, concurrency, command-center]
---

# Slot lifecycle invariants must live at the DB layer when multiple writers bypass the application path

## What broke

A user on the free tier (cap = 1) — and any user at any tier — was hard-locked
out of starting new conversations after archiving (or marking as completed)
all visible conversations. The Command Center sidebar correctly showed zero
active conversations, but `start_session` returned `cap_hit` and the WebSocket
closed with code `4010 CONCURRENCY_CAP`. The "Concurrent-conversation limit
reached" banner appeared with no in-product recovery path.

## Root cause

The slot ledger lives in `public.user_concurrency_slots` (migration 029).
Slot acquire/release goes through three SECURITY DEFINER RPCs:
`acquire_conversation_slot`, `touch_conversation_slot`, and
`release_conversation_slot`. Three application-layer surfaces write
`conversations.archived_at` directly without calling
`release_conversation_slot`:

1. `apps/web-platform/hooks/use-conversations.ts:325` —
   `archiveConversation` issues a client-side `supabase.from("conversations")
   .update({ archived_at })`.
2. `apps/web-platform/server/conversations-tools.ts` — the MCP tool
   `conversation_archive` does an analogous server-side UPDATE.
3. `apps/web-platform/hooks/use-conversations.ts:351` — `updateStatus`
   writes `status: 'completed'` directly. The WS handler's
   `close_conversation` path releases the slot when it transitions a
   conversation to `completed`, but the Command Center's status-update
   bypass never reaches the WS handler.

While the WebSocket session remained open, `touch_conversation_slot` kept
refreshing the heartbeat every 30s — so the lazy 120s sweep in
`acquire_conversation_slot` never fired either. The slot leaked until the
user fully disconnected and pg_cron's 1-minute sweep reclaimed it.

## Fix

Migration `036_release_slot_on_archive.sql` adds an AFTER UPDATE trigger on
`public.conversations` that calls the existing SECURITY DEFINER
`release_conversation_slot` RPC whenever `archived_at` transitions from NULL
to non-NULL. This closes the gap for every current and future writer (hook,
MCP tool, future API endpoint, manual DB write) without coupling each writer
to slot lifecycle.

## Why this had to live at the DB layer (not in the application code)

The slot ledger is a multi-writer invariant. Three application surfaces
already wrote to `conversations.archived_at`; a fourth would have arrived
soon (a planned `/api/conversations/:id/archive` endpoint for the mobile
client). Patching each writer to call `release_conversation_slot` would have
left a brittle surface that any future code change could re-break — exactly
the failure mode that produced this bug. The trigger is a single
chokepoint.

The same reasoning applies to migration 029 itself, where slot
acquire/release/heartbeat are SECURITY DEFINER RPCs (not direct table writes
guarded by RLS). Lifecycle logic owned by the DB, surfaces consume RPCs.

## Sharp edges encountered during fix design

1. **`status='completed'` is NOT a slot-release event.** Initial design had
   the trigger fire on either `archived_at` OR `status='completed'`
   transitions. This was rejected: `resume_session` in `ws-handler.ts` does
   NOT call `acquireSlot` (it sets `session.conversationId` directly with
   no slot acquire). Releasing on completed-only would let a user resume a
   completed conversation outside the slot ledger AND start a new one that
   takes the only slot — effectively cap+1 concurrent activity. The
   trigger fires on `archived_at` transitions ONLY. The user's reported
   scenario is still fixed because they archived after marking completed.

2. **`IS DISTINCT FROM` is mandatory for nullable comparisons in WHEN
   clauses.** `OLD.archived_at = NEW.archived_at` returns NULL when both
   sides are NULL (Postgres null-comparison rule), and `WHEN` treats NULL
   as false → the trigger silently misses the NULL → non-NULL transition.
   `IS DISTINCT FROM` correctly handles nullable comparisons.

3. **`AFTER UPDATE OF archived_at`** keeps the trigger no-op for unrelated
   column updates without WHEN-clause overhead. Postgres skips trigger
   evaluation entirely when the named column wasn't in the UPDATE's SET
   list — cheaper than a WHEN-clause filter alone (the planner doesn't
   even allocate a tuple snapshot).

4. **`release_conversation_slot` idempotence is load-bearing.** The
   `close_conversation` WS handler path already calls `releaseSlot`
   explicitly and writes `status='completed'`; if the user then archives
   the conversation, the trigger calls `release_conversation_slot` again.
   The RPC body is a plain keyed DELETE in migration 029 — a second
   invocation is a safe no-op. If a future change adds a side effect to
   `release_conversation_slot` beyond the keyed DELETE, the trigger
   becomes a fan-in for that side effect on every archive — re-evaluate
   then.

## Vitest cannot test Postgres triggers

The plan asked for unit tests asserting that `archiveConversation` "triggers
a `release_conversation_slot` RPC call." This is impossible to verify with
Vitest's mocked Supabase client — the hook does NOT call the RPC; only the
DB trigger does, at the data layer. Mocked-client assertions would be
vacuously true with or without the migration applied.

The right test shape for trigger-effect invariants:

1. **Migration-shape test** (`test/supabase-migrations/036-*.test.ts`):
   parse the SQL file, assert it declares the trigger with the right
   semantics (`AFTER UPDATE OF archived_at`, `IS DISTINCT FROM`,
   `NEW.archived_at IS NOT NULL`, `release_conversation_slot` body call,
   `search_path` pin, `REVOKE` on the function). This pins the contract
   without requiring a DB.

2. **Live-DB integration test**
   (`test/conversation-archive-release-slot.integration.test.ts`) gated by
   `SLOT_TRIGGER_INTEGRATION_TEST=1`: insert a conversation, acquire a
   slot, archive the conversation, assert `user_concurrency_slots` count
   went to 0. Ditto for the user-reported scenario (cap=1, archive,
   start new = ok). Ditto for the negative cases (unarchive, status-only
   update).

The negative path the migration test alone CANNOT catch is "trigger
declared but doesn't actually fire." That's the integration test's job.

## Detection footprint

A user-blocking, single-user-incident bug in a path the user follows on
literally every "I'm done with this conversation" workflow. The 4010 close
+ "Concurrent-conversation limit reached" banner is loud at the surface,
but the root cause (slot held by an archived conversation) was invisible
to anyone without the slot-ledger schema in their head. A free-tier
prospect would treat this as broken-product-on-day-one.

## Generalizable principle

When a value's lifecycle (acquire / use / release) is enforced by a
ledger table, every writer on every related table must either go through
the ledger's RPCs OR fire a trigger that does. Application-layer
enforcement is brittle in proportion to the number of writer surfaces;
DB-layer enforcement is robust by construction. The trade-off is
trigger-discoverability — a future engineer reading the application code
will not see the trigger — which is why migration headers must
cross-reference each other (this migration cites 029).
