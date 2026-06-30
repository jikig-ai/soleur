-- Negative-proof fixture for verify/117 check 1 (1a no_single_owner_unique_index
-- + 1b no_single_owner_constraint).
--
-- A sentinel that never returns bad>0 is worthless. This fixture PROVES
-- verify/117 checks 1a + 1b fire: in two transactions it re-introduces the
-- forbidden single-owner vectors (a partial-UNIQUE index, then a UNIQUE/EXCLUDE
-- constraint), runs the matching check, and asserts bad>0 — each block ROLLBACKs
-- so the schema is untouched.
--
-- MANUAL / LOCAL-DB PROOF — NOT part of any automated pipeline. The
-- release-workflow verify path (apps/web-platform/scripts/run-verify.sh) globs
-- ONLY supabase/verify/*.sql, so nothing executes THIS fixture automatically. It
-- is run BY HAND against a seeded/freshly-migrated local DB (psql via
-- DATABASE_URL_POOLER / Supabase MCP), or wired into a future live-DB
-- integration step. Its check-1a/1b queries are VERBATIM copies of verify/117's
-- shipped check 1, kept in lockstep — the parity assertion in
-- test/supabase-migrations/117-reconcile-ownership-rpc-comments-multi-owner.test.ts
-- fails if the fixture and the shipped check ever drift.
--
-- Expected: each SELECT returns bad >= 1; each DO block raises if it does not.

BEGIN;

-- Re-introduce the forbidden single-owner-strict enforcement: at most one owner
-- row per workspace. This is exactly what ADR-072 forbids and what check 1 must
-- catch.
CREATE UNIQUE INDEX ws_members_one_owner_per_workspace_neg_idx
  ON public.workspace_members (workspace_id)
  WHERE role = 'owner';

DO $$
DECLARE
  v_bad int;
BEGIN
  SELECT (SELECT count(*) FROM pg_index i
            JOIN pg_class c ON c.oid = i.indrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'workspace_members'
             AND i.indisunique
             AND pg_get_expr(i.indpred, i.indrelid) ILIKE '%owner%'
             AND pg_get_indexdef(i.indexrelid) ILIKE '%workspace_id%'))::int
    INTO v_bad;

  IF v_bad < 1 THEN
    RAISE EXCEPTION 'verify/117 check 1a FAILED to fire on a single-owner partial-unique index (bad=%)', v_bad;
  END IF;
  RAISE NOTICE 'verify/117 check 1a correctly returned bad=% on the negative fixture', v_bad;
END $$;

ROLLBACK;

-- ---------------------------------------------------------------------------
-- check 1b (no_single_owner_constraint): the OTHER forbidden vector — a
-- UNIQUE/EXCLUDE CONSTRAINT mentioning owner. A partial-unique INDEX (block 1)
-- and a table CONSTRAINT are distinct catalog objects (pg_index vs
-- pg_constraint), so check 1b needs its own negative proof.
-- ---------------------------------------------------------------------------
BEGIN;

-- Re-introduce single-owner enforcement as an EXCLUDE CONSTRAINT: at most one
-- 'owner' row per workspace_id. (A partial UNIQUE constraint cannot carry a
-- WHERE predicate, so an EXCLUDE with a WHERE on role='owner' is the realistic
-- constraint-shaped vector; its constraintdef mentions owner.)
ALTER TABLE public.workspace_members
  ADD CONSTRAINT ws_members_one_owner_per_workspace_neg_excl
  EXCLUDE (workspace_id WITH =) WHERE (role = 'owner');

DO $$
DECLARE
  v_bad int;
BEGIN
  SELECT (SELECT count(*) FROM pg_constraint con
            JOIN pg_class c ON c.oid = con.conrelid
            JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'public'
             AND c.relname = 'workspace_members'
             AND con.contype IN ('u', 'x')
             AND pg_get_constraintdef(con.oid) ILIKE '%owner%'))::int
    INTO v_bad;

  IF v_bad < 1 THEN
    RAISE EXCEPTION 'verify/117 check 1b FAILED to fire on a single-owner UNIQUE/EXCLUDE constraint (bad=%)', v_bad;
  END IF;
  RAISE NOTICE 'verify/117 check 1b correctly returned bad=% on the negative fixture', v_bad;
END $$;

ROLLBACK;
