-- 158_workspace_web_egress.sql
-- feat-open-web-egress (#9534) — per-workspace opt-in "Agent web access"
-- toggle.
--
-- Adds workspaces.web_egress (off by default). When ON for a workspace,
-- hosted agent sessions dispatched under that workspace get a per-
-- dispatch credentialed loopback-proxy env → forwarder → Squid CONNECT
-- gateway chain (PR-A infra; env proxy supersedes httpProxyPort per the
-- Phase-0 spike, spec TR7), re-enable WebFetch, and still deny every
-- credential env var in-sandbox. Default (and any read error) =
-- zero-egress, unchanged.
--
-- LAWFUL_BASIS: consent (Art. 6(1)(a)) — owner opt-in via the Scope
-- Grants UI; withdrawal = toggle off (GDPR Art. 7(3) parity: revoking is
-- as easy as granting). The column itself stores only a boolean flag —
-- the lawful basis annotation covers the grant RECORD itself (the
-- entitlement state is evidence of the workspace owner's consent).
--
-- The column is the per-workspace control surface, so it is an
-- authz-relevant value, cloned from 101_workspace_debug_mode.sql:
--
--   * READ  — member-checked get_workspace_web_egress (mirrors
--             get_workspace_debug_mode / 097's get_workspace_bash_autonomous).
--             Returns NULL for non-members / unauthenticated; the server
--             read helper treats NULL as fail-closed false.
--   * WRITE — OWNER-only set_workspace_web_egress. Enabling arbitrary
--             open-web egress for every agent session in a workspace is an
--             ownership-grade decision; members cannot flip it.
--
-- The workspaces table has RLS enabled (053) with ONLY a SELECT-for-members
-- policy and NO UPDATE policy, so authenticated cannot UPDATE web_egress
-- directly under the tenant client (default-deny). Both RPCs are SECURITY
-- DEFINER with search_path pinned to `public, pg_temp`
-- (cq-pg-security-definer-search-path-pin-pg-temp), REVOKE'd from PUBLIC/anon/
-- service_role, GRANT'd to authenticated only. The write RPC scopes the owner
-- check by (p_workspace_id, auth.uid()) — no cross-workspace write.

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS web_egress boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.workspaces.web_egress IS
  'feat-open-web-egress (#9534): when true, hosted agent sessions dispatched '
  'under this workspace route open-web traffic through the Squid CONNECT '
  'gateway via a per-dispatch localhost forwarder. Owner-only write via '
  'set_workspace_web_egress; member read via get_workspace_web_egress. '
  'Off by default; fail-closed on read error.';

-- READ: member-checked. NULL for non-member / unauthenticated (deny path),
-- mirroring get_workspace_debug_mode (101).
CREATE OR REPLACE FUNCTION public.get_workspace_web_egress(p_workspace_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_value boolean;
BEGIN
  -- is_workspace_member(NULL, …) and (…, NULL) both return FALSE, so a null
  -- arg or unauthenticated caller falls through to RETURN NULL.
  IF NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RETURN NULL;
  END IF;

  SELECT web_egress INTO v_value
  FROM public.workspaces
  WHERE id = p_workspace_id;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION public.get_workspace_web_egress(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_web_egress(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_workspace_web_egress(uuid) IS
  'Member-checked read of workspaces.web_egress. NULL for non-members '
  '(deny path) — server resolveWebEgress treats NULL as fail-closed false.';

-- WRITE: OWNER-only. Granting open-web egress to every agent session in the
-- workspace is an ownership decision. Raises on a non-owner / unauthenticated
-- caller (authz violation, not a normal null) so the server helper surfaces +
-- mirrors it (P0001 → HTTP 403 at the route).
CREATE OR REPLACE FUNCTION public.set_workspace_web_egress(
  p_workspace_id uuid,
  p_value boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- Composite-key invariant: owner check scopes by (p_workspace_id,
  -- auth.uid()) — a caller can only flip a workspace they own.
  IF NOT EXISTS (
    SELECT 1
    FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = auth.uid()
      AND role         = 'owner'
  ) THEN
    RAISE EXCEPTION 'not authorized: only a workspace owner may set web_egress';
  END IF;

  UPDATE public.workspaces
  SET web_egress = p_value
  WHERE id = p_workspace_id;

  RETURN p_value;
END;
$$;

REVOKE ALL ON FUNCTION public.set_workspace_web_egress(uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_workspace_web_egress(uuid, boolean)
  TO authenticated;

COMMENT ON FUNCTION public.set_workspace_web_egress(uuid, boolean) IS
  'Owner-only write of workspaces.web_egress. Raises for non-owners. '
  'Granting open-web egress to all workspace agent sessions is '
  'ownership-grade.';
