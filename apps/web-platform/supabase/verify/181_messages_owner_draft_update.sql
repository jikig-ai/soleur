-- Verify 181_messages_owner_draft_update.sql — contract: check_name + bad (run-verify.sh).
-- Reads the live catalog, so it catches a policy or grant that drifted from the
-- migration text. Deparse-aware: pg_policies renders (SELECT auth.uid()) as
-- ( SELECT auth.uid() AS uid) and IN (...) as = ANY (ARRAY[...]). A bare
-- auth.uid() match would be tautological (is_workspace_member(..., auth.uid())
-- contains it), so the user_id literal is asserted instead.
--
-- Row 1 counts every PERMISSIVE UPDATE/ALL policy on messages: exactly one may
-- exist and it must be messages_owner_draft_update. A legitimate second UPDATE
-- policy (for example the co-owner decision tracked in #11629) must update this
-- row in the same PR. The RESTRICTIVE messages_jti_not_denied ALL policy is
-- not permissive and is asserted separately.

SELECT 'messages_policy_single_permissive_update' AS check_name,
  CASE WHEN (SELECT count(*) FROM pg_policies
              WHERE schemaname = 'public' AND tablename = 'messages'
                AND permissive = 'PERMISSIVE' AND cmd IN ('UPDATE', 'ALL')) = 1
        AND EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname = 'public' AND tablename = 'messages'
                       AND policyname = 'messages_owner_draft_update'
                       AND permissive = 'PERMISSIVE' AND cmd = 'UPDATE')
       THEN 0 ELSE 1 END::int AS bad
UNION ALL
SELECT 'messages_policy_roles_authenticated_only',
  CASE WHEN EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname = 'public' AND tablename = 'messages'
                       AND policyname = 'messages_owner_draft_update'
                       AND roles = ARRAY['authenticated']::name[])
       THEN 0 ELSE 1 END
UNION ALL
SELECT 'messages_policy_using_author_member_draft',
  CASE WHEN EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname = 'public' AND tablename = 'messages'
                       AND policyname = 'messages_owner_draft_update'
                       AND position('user_id = ( SELECT auth.uid()' IN qual) > 0
                       AND position('is_workspace_member(' IN qual) > 0
                       AND position('status = ''draft''::text' IN qual) > 0
                       AND position(' OR ' IN qual) = 0)
       THEN 0 ELSE 1 END
UNION ALL
SELECT 'messages_policy_with_check_author_member_draft_archived',
  CASE WHEN EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname = 'public' AND tablename = 'messages'
                       AND policyname = 'messages_owner_draft_update'
                       AND position('user_id = ( SELECT auth.uid()' IN with_check) > 0
                       AND position('is_workspace_member(' IN with_check) > 0
                       AND position('status = ANY (ARRAY[''draft''::text, ''archived''::text])' IN with_check) > 0
                       AND position(' OR ' IN with_check) = 0)
       THEN 0 ELSE 1 END
UNION ALL
-- RLS stays enabled: with it off every policy above is moot and any authenticated session could update the two granted columns.
SELECT 'messages_rls_enabled',
  CASE WHEN EXISTS (SELECT 1 FROM pg_class WHERE oid = 'public.messages'::regclass AND relrowsecurity)
       THEN 0 ELSE 1 END
UNION ALL
SELECT 'messages_jti_policy_still_restrictive_all',
  CASE WHEN EXISTS (SELECT 1 FROM pg_policies
                     WHERE schemaname = 'public' AND tablename = 'messages'
                       AND policyname = 'messages_jti_not_denied'
                       AND permissive = 'RESTRICTIVE' AND cmd = 'ALL')
       THEN 0 ELSE 1 END
UNION ALL

-- Table-level UPDATE is gone for both client roles.
SELECT 'messages_no_table_update_anon_authenticated',
  CASE WHEN has_table_privilege('anon', 'public.messages', 'UPDATE')
         OR has_table_privilege('authenticated', 'public.messages', 'UPDATE')
       THEN 1 ELSE 0 END
UNION ALL

-- Column privileges derived from pg_attribute (a future column is covered):
-- authenticated holds UPDATE on exactly status and draft_preview.
SELECT 'messages_authenticated_update_columns_exact', count(*)::int
FROM pg_attribute a
WHERE a.attrelid = 'public.messages'::regclass
  AND a.attnum > 0 AND NOT a.attisdropped
  AND has_column_privilege('authenticated', a.attrelid, a.attname, 'UPDATE')
      IS DISTINCT FROM (a.attname IN ('status', 'draft_preview'))
UNION ALL

-- anon holds no UPDATE privilege on any column.
SELECT 'messages_anon_no_update_columns', count(*)::int
FROM pg_attribute a
WHERE a.attrelid = 'public.messages'::regclass
  AND a.attnum > 0 AND NOT a.attisdropped
  AND has_column_privilege('anon', a.attrelid, a.attname, 'UPDATE')
UNION ALL

-- attacl complement sweep in the registered-or-covered form of the fuzz gate:
-- a column-level UPDATE with no covering table-level verb, other than the two
-- granted columns. service_role keeps its table-level grants and is exempt
-- through NOT has_table_privilege.
SELECT 'messages_no_uncovered_update_col_grants', count(*)::int
FROM pg_attribute a
CROSS JOIN (VALUES ('anon'), ('authenticated')) r(role)
WHERE a.attrelid = 'public.messages'::regclass
  AND a.attnum > 0 AND NOT a.attisdropped
  AND NOT (r.role = 'authenticated' AND a.attname IN ('status', 'draft_preview'))
  AND has_column_privilege(r.role, a.attrelid, a.attname, 'UPDATE')
  AND NOT has_table_privilege(r.role, a.attrelid, 'UPDATE')
UNION ALL

-- PUBLIC (grantee 0) cannot be seen through has_*_privilege as a role: no ACL
-- entry for PUBLIC may carry UPDATE on the table or on any column.
SELECT 'messages_public_no_update_acl',
  (SELECT count(*) FROM pg_class c, aclexplode(c.relacl) e
    WHERE c.oid = 'public.messages'::regclass AND e.grantee = 0 AND e.privilege_type = 'UPDATE')::int
  + (SELECT count(*) FROM pg_attribute a, aclexplode(a.attacl) e
      WHERE a.attrelid = 'public.messages'::regclass AND a.attacl IS NOT NULL
        AND e.grantee = 0 AND e.privilege_type = 'UPDATE')::int;
