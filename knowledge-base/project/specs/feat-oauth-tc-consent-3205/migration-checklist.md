---
title: "Migration 044 — Apply Checklist"
feature: feat-oauth-tc-consent-3205
pr: 3853
issue: 3205
migration: apps/web-platform/supabase/migrations/044_add_tc_acceptances_ledger.sql
migration_sha256: 8ff3974289094d188ac94944c63bd0022d7c1580e24852eca90332af564836f4
migration_sha256_pre_idempotency_guards: 0580ea5465eb68d90d316871a4f74e8cf87a230f4cc00f2de71863fc6698d864
---

# Migration 044 — Apply Checklist

Per AC1 of the plan: dev applied pre-merge, prd applied post-merge via
`/soleur:ship` Phase 5. Per `hr-dev-prd-distinct-supabase-projects` — both
projects MUST receive the migration with verification recorded here.

## Project refs (verified at /work time)

| Env | Project ref (verified via `doppler secrets get ... -p soleur -c <env>`) |
|---|---|
| `dev` | `mlwiodleouzwniehynfz` |
| `prd` | `ifsccnjhymdmidffkzhl` |

**Plan drift caught at /work:** the plan body listed `bdgbnzmprmqsibpvtbmd` (dev)
and `zzfprwuaccgpdttogdoa` (prd). Doppler is the source of truth — these
project refs are the verified-correct values. Plan precondition 0.3
("Verify Supabase project IDs for dev / prd via `doppler secrets get
SUPABASE_PROJECT_REF`") refuted the plan body's quoted values; this
checklist records the correct refs.

## Dev apply

- [x] Applied: **2026-05-15 22:01:08 UTC**
- [x] Method: `pg` (node `pg@8.20.0`) → `DATABASE_URL_POOLER` rewritten to
      session mode (`:6543` → `:5432`) so multi-statement DDL executes in
      a single transaction. Pooler avoids the IPv6-only direct-DB route
      (`db.<ref>.supabase.co:5432`) which is unreachable from the
      operator's network.
- [x] SQL file SHA-256 at apply time: `0580ea5465eb68d90d316871a4f74e8cf87a230f4cc00f2de71863fc6698d864`
- [x] SQL file SHA-256 after idempotency-guard edit (post-merge re-apply only — same DDL semantics): `8ff3974289094d188ac94944c63bd0022d7c1580e24852eca90332af564836f4`
- [x] Migration wrapped in `BEGIN; …; COMMIT;` — atomic.

### Post-apply structural verification (dev)

| Invariant | Result |
|---|---|
| Table `public.tc_acceptances` with 9 expected columns | ✅ id, user_id, version, document_sha, accepted_at, ip_hash, user_agent, retention_until, created_at |
| RLS enabled, 0 policies | ✅ rls_enabled=true, policy_count=0 |
| Triggers wired | ✅ `tc_acceptances_no_update` (BEFORE UPDATE), `tc_acceptances_no_delete` (BEFORE DELETE) |
| `accept_terms(uuid, text, text)` registered + SECURITY DEFINER | ✅ |
| `anonymise_tc_acceptances(uuid)` registered + SECURITY DEFINER | ✅ |
| `tc_acceptances_no_mutate()` registered + INVOKER (not DEFINER) | ✅ prosecdef=false |
| `UNIQUE(user_id, version)` constraint | ✅ `tc_acceptances_user_id_version_key` |

The generalised `migration-rpc-grants.test.ts` will also re-validate the
REVOKE/GRANT patterns on every PR run.

## Prd apply

- [ ] Applied: _(post-merge via `/soleur:ship` Phase 5)_
- [ ] Method:
- [ ] SQL file SHA-256: _(same canonical file; matches dev)_

### Post-apply structural verification (prd)

_(filled in post-merge by `/soleur:ship` Phase 5; same invariants as dev)_

### Post-apply behavioural verification (prd — AC23)

Per `hr-no-dashboard-eyeball-pull-data-yourself`: queries via
`mcp__plugin_supabase_supabase__execute_sql` OR direct `pg` against
`DATABASE_URL_POOLER` (session mode).

```sql
-- 1. Insert one synthetic acceptance via the RPC (service-role context).
SELECT public.accept_terms(
  '<a real user_id from public.users>',
  '1.0.0',
  '79b2d2c00136cfcd1e61cb7ee9654aeb2b80cf21f2b2d33d1f063f10948d9300'
);

-- 2. Read it back.
SELECT user_id, version, document_sha, accepted_at
  FROM public.tc_acceptances
 WHERE version = '1.0.0'
 ORDER BY accepted_at DESC
 LIMIT 1;

-- 3. WORM invariant: UPDATE MUST raise P0001.
DO $$ BEGIN
  UPDATE public.tc_acceptances SET version = 'tampered' WHERE version = '1.0.0';
EXCEPTION WHEN SQLSTATE 'P0001' THEN
  RAISE NOTICE 'WORM passed: UPDATE rejected with P0001';
END $$;

-- 4. Anonymise RPC: user_id NULL after call.
SELECT public.anonymise_tc_acceptances('<the same user_id>');
SELECT user_id FROM public.tc_acceptances WHERE version = '1.0.0';
-- expect: NULL
```

- [ ] AC23-1 RPC insert succeeded:
- [ ] AC23-2 Row visible:
- [ ] AC23-3 UPDATE rejected with P0001:
- [ ] AC23-4 user_id NULL after anonymise:

## Rollback (emergency-only)

Roll back **only** if structural verification fails or AC23 spot-check
identifies a P0 defect. Rolling back DESTROYS audit-trail rows; if a single
user has already accepted under v1.0.0 in production, prefer fix-forward
(see "Fix-forward" below).

```sql
-- Safety check first: how many rows would be lost?
SELECT COUNT(*) FROM public.tc_acceptances;
-- If > 0, escalate before continuing. The WORM ledger has no GDPR-safe
-- recovery path after this point.

BEGIN;

-- Reverse-order teardown: drop dependents before the table.
DROP TRIGGER IF EXISTS tc_acceptances_no_delete ON public.tc_acceptances;
DROP TRIGGER IF EXISTS tc_acceptances_no_update ON public.tc_acceptances;
DROP FUNCTION IF EXISTS public.anonymise_tc_acceptances(uuid);
DROP FUNCTION IF EXISTS public.accept_terms(uuid, text, text);
DROP FUNCTION IF EXISTS public.tc_acceptances_no_mutate();
DROP INDEX IF EXISTS public.tc_acceptances_user_accepted_idx;
DROP TABLE IF EXISTS public.tc_acceptances;

COMMIT;
```

**Application-side rollback prerequisites:**

1. Revert `app/api/accept-terms/route.ts` to the pre-PR version (idempotent
   UPDATE on `public.users.tc_accepted_version`, no `accept_terms` RPC).
2. Revert `middleware.ts` fail-closed branch to fail-open (DO NOT redeploy
   without this — middleware will hard-fail every request once the table
   is dropped because `users.tc_accepted_version` is still referenced).
3. Revert `server/ws-handler.ts` mid-session re-check (DB query against the
   deleted table will crash every gated WS message).
4. Re-apply DB rollback **only after** the application revert is live.

### Fix-forward (preferred over rollback for any defect that has touched user data)

If `accept_terms()` is misbehaving but the WORM rows are intact, write a
forward-migration `045_fix_accept_terms.sql` that `CREATE OR REPLACE`s the
RPC. The migration's idempotency guards (`CREATE INDEX IF NOT EXISTS`,
`DROP TRIGGER IF EXISTS`) make re-applies safe; teardown is a last resort
that violates Art. 7(1) demonstrability for every row dropped.
