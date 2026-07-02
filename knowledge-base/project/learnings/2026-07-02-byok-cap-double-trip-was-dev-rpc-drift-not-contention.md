---
title: "byok cap-boundary double-trip on tenant-integration was dev-RPC drift, not shared-DB contention"
date: 2026-07-02
issue: 5917
tags: [ci, supabase, byok, drift, tenant-integration, concurrency, verdict]
category: workflow-patterns
---

# byok cap-boundary double-trip was dev-RPC drift (H1), not shared-DB contention

## Symptom

The **required** `tenant-integration-required` check went red on `main`
(2026-07-02 ~20:26 UTC) on the live-DB test
`apps/web-platform/test/server/byok-kill-switch.atomicity.tenant-isolation.test.ts`
› *"N concurrent RPC calls at cap-boundary serialize via FOR UPDATE"* —
Invariant C: `at cumulative=700: expected true to be false`. Two unrelated
PRs (a docs/infra-guard #5908 and a git-worktree diagnostics #5907) both
flipped it red immediately after a green run, with zero byok/RPC/migration
code delta in the window. It failed twice consecutively + a full re-run.

## Issue #5917's hypothesis — and why it was wrong

The issue read the "two unrelated PRs, no code delta, persistent" signal as a
**shared dev-Supabase cross-run contention flake** and proposed test-side
fixes (per-run row namespace / serialize the test). Both halves were wrong:

- The founder row is **already per-run unique** (randomBytes-derived email →
  unique `users.id`); the `FOR UPDATE` lock and the `SUM ... WHERE founder_id`
  are founder-scoped, so concurrent CI runs **cannot** contend on this row.
  The "dedicated row namespace" fix already existed.
- Invariant **B** (serialization: cumulatives `[100..1000]`, no gaps/dupes)
  **passed** — so the lock *was* serializing. Only the trip *signal*
  double-fired. The failing invariant was **atomicity (exactly-one-trip)**,
  not load/serialization.

## Verdict: H1 — dev-DB RPC drift (confirmed by reading the live body)

The decisive read was `pg_get_functiondef` on **dev**, not code-reading. The
live dev body was **not** migration 061's. It carried an extra branch:

```sql
IF v_paused_at IS NOT NULL THEN
  v_tripped := true;              -- reports a trip on EVERY already-paused call
ELSIF v_total > v_cap THEN
  UPDATE ... ; v_tripped := true;
END IF;
```

`list_migrations` on dev pinned the culprit exactly: a migration
`byok_cap_kill_tripped_while_paused` (supabase ledger version
**20260702195538**, i.e. 19:55:38 UTC — between the 19:43 last-green and
20:26 first-red runs) applied **directly to dev via MCP** and **never
committed to the repo** (source's last definition is migration 061). Under
concurrency the cumulative-700 caller acquires the lock after 600 stamps
`runtime_paused_at`, re-reads it non-NULL, and this body reports
`kill_tripped=true` a second time → the double-trip.

## The fix (correct under drift AND any genuine snapshot-staleness)

Migration **121** (`121_byok_cap_trip_from_found.sql`): derive the trip from
the guarded `UPDATE`'s actual effect —

```sql
IF v_total > v_cap THEN
  UPDATE public.users SET runtime_paused_at = now()
   WHERE id = p_founder_id AND runtime_paused_at IS NULL;
  v_tripped := FOUND;   -- true iff THIS statement changed the row
END IF;
```

`FOUND` is a strict improvement over mig 061's `v_paused_at IS NULL AND
v_total > v_cap` pre-read guard: the `WHERE ... AND runtime_paused_at IS NULL`
predicate is evaluated atomically against the current row under the lock, so
exactly one concurrent caller flips NULL → non-NULL. `FOR UPDATE` retained.
Applying it to dev is an idempotent `CREATE OR REPLACE` that both reconciles
the rogue drift and hardens the body. Verified: the live-DB atomicity test
passes against dev post-apply.

## Transferable lessons

1. **A required-check flake with "no code delta in the window" is not
   automatically environmental — the live function body can drift from source
   independently of any git change.** Read `pg_get_functiondef` on the
   affected DB before trusting a "shared-DB contention" narrative. `git log`
   proves what the *repo* says; it says nothing about what the *dev DB* runs.
2. **`list_migrations` on the affected project timestamps the drift.** A
   supabase-ledger entry that has no counterpart file in
   `supabase/migrations/` is a direct-to-DB apply — a smoking gun with a
   clock on it.
3. **Never hand-apply an experimental migration to dev via MCP without
   committing it.** The `byok_cap_kill_tripped_while_paused` apply broke the
   required check for every founder's merges with no repo trace. Follow-up:
   a drift-probe that asserts live byok RPC *bodies* (not just the ledger)
   is filed as a `Ref #5917` follow-up.
4. **Don't weaken the assertion to "tolerate" the anomaly.** Invariant C is
   the safety net for a real cost-ceiling atomicity regression; the double-
   trip was a *correct* rejection of a genuinely-wrong body.
