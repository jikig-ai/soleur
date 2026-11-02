-- Verify 176_users_restrictive_policy_subqueries.sql.
--
-- Contract (see run-verify.sh): every row returns check_name + bad.
-- Any row with bad > 0 fails the verify-migrations job where that job runs.
--
-- Asserts, for #10764:
--   1. the three users_own_* functions exist and are plpgsql STABLE SECURITY
--      DEFINER (prosecdef true, provolatile = s, language plpgsql);
--   2. the three RESTRICTIVE policies exist by name on public.users;
--   3. each policy's expression (polqual/polwithcheck via pg_get_expr) routes
--      through users_own_* — a bare self-subquery surviving in the recreated
--      policy expression means the seq-scan pathology is still live;
--   4. EXECUTE is granted to authenticated and denied to PUBLIC/anon (proacl
--      inspection) — the functions read own-row data and must not be callable
--      by unauthenticated callers. A NULL proacl means the default PUBLIC
--      grant survives and counts as bad.

SELECT 'users_own_fn_missing_or_wrong_shape' AS check_name, count(*)::int AS bad
  FROM (VALUES
    ('users_own_github_username', 'text'),
    ('users_own_kb_sync_history', 'jsonb'),
    ('users_own_health_snapshot', 'jsonb')
  ) AS want(fn, ret)
  LEFT JOIN pg_proc p
    ON p.proname = want.fn
   AND p.pronamespace = 'public'::regnamespace
   AND p.prokind = 'f'
   AND p.prolang = (SELECT oid FROM pg_language WHERE lanname = 'plpgsql')
   AND p.prosecdef = true
   AND p.provolatile = 's'
   AND pg_get_function_result(p.oid) ~* ('^' || want.ret || '$')
 WHERE p.oid IS NULL

UNION ALL

SELECT 'users_policy_missing', count(*)::int
  FROM (VALUES
    ('Users cannot update github_username directly'),
    ('Users cannot update kb_sync_history directly'),
    ('Prevent client health_snapshot update')
  ) AS want(polname)
  LEFT JOIN pg_policies pol
    ON pol.schemaname = 'public'
   AND pol.tablename = 'users'
   AND pol.policyname = want.polname
 WHERE pol.policyname IS NULL

UNION ALL

SELECT 'users_policy_expr_missing_fn_call', count(*)::int
  FROM pg_policies pol
  JOIN pg_policy polcat
    ON polcat.polname = pol.policyname
   AND polcat.polrelid = 'public.users'::regclass
 WHERE pol.schemaname = 'public'
   AND pol.tablename = 'users'
   AND pol.policyname IN (
     'Users cannot update github_username directly',
     'Users cannot update kb_sync_history directly',
     'Prevent client health_snapshot update'
   )
   AND NOT (
     COALESCE(pg_get_expr(polcat.polqual, polcat.polrelid), '')
       ~ 'users_own_(github_username|kb_sync_history|health_snapshot)\s*\('
     OR
     COALESCE(pg_get_expr(polcat.polwithcheck, polcat.polrelid), '')
       ~ 'users_own_(github_username|kb_sync_history|health_snapshot)\s*\('
   )

UNION ALL

-- A recreated policy expression that still embeds the self-subquery is the
-- pathology this migration removes; detect it directly, not only by the
-- absence of the function call above.
SELECT 'users_policy_expr_self_subquery', count(*)::int
  FROM pg_policies pol
  JOIN pg_policy polcat
    ON polcat.polname = pol.policyname
   AND polcat.polrelid = 'public.users'::regclass
 WHERE pol.schemaname = 'public'
   AND pol.tablename = 'users'
   AND pol.policyname IN (
     'Users cannot update github_username directly',
     'Users cannot update kb_sync_history directly',
     'Prevent client health_snapshot update'
   )
   AND (
     -- pg_get_expr de-qualifies relations already on search_path, so match
     -- 'FROM users' / 'FROM public.users' alike (word boundary, no schema pin).
     COALESCE(pg_get_expr(polcat.polqual, polcat.polrelid), '')
       ~* 'SELECT[^)]*(public\.)?users\s[^)]*auth\.uid'
     OR
     COALESCE(pg_get_expr(polcat.polwithcheck, polcat.polrelid), '')
       ~* 'SELECT[^)]*(public\.)?users\s[^)]*auth\.uid'
   )

UNION ALL

SELECT 'users_own_fn_exec_grants_wrong', count(*)::int
  FROM pg_proc p
 WHERE p.pronamespace = 'public'::regnamespace
   AND p.proname IN (
     'users_own_github_username',
     'users_own_kb_sync_history',
     'users_own_health_snapshot'
   )
   AND (
     -- authenticated must hold EXECUTE (aclitem prints as grantee=X/grantor)
     NOT (COALESCE(p.proacl::text, '') ~ 'authenticated=[^,}]*X')
     -- anon must NOT hold EXECUTE (public.users is not an anon surface)
     OR COALESCE(p.proacl::text, '') ~ 'anon=[^,}]*X'
     -- service_role must NOT hold EXECUTE (it bypasses RLS; grant is dead surface)
     OR COALESCE(p.proacl::text, '') ~ 'service_role=[^,}]*X'
     -- PUBLIC must NOT hold EXECUTE (the PUBLIC aclitem prints as =X/...)
     OR COALESCE(p.proacl::text, '') ~ '(^|[{,])=X'
   );
