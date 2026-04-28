-- 033_migrate_api_key_to_v2_rpc.sql
-- Predicate-locked v1 -> v2 BYOK migration. Concurrent callers serialize
-- via PG row locks on api_keys; the second writer's UPDATE matches
-- WHERE key_version = 1 with zero rows (no-op). See #2919 + plan
-- 2026-04-27-fix-cc-soleur-go-cleanup-2918-2923-plan.md.
--
-- LANGUAGE sql (not plpgsql) -- single UPDATE, no control flow. Matches
-- the migration 027 (sum_user_mtd_cost) precedent.
-- SECURITY DEFINER -- `getUserApiKey` and `getUserServiceTokens` invoke
-- via the service-role client (apps/web-platform/server/agent-runner.ts).
-- REVOKE from authenticated and anon defends against accidental
-- client-side calls slipping in.
-- search_path is pinned to `public, pg_temp` (in that order). Listing
-- `public` first defends against definer-hijacking attacks where an
-- attacker plants a same-named relation under `pg_temp` (their session-
-- private schema) — the SECURITY DEFINER body would otherwise resolve
-- the unqualified relation against the attacker's planted object. The
-- explicit `public.api_keys` qualifier below is belt-and-suspenders.

CREATE OR REPLACE FUNCTION public.migrate_api_key_to_v2(
  p_id        uuid,
  p_user_id   uuid,
  p_provider  text,
  p_encrypted text,
  p_iv        text,
  p_tag       text
) RETURNS TABLE (rows_affected integer)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  WITH updated AS (
    UPDATE public.api_keys
       SET encrypted_key = p_encrypted,
           iv            = p_iv,
           auth_tag      = p_tag,
           key_version   = 2,
           updated_at    = NOW()
     WHERE id            = p_id
       AND user_id       = p_user_id
       AND provider      = p_provider
       AND key_version   = 1
       AND is_valid      = true
     RETURNING 1
  )
  SELECT COUNT(*)::INTEGER FROM updated;
$$;

COMMENT ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) IS
  'Service-role-only v1 -> v2 BYOK re-encryption. Predicate-locked '
  'UPDATE serializes concurrent callers via PG row locks. See #2919.';

REVOKE EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.migrate_api_key_to_v2(uuid, uuid, text, text, text, text) TO   service_role;
