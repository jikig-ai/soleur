-- Verify 110_workspace_repo_error_and_comember_reconcile.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (and auto-closes any matching `follow-through` issue).
--
-- ADR-044 PR-2 team write-cutover (#5462, Phase 1). Asserts the post-apply
-- state of the migration's schema add + SOLO drift reconcile. The drift exit is
-- two-part (deepen-confirmed CLO/PA-17(c) reshape of the literal "COUNT -> 0"):
--   (1) SOLO drift-gate COUNT = 0 post-reconcile (sole-member workspaces).
--   (2) 0 co-membered workspaces adopted WITHOUT an attestation — NOT "0 SKIP
--       rows remaining" (the co-membered backlog is a lawful carried residual
--       cleared by owner re-connect, this PR's owner-gated write path).

-- (1) workspaces.repo_error column exists (the schema precondition for the
--     write relocation + getCurrentRepoStatus read).
SELECT 'workspaces_repo_error_missing' AS check_name,
       (SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'workspaces'
          AND column_name  = 'repo_error') = 0 AS bad
UNION ALL
-- (2) repo_error is in the `authenticated` column-level SELECT grant (it is a
--     sanitized reason, non-credential). A tenant read of it must not be
--     permission-denied (getCurrentRepoStatus reads it via the tenant client).
SELECT 'repo_error_not_in_authenticated_grant',
       NOT EXISTS (
         SELECT 1 FROM information_schema.column_privileges
         WHERE table_schema = 'public'
           AND table_name   = 'workspaces'
           AND column_name  = 'repo_error'
           AND grantee      = 'authenticated'
           AND privilege_type = 'SELECT'
       ) AS bad
UNION ALL
-- (3) github_installation_id stays REVOKE'd from `authenticated` (credential —
--     readable only via resolve_workspace_installation_id RPC).
SELECT 'github_installation_id_leaked_to_authenticated',
       EXISTS (
         SELECT 1 FROM information_schema.column_privileges
         WHERE table_schema = 'public'
           AND table_name   = 'workspaces'
           AND column_name  = 'github_installation_id'
           AND grantee      = 'authenticated'
           AND privilege_type = 'SELECT'
       ) AS bad
UNION ALL
-- (4) SOLO drift-gate COUNT = 0. ADR-044's exact PR-2b gate query
--     (users JOIN workspaces ON w.id = u.id) scoped to SOLO (sole-member)
--     workspaces. Post-reconcile this must be 0; co-membered rows are excluded
--     (asserted separately in check 5).
SELECT 'repo_drift_count',
       (SELECT count(*)::int FROM public.users u
          JOIN public.workspaces w ON w.id = u.id
        WHERE (
          (u.repo_url IS NOT NULL AND w.repo_url IS DISTINCT FROM u.repo_url)
          OR (u.github_installation_id IS NOT NULL
              AND w.github_installation_id IS DISTINCT FROM u.github_installation_id)
        )
        AND (
          SELECT count(*) FROM public.workspace_members m2
          WHERE m2.workspace_id = w.id
        ) = 1) AS bad
UNION ALL
-- (5) 0 co-membered (sole-member COUNT > 1) workspaces that have an adopted
--     repo connection WITHOUT a corresponding attestation row. This is the
--     lawful-basis assertion: a co-membered workspace may hold a repo_url only
--     if an Art. 6(1)(a) attestation exists (workspace_member_attestations,
--     mig 058). This migration does NOT auto-adopt, so this stays 0.
SELECT 'comembered_adopted_without_attestation',
       (SELECT count(*)::int FROM public.workspaces w
        WHERE w.repo_url IS NOT NULL
          AND (
            SELECT count(*) FROM public.workspace_members m2
            WHERE m2.workspace_id = w.id
          ) > 1
          AND NOT EXISTS (
            SELECT 1 FROM public.workspace_member_attestations a
            WHERE a.workspace_id = w.id
          )) AS bad;
