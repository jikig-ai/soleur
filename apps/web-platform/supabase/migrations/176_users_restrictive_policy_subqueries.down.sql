-- 176_users_restrictive_policy_subqueries.down.sql
-- Restores the three original self-subquery policies from migrations 016/017
-- and drops the users_own_* helper functions. This knowingly reinstates the
-- InitPlan seq-scan pathology that #10764 records — rollback restores the
-- pre-176 catalog exactly, matching the convention that a down file reproduces
-- the prior state, defects included.

DROP POLICY IF EXISTS "Users cannot update github_username directly" ON public.users;
CREATE POLICY "Users cannot update github_username directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    github_username IS NOT DISTINCT FROM (SELECT github_username FROM public.users WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Users cannot update kb_sync_history directly" ON public.users;
CREATE POLICY "Users cannot update kb_sync_history directly"
  ON public.users
  AS RESTRICTIVE
  FOR UPDATE
  USING (true)
  WITH CHECK (
    kb_sync_history IS NOT DISTINCT FROM (SELECT kb_sync_history FROM public.users WHERE id = auth.uid())
  );

DROP POLICY IF EXISTS "Prevent client health_snapshot update" ON public.users;
CREATE POLICY "Prevent client health_snapshot update" ON public.users
  AS RESTRICTIVE FOR UPDATE TO authenticated
  USING (
    health_snapshot IS NOT DISTINCT FROM (SELECT health_snapshot FROM public.users WHERE id = auth.uid())
  );

DROP FUNCTION IF EXISTS public.users_own_github_username();
DROP FUNCTION IF EXISTS public.users_own_kb_sync_history();
DROP FUNCTION IF EXISTS public.users_own_health_snapshot();
