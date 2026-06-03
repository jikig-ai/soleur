-- 097_workspace_bash_autonomous.sql
-- Issue B part 2 — per-workspace "autonomous / trusted" Bash toggle.
--
-- Adds workspaces.bash_autonomous (off by default). When ON, the Concierge
-- permission-callback bypasses the Bash review-gate for all NON-BLOCKED
-- commands (the BLOCKED_BASH_PATTERNS denylist — curl|wget|nc|sh -c|eval|
-- base64 -d|/dev/tcp|sudo — stays authoritative even under autonomy). This
-- is, by design, an approval-bypass on a code-executing surface, so the
-- column is an authz-relevant value:
--
--   * READ  — member-checked get_workspace_bash_autonomous (mirrors the
--             resolve_workspace_installation_id ADR-044 shape). Returns NULL
--             for non-members / unauthenticated; the server read helper
--             treats NULL as fail-closed false.
--   * WRITE — OWNER-only set_workspace_bash_autonomous. Enabling an approval
--             bypass is an ownership-grade decision; members cannot flip it.
--
-- The workspaces table has RLS enabled (053) with ONLY a SELECT-for-members
-- policy and NO UPDATE policy, so authenticated cannot UPDATE bash_autonomous
-- directly under the tenant client (default-deny). Both RPCs are SECURITY
-- DEFINER with search_path pinned to `public, pg_temp`
-- (cq-pg-security-definer-search-path-pin-pg-temp), REVOKE'd from PUBLIC/anon/
-- service_role, GRANT'd to authenticated only. R8: the write RPC scopes the
-- owner check by (p_workspace_id, auth.uid()) — no cross-workspace write.

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS bash_autonomous boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.workspaces.bash_autonomous IS
  'Issue B part 2: when true, the Concierge auto-approves all non-BLOCKED '
  'Bash commands (skips the review-gate; the blocklist still applies). '
  'Owner-only write via set_workspace_bash_autonomous; member read via '
  'get_workspace_bash_autonomous. Off by default; fail-closed on read error.';

-- READ: member-checked. NULL for non-member / unauthenticated (deny path),
-- mirroring resolve_workspace_installation_id (079).
CREATE OR REPLACE FUNCTION public.get_workspace_bash_autonomous(p_workspace_id uuid)
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

  SELECT bash_autonomous INTO v_value
  FROM public.workspaces
  WHERE id = p_workspace_id;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION public.get_workspace_bash_autonomous(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_bash_autonomous(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_workspace_bash_autonomous(uuid) IS
  'Member-checked read of workspaces.bash_autonomous. NULL for non-members '
  '(deny path) — server resolveBashAutonomous treats NULL as fail-closed false.';

-- WRITE: OWNER-only. Enabling an approval-bypass is an ownership decision.
-- Raises on a non-owner / unauthenticated caller (authz violation, not a
-- normal null) so the server helper surfaces + mirrors it.
CREATE OR REPLACE FUNCTION public.set_workspace_bash_autonomous(
  p_workspace_id uuid,
  p_value boolean
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- R8 composite-key invariant: owner check scopes by (p_workspace_id,
  -- auth.uid()) — a caller can only flip a workspace they own.
  IF NOT EXISTS (
    SELECT 1
    FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = auth.uid()
      AND role         = 'owner'
  ) THEN
    RAISE EXCEPTION 'not authorized: only a workspace owner may set bash_autonomous';
  END IF;

  UPDATE public.workspaces
  SET bash_autonomous = p_value
  WHERE id = p_workspace_id;

  RETURN p_value;
END;
$$;

REVOKE ALL ON FUNCTION public.set_workspace_bash_autonomous(uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_workspace_bash_autonomous(uuid, boolean)
  TO authenticated;

COMMENT ON FUNCTION public.set_workspace_bash_autonomous(uuid, boolean) IS
  'Owner-only write of workspaces.bash_autonomous. Raises for non-owners. '
  'Enabling an approval-bypass on a code-executing surface is ownership-grade.';
