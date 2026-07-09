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

  -- jti-deny re-assert (ONLY if the referenced tables carry the RESTRICTIVE
  -- `<table>_jti_not_denied` policy, 068/126 shape). That policy protects DIRECT
  -- PostgREST table access, NOT this fn: SECURITY DEFINER bypasses RLS, so a
  -- denylisted-but-unexpired JWT would otherwise read/write via the rpc() path.
  -- A RESTRICTIVE RLS policy protects rows, not RPCs — re-encode EVERY
  -- RLS-boundary property here. Omit for RPCs over non-jti tables. (PR #6239)
  IF public.is_jti_denied_from_jwt() THEN
    RAISE EXCEPTION 'token denied' USING ERRCODE = '42501';
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
-- SAFE here because this scaffold gates on the NON-forgeable auth.uid().
--
-- CALLER-OVERRIDE VARIANT (forgeable identity → service_role ONLY): if the
-- function instead resolves the caller via COALESCE(p_caller_user_id, auth.uid())
-- — necessary when the TS wrapper invokes via createServiceClient() (service-role
-- key) where auth.uid() is NULL — then p_caller_user_id is client-forgeable.
-- Granting such a function TO authenticated lets any logged-in user call it via
-- PostgREST with a forged caller id and bypass the owner-gate. In that case GRANT
-- to service_role ONLY (mirror accept_workspace_invitation mig 076/085), never
-- authenticated. Rule: a forgeable caller-override param and TO service_role are a
-- matched pair — copy BOTH halves of the precedent. See
-- knowledge-base/project/learnings/security-issues/2026-06-01-caller-override-rpc-needs-service-role-only-grant.md (#4762/#4765).
GRANT EXECUTE ON FUNCTION public.<fn_name>(uuid, text) TO authenticated;
