-- Verify 129_rls_write_check_workspace_member.sql (#6334).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails CI
-- verify-migrations (run-verify.sh parses tab-separated (check_name TEXT, bad INT)
-- rows under ON_ERROR_STOP=1).
--
-- FAIL-CLOSED (verify/116 idiom): each check is a `CASE WHEN count(*)=1` aggregate
-- that always emits exactly one row, so a DROPPED or REGRESSED policy yields
-- `bad=1` — NOT a vanished zero-row false-green (run-verify.sh only errors on a
-- whole-file zero-row result, so a per-object ILIKE-only filter would silently
-- disappear if the object were gone).
--
-- verify/129 (not the RLS-fuzz green) is the AUTHORITATIVE proof of the WITH CHECK
-- mechanism: a column-ACL denial and a WITH-CHECK denial are both SQLSTATE 42501,
-- so the fuzz-green alone cannot attribute the denial to the WITH CHECK. Asserting
-- `with_check ILIKE '%is_workspace_member%'` proves the mechanism directly. The
-- second clause asserts the `user_id = <auth.uid()>` owner-binding is RETAINED
-- (not replaced by the membership check) — it requires the `user_id = ` prefix,
-- NOT a bare `%auth.uid()%` (which `is_workspace_member(workspace_id, …auth.uid()…)`
-- would satisfy on its own, letting a dropped owner-binding false-green).
--
-- WRAP-TOLERANT (migration 134, auth_rls_initplan): migration 134 wrapped
-- `auth.uid()` → `(select auth.uid())` for InitPlan hoisting, so pg_policies now
-- deparses the owner-binding as `(user_id = ( SELECT auth.uid() AS uid))` instead
-- of `(user_id = auth.uid())`. The regex `user_id = \(? *(select +)?auth.uid()`
-- matches BOTH the wrapped and the pre-134 unwrapped form while still requiring the
-- `user_id = ` owner-binding prefix (preserving the anti-false-green property). The
-- `is_workspace_member` conjunct is verified live-present on prod post-134.

-- (1) conversations UPDATE carries is_workspace_member + retains auth.uid()
SELECT 'conversations_owner_update_with_check_member' AS check_name,
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int AS bad
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'conversations'
   AND policyname = 'conversations_owner_update'
   AND cmd = 'UPDATE'
   AND with_check ILIKE '%is_workspace_member%'
   AND with_check ~* 'user_id = \(? *(select +)?auth\.uid\(\)'
UNION ALL
-- (2) conversations INSERT carries is_workspace_member + retains auth.uid()
SELECT 'conversations_owner_insert_with_check_member',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'conversations'
   AND policyname = 'conversations_owner_insert'
   AND cmd = 'INSERT'
   AND with_check ILIKE '%is_workspace_member%'
   AND with_check ~* 'user_id = \(? *(select +)?auth\.uid\(\)'
UNION ALL
-- (3) kb_files UPDATE carries is_workspace_member + retains auth.uid()
SELECT 'kb_files_owner_update_with_check_member',
       CASE WHEN count(*) = 1 THEN 0 ELSE 1 END::int
  FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'kb_files'
   AND policyname = 'kb_files_owner_update'
   AND cmd = 'UPDATE'
   AND with_check ILIKE '%is_workspace_member%'
   AND with_check ~* 'user_id = \(? *(select +)?auth\.uid\(\)';
