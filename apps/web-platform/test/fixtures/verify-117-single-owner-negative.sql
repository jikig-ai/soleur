-- Negative-proof fixture for verify/117 check 1 (no_single_owner_unique_index).
--
-- A sentinel that never returns bad>0 is worthless. This fixture PROVES
-- verify/117 check 1 fires: inside a transaction it re-introduces a single-owner
-- partial-UNIQUE index (the exact vector the check targets), runs check 1, and
-- asserts bad>0 — then ROLLBACKs so the schema is untouched.
--
-- RUN (requires a live, freshly-migrated test DB — DATABASE_URL_POOLER /
-- Supabase MCP). In this pipeline run there is NO live DB, so this fixture is
-- AUTHORED but NOT EXECUTED; it is the named negative-proof location referenced
-- by test/supabase-migrations/117-reconcile-ownership-rpc-comments-multi-owner.test.ts
-- and by the release-workflow migrate+verify path.
--
-- Expected: the SELECT returns bad >= 1; the DO block raises if it does not.

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
    RAISE EXCEPTION 'verify/117 check 1 FAILED to fire on a single-owner partial-unique index (bad=%)', v_bad;
  END IF;
  RAISE NOTICE 'verify/117 check 1 correctly returned bad=% on the negative fixture', v_bad;
END $$;

ROLLBACK;
