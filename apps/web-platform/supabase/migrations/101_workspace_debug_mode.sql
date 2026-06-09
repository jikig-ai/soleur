-- 101_workspace_debug_mode.sql
-- feat-debug-mode-stream — per-workspace internal "debug mode" toggle.
--
-- Adds workspaces.debug_mode (off by default). When ON for a workspace
-- (visible only to the Soleur `dev` cohort, gated server-side), a separate
-- collapsed debug panel streams REDACTED Claude Agent SDK harness events
-- (tool_use name + redacted tool_input, assistant text, result/usage) so
-- operators see live what the harness is doing. The stream is render-only,
-- ephemeral, and a scoped exception to the #2138 "no raw tool inputs on the
-- wire" invariant — exactly as command_stream already is. The column is the
-- per-workspace control surface, so it is an authz-relevant value:
--
--   * READ  — member-checked get_workspace_debug_mode (mirrors 097's
--             get_workspace_bash_autonomous shape). Returns NULL for
--             non-members / unauthenticated; the server read helper treats
--             NULL as fail-closed false.
--   * WRITE — OWNER-only set_workspace_debug_mode. Enabling a harness
--             instruction stream is an ownership-grade decision; members
--             cannot flip it.
--
-- The workspaces table has RLS enabled (053) with ONLY a SELECT-for-members
-- policy and NO UPDATE policy, so authenticated cannot UPDATE debug_mode
-- directly under the tenant client (default-deny). Both RPCs are SECURITY
-- DEFINER with search_path pinned to `public, pg_temp`
-- (cq-pg-security-definer-search-path-pin-pg-temp), REVOKE'd from PUBLIC/anon/
-- service_role, GRANT'd to authenticated only. The write RPC scopes the owner
-- check by (p_workspace_id, auth.uid()) — no cross-workspace write.

ALTER TABLE public.workspaces
  ADD COLUMN IF NOT EXISTS debug_mode boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.workspaces.debug_mode IS
  'feat-debug-mode-stream: when true, the dev-cohort debug panel streams '
  'redacted harness SDK events for this workspace (render-only, ephemeral). '
  'Owner-only write via set_workspace_debug_mode; member read via '
  'get_workspace_debug_mode. Off by default; fail-closed on read error.';

-- READ: member-checked. NULL for non-member / unauthenticated (deny path),
-- mirroring get_workspace_bash_autonomous (097).
CREATE OR REPLACE FUNCTION public.get_workspace_debug_mode(p_workspace_id uuid)
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

  SELECT debug_mode INTO v_value
  FROM public.workspaces
  WHERE id = p_workspace_id;

  RETURN v_value;
END;
$$;

REVOKE ALL ON FUNCTION public.get_workspace_debug_mode(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_workspace_debug_mode(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.get_workspace_debug_mode(uuid) IS
  'Member-checked read of workspaces.debug_mode. NULL for non-members '
  '(deny path) — server resolveDebugMode treats NULL as fail-closed false.';

-- WRITE: OWNER-only. Enabling the harness instruction stream is an ownership
-- decision. Raises on a non-owner / unauthenticated caller (authz violation,
-- not a normal null) so the server helper surfaces + mirrors it.
CREATE OR REPLACE FUNCTION public.set_workspace_debug_mode(
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
    RAISE EXCEPTION 'not authorized: only a workspace owner may set debug_mode';
  END IF;

  UPDATE public.workspaces
  SET debug_mode = p_value
  WHERE id = p_workspace_id;

  RETURN p_value;
END;
$$;

REVOKE ALL ON FUNCTION public.set_workspace_debug_mode(uuid, boolean)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_workspace_debug_mode(uuid, boolean)
  TO authenticated;

COMMENT ON FUNCTION public.set_workspace_debug_mode(uuid, boolean) IS
  'Owner-only write of workspaces.debug_mode. Raises for non-owners. '
  'Enabling the dev-cohort harness instruction stream is ownership-grade.';
