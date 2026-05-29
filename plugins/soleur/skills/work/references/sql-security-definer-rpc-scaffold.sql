-- Canonical SECURITY DEFINER RPC scaffold for Supabase migrations.
--
-- Copy this template when a tenant-client write/read must bypass an RLS or
-- column-grant restriction (the #4224/#4226 silent-write-drop class). The shape
-- below is the one the lint test enforces:
--   apps/web-platform/test/migration-rpc-grants.test.ts
-- and the hard rule:
--   cq-pg-security-definer-search-path-pin-pg-temp
--
-- Three load-bearing pieces the lint checks for EVERY `SECURITY DEFINER` fn:
--   1. `SET search_path = public, pg_temp` (in that order) in the declaration.
--   2. A REVOKE that removes EXECUTE from PUBLIC + anon + authenticated.
--      (Supabase's `ALTER DEFAULT PRIVILEGES ... GRANT EXECUTE TO anon,
--      authenticated, service_role` makes the named-role REVOKE load-bearing —
--      a bare `FROM PUBLIC` is NOT enough; the default grant survives it.)
--   3. Relations referenced as `public.<table>` (fully qualified) — the pinned
--      search_path makes unqualified lookups fall back to public then pg_temp,
--      but qualify anyway so intent is explicit.
--
-- Replace <fn_name>, params, and the body. Keep the auth.uid() pin: a
-- SECURITY DEFINER fn runs as the definer (bypassing RLS), so the function
-- body is now the ONLY thing enforcing per-caller authorization.

CREATE OR REPLACE FUNCTION public.<fn_name>(p_target_id uuid, p_value text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Authorization pin: SECURITY DEFINER bypasses RLS, so re-assert the
  -- caller's right to act on this row here. Use the ownership scope that
  -- matches the resource (auth.uid() = user_id for user-owned rows;
  -- public.is_workspace_member(auth.uid(), <workspace_id>) for shared rows).
  IF NOT EXISTS (
    SELECT 1 FROM public.<table>
    WHERE id = p_target_id
      AND user_id = auth.uid()          -- or: AND public.is_workspace_member(...)
  ) THEN
    RAISE EXCEPTION 'not authorized' USING ERRCODE = '42501';
  END IF;

  UPDATE public.<table>
     SET <column> = p_value
   WHERE id = p_target_id;
END;
$$;

-- 4-role REVOKE (PUBLIC + the three Supabase default-granted roles). The
-- service_role line is belt-and-suspenders: the lint requires PUBLIC, anon,
-- authenticated; include service_role to close the residual default EXECUTE.
REVOKE ALL ON FUNCTION public.<fn_name>(uuid, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- Grant back EXECUTE only to the role(s) that should call it.
GRANT EXECUTE ON FUNCTION public.<fn_name>(uuid, text) TO authenticated;
