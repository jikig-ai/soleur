-- Postgres-side month-to-date cost aggregate for the BYOK usage
-- dashboard. Replaces a client-side JS reduce over up to 1000 rows
-- (see issue #2478). Uses the partial index from migration 017
-- (idx_conversations_user_cost), enabling an index-only scan.
--
-- SECURITY: security-definer + explicit search_path; REVOKE from
-- PUBLIC/authenticated/anon and GRANT only to service_role. End users
-- must never call this directly -- the BYOK loader runs under the
-- service client which already enforces "caller MUST have verified
-- userId belongs to the session" (see server/api-usage.ts:1-5).
--
-- Idempotency note: CREATE OR REPLACE FUNCTION preserves existing
-- grants on REPLACE, but on FIRST create Postgres grants EXECUTE to
-- PUBLIC by default. The REVOKE statements below MUST run on every
-- apply -- treating them as "cleanup" after the CREATE is a real
-- security gap. The REVOKEs are ordered immediately after the CREATE
-- so a mid-file retry still lands them.

-- If a future migration changes the signature, uncomment the DROP and
-- drop the old (UUID, TIMESTAMPTZ) overload. For the initial apply
-- this is a no-op -- CREATE OR REPLACE handles the in-place update.
-- DROP FUNCTION IF EXISTS public.sum_user_mtd_cost(UUID, TIMESTAMPTZ);

CREATE OR REPLACE FUNCTION public.sum_user_mtd_cost(
  uid   UUID,
  since TIMESTAMPTZ
) RETURNS TABLE(total NUMERIC, n INTEGER)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  -- COALESCE guarantees `total` is never NULL when zero rows match;
  -- matches the loader's `mtdTotalUsd = 0` default. COUNT(*)::INTEGER
  -- is an explicit cast on a non-user-controlled column count.
  SELECT COALESCE(SUM(total_cost_usd), 0)::NUMERIC AS total,
         COUNT(*)::INTEGER                          AS n
    FROM public.conversations
   WHERE user_id = uid
     AND total_cost_usd > 0
     AND created_at >= since;
$$;

COMMENT ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) IS
  'Service-role-only MTD cost aggregate for the BYOK usage dashboard. '
  'End users MUST NOT call this directly; see server/api-usage.ts. '
  'Issue #2478.';

REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) FROM anon;
GRANT  EXECUTE ON FUNCTION public.sum_user_mtd_cost(UUID, TIMESTAMPTZ) TO   service_role;
