---
title: Applying an unmerged migration to shared dev during /work broke another PR's CI (and triggered a same-subsystem sibling collision at merge)
date: 2026-07-03
category: workflow-patterns
tags: [migrations, dev-db, shared-state, mid-pipeline-collision, ship, cto-fork]
issue: 5767
pr: 5881
severity: P1
---

## What happened

During `/work` on feat-l5-runaway-guard (#5767), I applied migration
`121_byok_cap_kill_tripped_while_paused.sql` to the **shared dev Supabase
project** (via MCP `apply_migration`) to fail-fast on SQL validity — the
canonical inline-apply step. That migration `CREATE OR REPLACE`d
`record_byok_use_and_check_cap` with `IF v_paused_at IS NOT NULL THEN
v_tripped := true`.

The `tenant-integration` suite (`byok-kill-switch.atomicity.tenant-isolation`)
runs against the **live dev RPC**. Its Invariant C ("exactly one trip, on the
CAP+COST crossing call") started failing on `main` for **every** PR — because
under concurrency my drifted body reports `kill_tripped=true` a SECOND time for
an already-paused caller. A sibling one-shot (#5917) diagnosed the red as "dev
RPC drift, not contention", authored a fix (#5919: `v_tripped := FOUND`,
exactly-once), re-applied it to dev, and **merged a same-prefix `121_*.sql` to
main** — all while my PR sat in the merge queue.

At my ship-time merge poll, the auto-sync pulled #5919's `121_byok_cap_trip_from_found.sql`
into my branch (clean git merge — different filenames), producing (a) a duplicate
`121` prefix and (b) two `CREATE OR REPLACE`s of the same function with
contradictory `kill_tripped` semantics. The collision was invisible to git and
would only have failed at CI's migration-drift gate.

## Root causes

1. **Applying an unmerged, behavior-changing migration to a SHARED dev DB is a
   cross-PR side effect.** Shared-dev integration tests (`tenant-integration`)
   read the live RPC, so my un-landed drift broke *other people's* CI on main.
   The inline-apply-to-dev step is safe for additive schema (a new column no
   test asserts against) but NOT for a `CREATE OR REPLACE` that changes the
   behavior a shared test depends on.
2. **Reusing one return boolean (`kill_tripped`) for a new role.** It conflated
   "just crossed the cap" (exactly-once, concurrency-correct) with "this founder
   is blocked" (paused-or-tripped). The two are genuinely different signals —
   the precedent-mirror-for-a-new-role fencing class
   ([[2026-06-30-precedent-mirror-for-new-role-breaks-fencing-token-monotonicity]]).
   Review's architecture-strategist flagged exactly this risk; I under-weighted it.

## Prevention

- **Before `apply_migration` to shared dev during /work, ask: does a
  behavior-changing `CREATE OR REPLACE`/`ALTER` here alter something a shared
  integration test (`tenant-integration`, `verify/`) asserts against live?** If
  yes, do NOT apply to shared dev pre-merge — validate SQL syntactically
  (a scratch/transaction-rollback, or a local pg) instead, and let the release
  pipeline apply on merge. Additive-only migrations remain safe to inline-apply.
- **Mid-pipeline collision check must cover semantics, not just the prefix.**
  The `/ship` prefix-collision re-check (renumber on dup `NNN_`) catches the
  filename clash, but a sibling `CREATE OR REPLACE` of the **same function** is
  a semantic collision even at a *different* number. When a ship-time sync pulls
  in `supabase/migrations/*.sql`, grep the incoming migrations for any
  `CREATE OR REPLACE FUNCTION <same-name>` your PR also touches.
- **When two PRs need contradictory contracts on one RPC return value, split
  the signals** — don't have the later PR re-define the shared boolean. Here the
  resolution was to NOT touch the RPC at all and own the new role (paused-block)
  in the caller (a fail-closed entry gate), leaving `kill_tripped` as #5919's
  exactly-once signal.

## Resolution

CTO fork ruling (recorded in ADR-041): deleted the RPC-backstop migration;
made the spawn-entry pause gate **fail-closed** (a `users`-read error halts via
`run_paused`, matching the two adjacent fail-closed cap-check steps). Layer 2's
per-spawn ceiling bounds any residual leak to ≤ `PER_SPAWN_COST_CEILING_CENTS`.
See [[2026-07-02-inngest-side-effect-outside-step-run-duplicates-on-replay]] for
the sibling notification-layer learning from the same PR's review.
