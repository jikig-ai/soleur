-- 113_set_repo_status_writes_workspace_repo_error.sql
-- feat-one-shot-shared-workspace-founder-resolve-and-provision (Bug 2, Phase 2.4).
--
-- Closes the member-triggered self-heal SPLIT-WRITE (the AC6c headline user).
--
-- Migration 108's set_repo_status dual-wrote the failure reason to
-- users.repo_error (the caller = auth.uid()). Migration 110 then relocated the
-- READ: getCurrentRepoStatus (current-repo-url.ts:134) now reads
-- workspaces.repo_error, keyed on the ACTIVE workspace (membership-correct for a
-- shared workspace). So as of 110 the 108 write targets a column the readiness
-- gate NO LONGER READS:
--   * a non-owner MEMBER healing a shared workspace writes their OWN
--     users.repo_error on a clone FAILURE, but the gate re-reads
--     workspaces.repo_error (which stays NULL) → the next dispatch fast-paths /
--     mis-reports and the member loops forever with NO honest reason. (#4560
--     SOLEUR-DEBT marker in 108:172-181, now actionable.)
--
-- Fix (minimal, reason-targeting ONLY — does NOT expand into the #4755 KB-route
-- surface): redefine set_repo_status to write the reason onto
-- workspaces.repo_error (the active-workspace row the gate reads), NOT
-- users.repo_error. The workspace id is the membership-checked p_workspace_id, so
-- the reason lands on the exact row getCurrentRepoStatus reads back for ANY
-- member of that workspace — owner or not. No users.* write at all (users.repo_error
-- is the soon-dead legacy column; ADR-044 relocated repo-connection state to
-- workspaces.*). 'ready' clears the reason; 'error' sets the caller-framed one.
--
-- Precedent: verbatim 108 REVOKE/GRANT (4-role REVOKE PUBLIC,anon,authenticated,
-- service_role then GRANT EXECUTE TO authenticated) + SECURITY DEFINER +
-- `SET search_path = public, pg_temp` (public first) per
-- cq-pg-security-definer-search-path-pin-pg-temp and the migration-rpc-grants
-- lint. claim_repo_clone_lock is UNCHANGED (108) — only set_repo_status is
-- redefined here. CREATE OR REPLACE keeps the same signature, so existing tenant
-- .rpc("set_repo_status", …) call sites are unaffected.
--
-- DEPENDENCY: migration 110 (workspaces.repo_error column), 108 (the fn this
-- replaces), 053 (is_workspace_member). Supabase wraps each migration file in ONE
-- transaction; no CONCURRENTLY / non-transactional DDL.

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION '113: public.workspaces must exist (run 053/079/110 first)';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'workspaces'
      AND column_name  = 'repo_error'
  ) THEN
    RAISE EXCEPTION '113: public.workspaces.repo_error must exist (run migration 110 first)';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.set_repo_status(
  p_workspace_id uuid,
  p_status       text,
  p_error        text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF NOT public.is_workspace_member(p_workspace_id, v_user_id) THEN
    RAISE EXCEPTION 'caller is not a member of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('ready', 'error') THEN
    RAISE EXCEPTION 'set_repo_status: p_status must be ready|error, got %', p_status
      USING ERRCODE = '22023';
  END IF;

  -- Terminal write onto the ACTIVE workspace row (the readiness gate's source of
  -- truth). The reason is written to workspaces.repo_error — the column
  -- getCurrentRepoStatus reads back for ANY member of the workspace (Bug 2 AC6c).
  -- ready: clear the reason + stamp repo_last_synced_at. error: set the framed,
  -- already-sanitized reason (this fn does not re-sanitize).
  UPDATE public.workspaces
     SET repo_status         = p_status,
         repo_error          = CASE WHEN p_status = 'ready' THEN NULL
                                    ELSE p_error END,
         repo_last_synced_at = CASE WHEN p_status = 'ready' THEN now()
                                    ELSE repo_last_synced_at END
   WHERE id = p_workspace_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_repo_status(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_repo_status(uuid, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.set_repo_status(uuid, text, text) IS
  'Membership-checked terminal write of the dispatch self-heal (FIX 1a + Bug 2). '
  'Writes workspaces.repo_status (source of truth) AND workspaces.repo_error '
  '(the sanitized reason the readiness gate reads, keyed on the active workspace '
  '— membership-correct for shared workspaces; supersedes the 108 users.repo_error '
  'split-write). ready clears the reason + stamps repo_last_synced_at; error sets '
  'the caller-framed reason. Callable via tenant .rpc() so cc-dispatcher stays '
  'off the service-role allowlist. ADR-044.';

COMMIT;

-- Tracking row written in the same transaction by run-migrations.sh
-- (canonical) or the Doppler+pg fallback applier.
