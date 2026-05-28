-- 080_backfill_workspace_repo_from_users.down.sql
-- SCOPED-FORWARD-ONLY reversal (data-integrity P2).
--
-- A blanket `UPDATE workspaces SET repo_url = NULL` would DESTROY repos
-- connected DIRECTLY to a workspace after 080 ran (e.g., a workspace that
-- connected its own repo post-backfill). The reversal therefore nulls the
-- repo columns ONLY for solo workspaces whose values still equal the
-- users source — i.e., rows untouched since the 080 copy. Any row that
-- diverged from the source (a direct workspace connect) is LEFT ALONE.
--
-- Rows that diverged are intentionally not reverted here; the wholesale
-- column drop lives in 079.down.sql. This down is forward-only for the
-- divergent set by design.

UPDATE public.workspaces w
   SET repo_url               = NULL,
       repo_provider          = 'github',
       github_installation_id = NULL,
       repo_status            = 'not_connected',
       repo_last_synced_at    = NULL
  FROM public.users u
 WHERE w.id = u.id
   AND u.repo_url IS NOT NULL
   AND w.repo_url               IS NOT DISTINCT FROM u.repo_url
   AND w.github_installation_id IS NOT DISTINCT FROM u.github_installation_id;
