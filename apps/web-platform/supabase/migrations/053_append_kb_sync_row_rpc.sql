-- #4224 — atomic, RLS-bypassing append to public.users.kb_sync_history.
--
-- Background:
--   Migration 006 column grant restricts `authenticated` to UPDATE(email)
--   only on public.users. Migration 017 adds a RESTRICTIVE RLS policy
--   pinning kb_sync_history to "must not change" for any authenticated
--   UPDATE. Together, these two layers mean a tenant-scoped Supabase
--   client (role=authenticated) CANNOT write the kb_sync_history column —
--   every UPDATE silently returns "permission denied" and is absorbed by
--   the helper's best-effort try/catch.
--
--   PR-C §2.1 (#3244) migrated `recordKbSyncHistory` from service-role to
--   tenant client, masking this constraint behind the best-effort
--   contract (writes were already silently failing pre-#4224). #4224
--   added `appendKbSyncRow` and the KbSyncStatus UI surface, which makes
--   the write loss user-visible (chip would always show "Workspace
--   ready" because no rows ever land).
--
-- Solution:
--   SECURITY DEFINER RPC that performs the read-merge-cap-write atomically
--   under the function owner's privileges, pinned to `auth.uid()` for
--   tenant isolation. Granted to `authenticated` only; service-role can
--   still call it directly when needed. The RESTRICTIVE policy from 017
--   stays in place — SECURITY DEFINER bypasses it; direct UPDATE paths
--   remain blocked.
--
-- Side benefits:
--   - Eliminates the read-then-write lost-update race that the JS-side
--     helper had (data-integrity-guardian P1-3 / user-impact F3) —
--     concurrent reconcile + manual sync calls now serialize at the
--     row-level lock taken by UPDATE.
--   - Heterogeneous JSONB shapes (legacy {date,count} + new rich rows)
--     are preserved; the function only appends and trims.
--
-- search_path pin per cq-pg-security-definer-search-path-pin-pg-temp.

CREATE OR REPLACE FUNCTION public.append_kb_sync_row(
  p_row jsonb,
  p_cap int DEFAULT 100
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    -- Service-role callers (Inngest worker minting tenant JWT) reach here
    -- via getFreshTenantClient(userId), so auth.uid() is the founder.
    -- A null auth.uid() means the caller has no session — refuse.
    RAISE EXCEPTION 'append_kb_sync_row: no auth.uid()';
  END IF;

  UPDATE public.users
     SET kb_sync_history = (
       WITH appended AS (
         SELECT elem, ord
           FROM jsonb_array_elements(COALESCE(kb_sync_history, '[]'::jsonb))
                  WITH ORDINALITY t(elem, ord)
         UNION ALL
         SELECT p_row, COALESCE(jsonb_array_length(kb_sync_history), 0) + 1
       ),
       trimmed AS (
         SELECT elem, ord
           FROM appended
           ORDER BY ord DESC
           LIMIT p_cap
       )
       SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
         FROM trimmed
     )
   WHERE id = v_caller;
END;
$$;

REVOKE ALL ON FUNCTION public.append_kb_sync_row(jsonb, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_kb_sync_row(jsonb, int) TO authenticated;

COMMENT ON FUNCTION public.append_kb_sync_row(jsonb, int) IS
  '#4224 — appends a row to the caller''s public.users.kb_sync_history JSONB array, capped at p_cap rows. SECURITY DEFINER + auth.uid() pin; granted to authenticated role only. Solves the migration-006 column-grant + migration-017 RESTRICTIVE-policy block on tenant-client writes.';
