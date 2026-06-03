---
title: "Fixing a broken WORM-bypass on a multi-step saga: enumerate ALL bypass mechanisms, not just the one the bug report names"
date: 2026-05-31
category: database-issues
tags: [worm, trigger, bypass, gdpr, art17, account-delete, session_replication_role, current_user, postgrest, security-definer, saga, migration, multi-agent-review]
related:
  - 4696
  - 4702
related_migrations:
  - 050_fix_scope_grants_trigger_bypass.sql
  - 087_worm_bypass_privilege_independence.sql
related_learnings:
  - 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md
---

# Fixing a broken WORM-bypass on a multi-step saga: enumerate ALL bypass mechanisms

## Problem

GDPR Art. 17 account deletion was broken in production (Sentry WEB-PLATFORM-13).
The bug report named one symptom: the saga aborts at `anonymise_action_sends` with
`42501 permission denied to set parameter "session_replication_role"`. That GUC is
superuser-only (PGC_SUSET); the `SECURITY DEFINER` anonymise RPCs are owned by
`postgres`, which on managed Supabase is **not** a superuser, so the `SET LOCAL
session_replication_role='replica'` WORM-bypass raises before the UPDATE.

The obvious fix — replace `session_replication_role` with a privilege-free custom
GUC (`app.worm_bypass`) — was correct but **incomplete**. The account-delete saga
runs ~17 `anonymise_*` RPCs in sequence and aborts on the FIRST failing step, so the
Sentry event only ever names step 3.82. Fixing only the `session_replication_role`
functions would have moved the break downstream to a DIFFERENT broken-bypass class.

## Root cause — two independent broken-bypass mechanisms on the same saga

`grep`-ing for the symptom (`session_replication_role`) found 7 saga functions. But a
multi-agent review surfaced a SECOND, independent defect class on the same saga:

- **`anonymise_tc_acceptances` (mig 044, saga-FATAL)** and **`anonymise_dsar_export_audit_pii`
  (mig 041)** bypass their WORM triggers via a per-table sentinel GUC PAIRED with
  `current_user = 'service_role'`. Inside a `SECURITY DEFINER` RPC owned by `postgres`,
  `current_user` is `postgres`, NOT `service_role`, so the gate is **silently
  always-false** → the bypass never fires → the trigger ALWAYS raises `P0001`. This is
  the exact pattern documented in
  `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`
  (migration 050 fixed `scope_grants` this way; 041/044 were never converted — the
  learning's "fix 043/044 in a follow-up" TODO was never executed).

`tc_acceptances` is FATAL and every user has a T&C consent row, so the
`session_replication_role` fix alone would have left erasure broken end-to-end for
every real user — just with a different SQLSTATE (P0001 instead of 42501) at a later
saga step.

## Solution

Migration `087_worm_bypass_privilege_independence.sql` converts BOTH broken bypass
mechanisms (the superuser `session_replication_role` AND the dead `current_user`
sentinel-GUC) to ONE uniform, privilege-free custom GUC across **9 anonymise RPCs +
10 trigger functions** on the erasure path:

```sql
-- In each anonymise RPC (replaces session_replication_role OR the per-table sentinel):
SET LOCAL app.worm_bypass = 'on';
UPDATE ...;                 -- the single erasure write
SET LOCAL app.worm_bypass = 'off';   -- re-arm WORM immediately (no leak)

-- In each WORM trigger function (replaces pure-reject / dead-role-gate / SRR-check):
IF current_setting('app.worm_bypass', true) = 'on' THEN
  RETURN COALESCE(NEW, OLD);          -- works for BEFORE-reject AND AFTER-suppress
END IF;
RAISE EXCEPTION '... append-only (WORM)' USING ERRCODE = 'P0001';
```

`app.worm_bypass` is a custom namespaced GUC → settable by any role without privilege
(no 42501), and has NO `current_user` dependency (not the proven-dead pattern — it is
the learning's own recommended no-role-check bypass, a refinement of the 041/043/044
`app.*_anonymise_in_progress` convention with the dead role half removed). Also
`DROP NOT NULL` on `byok_delegation_acceptances.user_id` (a real, distinct defect: the
column was `NOT NULL` with FK ON DELETE RESTRICT, yet the anonymise RPC nulls it).

The uniform-GUC (over structural-shape, the plan's original prescription) was forced
by `anonymise_workspace_members`, which suppresses **AFTER side-effect triggers**
(audit writer + byok-revoke cascade) — there is no reject "row-shape" to detect, so
structural-shape detection cannot express it; a GUC is the only mechanism that covers
both BEFORE-reject and AFTER-suppress uniformly.

## Key Insight

**When a bug report names ONE failing step of a multi-step saga that aborts-on-first-error,
the reported symptom is a lower bound on the blast radius, not the blast radius.** Before
declaring the fix complete:

1. **Enumerate every bypass MECHANISM, not just the one the symptom names.** A WORM-bypass
   can be broken by ≥3 distinct mechanisms (superuser-only `session_replication_role`;
   dead `current_user='service_role'` role gate; a sentinel GUC). Scan the live DB for ALL
   of them: `pg_get_functiondef(p.oid) ILIKE '%session_replication_role%' OR ILIKE
   '%current_user%service_role%'` over `prokind='f'`.
2. **Trust the live DB over migration files** (append-only) AND over the plan's enumerated
   scope. The plan's 5-table list and the operator's framing both anchored on the reported
   `session_replication_role` symptom; the live function bodies revealed the second class.
3. **Reproduce each suspected-broken step on a REAL row** before AND after the fix
   (`BEGIN; INSERT synthetic; SELECT anonymise_x(...); ROLLBACK`). `anonymise_tc_acceptances`
   → P0001 on a real row was the empirical proof that turned an architecture-review
   hypothesis into a confirmed saga-blocker. A 0-row call is vacuous (the row-level trigger
   never fires).
4. **Multi-agent review earns its cost on exactly this class.** The `architecture-strategist`
   agent, prompted to compare against precedent, surfaced that 041/043/044 carry the dead
   gate — a gap the symptom-grep, the plan, and the operator all missed. The verification
   loop (review → live-DB scan → synthetic-row reproduction → scope expansion) is the
   pattern.

The dev/prod privilege divergence is why this class hides: dev's `postgres` HAS the
`session_replication_role` grant and the `current_user` gate is equally always-false on
dev and prod, so neither defect reproduces as a hard failure on dev unless you (a) run as
the actual prod-equivalent role for the 42501, or (b) exercise the dead-gate path on a real
row for the P0001. The committed regression guard is therefore a **SQL-text guardrail**
(assert the broken patterns are textually absent + the privilege-free pattern present),
not a behavioral test — behavioral tests stay green on dev while prod is broken.

## Session Errors

1. **RED-test regex backreference bug** — used `\2` in a pattern with a single capture
   group, so the function-block matcher matched nothing and 23 assertions failed with
   "expected null not to be null." Recovery: changed `\2` → `\1`. **Prevention:** count the
   capture groups in a regex before writing a backreference; `\N` must reference an existing
   group.
2. **Postgres `LIKE 'anonymise[_]%'`** — SQL `LIKE` does not support `[...]` character
   classes (only `%` and `_`), so the function-introspection query returned an empty
   FUNCTIONS section and looked like the functions didn't exist. Recovery: switched to
   `proname = ANY($1)` with explicit names. **Prevention:** SQL `LIKE` ≠ regex; use `~`
   for POSIX regex or exact `= ANY(...)`.
3. **`pg_get_functiondef` on an aggregate** — scanning all `pg_proc` rows ran the function
   on `array_agg` and raised `42809 "array_agg" is an aggregate function`. Recovery: filter
   `p.prokind = 'f'`. **Prevention:** always constrain `pg_proc` to `prokind='f'` before
   `pg_get_functiondef`.
4. **Transaction poisoned (25P02)** — an expected-`P0001` error inside a `BEGIN` block
   aborted the whole transaction; the next statement returned "current transaction is
   aborted." Recovery: wrap each expected-error probe in `SAVEPOINT s; ... ; ROLLBACK TO
   SAVEPOINT s`. **Prevention:** any expected-error assertion inside a transaction needs a
   savepoint, or each error kills the rest of the txn.
5. **0-row WORM re-arm false negative** — tested re-arm with `UPDATE ... WHERE id =
   gen_random_uuid()` (matches 0 rows); a `FOR EACH ROW` trigger never fires on 0 rows, so
   the bare UPDATE "succeeded" and looked like the GUC leaked. Recovery: test against an
   existing row. **Prevention:** to exercise a row-level trigger you must affect ≥1 row.
6. **Synthetic `tc_acceptances` CHECK violation** — inserted `document_sha='sha-test'`,
   violating a length/format CHECK (needs 64 hex chars). Recovery: used `'a'.repeat(64)`.
   **Prevention:** read a table's CHECK constraints (`pg_get_constraintdef`) before
   synthesizing fixtures.
7. **`gh issue create` blocked by milestone hook** — the PreToolUse gate denies issue
   creation without `--milestone`. Recovery: added `--milestone "Post-MVP / Later"`.
   **Prevention:** every `gh issue create` needs `--milestone` (operational → "Post-MVP /
   Later"). Already hook-enforced.

## Tags
category: database-issues
module: apps/web-platform/supabase/migrations
