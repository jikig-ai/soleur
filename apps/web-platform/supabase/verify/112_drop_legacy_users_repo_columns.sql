-- Verify 112_drop_legacy_users_repo_columns.sql.
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (and auto-closes any matching `follow-through` issue).
--
-- ADR-044 PR-2b (#5437) — the FINAL column DROP. Asserts the post-apply state:
-- the three dead users.* repo columns and the dead partial-UNIQUE index are GONE.
--
-- NOTE: every UNION branch's `bad` column MUST be the SAME type (Postgres rejects
-- a boolean/integer UNION: "UNION types boolean and integer cannot be matched";
-- this was a release-blocker once — commit e21066864 / #5474). run-verify.sh
-- reports `bad=N` and fails on `bad <> 0`, so `bad` is INTEGER throughout — the
-- column/index COUNT checks are already integer; they assert "= 0" then cast the
-- boolean predicate ::int (true→1, false→0).

-- (1) users.github_installation_id column is GONE.
SELECT 'users_github_installation_id_present' AS check_name,
       ((SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'users'
          AND column_name  = 'github_installation_id') > 0)::int AS bad
UNION ALL
-- (2) users.repo_url column is GONE.
SELECT 'users_repo_url_present',
       ((SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'users'
          AND column_name  = 'repo_url') > 0)::int AS bad
UNION ALL
-- (3) users.workspace_path column is GONE.
SELECT 'users_workspace_path_present',
       ((SELECT count(*) FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name   = 'users'
          AND column_name  = 'workspace_path') > 0)::int AS bad
UNION ALL
-- (4) the partial-UNIQUE index users_github_installation_id_unique_idx is GONE.
SELECT 'users_github_installation_id_unique_idx_present',
       ((SELECT count(*) FROM pg_indexes
        WHERE schemaname = 'public'
          AND tablename  = 'users'
          AND indexname  = 'users_github_installation_id_unique_idx') > 0)::int AS bad
UNION ALL
-- (5) the live handle_new_user() body no longer references the dropped column.
SELECT 'handle_new_user_no_workspace_path',
       (CASE WHEN pg_get_functiondef('public.handle_new_user()'::regprocedure) ILIKE '%workspace_path%' THEN 1 ELSE 0 END) AS bad;
