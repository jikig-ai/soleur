-- 110_workspace_repo_error_and_comember_reconcile.down.sql
-- Reverse 110 (ADR-044 PR-2 team write-cutover, #5462 — Phase 1).
--
-- The backfill steps (3-4) are SCOPED-FORWARD-ONLY: they re-keyed the
-- still-authoritative `users` snapshot onto solo workspaces. A blanket revert
-- would risk nulling repo state a direct workspace connect set post-110. The
-- repo_url/github_installation_id/repo_status/repo_last_synced_at columns are
-- dropped wholesale by 079.down.sql, so this down only reverses the additive
-- schema change (the repo_error column + its GRANT extension).

-- Restore the mig-079 GRANT shape (without repo_error).
REVOKE SELECT ON public.workspaces FROM authenticated;
GRANT SELECT (id, organization_id, name, created_at,
              repo_url, repo_provider, repo_status, repo_last_synced_at)
  ON public.workspaces TO authenticated;

ALTER TABLE public.workspaces
  DROP COLUMN IF EXISTS repo_error;
