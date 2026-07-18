-- 134_rls_initplan_hotspots.down.sql
-- Restore the 18 RLS policies wrapped by 134 to their pre-134 unwrapped form
-- (the live pg_policies snapshot captured 2026-07-18). Every clause is
-- byte-identical to before; only the (select …) wrapper is removed from the
-- auth.uid() calls. The is_workspace_member(...) #6334 conjuncts are preserved.

-- conversations (×5)
ALTER POLICY "conversations_owner_delete" ON public.conversations
  USING ((user_id = auth.uid()));

ALTER POLICY "conversations_owner_insert" ON public.conversations
  WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));

ALTER POLICY "conversations_owner_select" ON public.conversations
  USING ((user_id = auth.uid()));

ALTER POLICY "conversations_owner_update" ON public.conversations
  USING ((user_id = auth.uid()))
  WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));

ALTER POLICY "conversations_shared_select" ON public.conversations
  USING (((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, auth.uid())));

-- kb_files (×4)
ALTER POLICY "kb_files_member_insert" ON public.kb_files
  WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));

ALTER POLICY "kb_files_owner_delete" ON public.kb_files
  USING ((user_id = auth.uid()));

ALTER POLICY "kb_files_owner_or_shared" ON public.kb_files
  USING (((user_id = auth.uid()) OR ((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, auth.uid()))));

ALTER POLICY "kb_files_owner_update" ON public.kb_files
  USING ((user_id = auth.uid()))
  WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));

-- messages (×2)
ALTER POLICY "messages_workspace_member_insert" ON public.messages
  WITH CHECK (is_workspace_member(workspace_id, auth.uid()));

ALTER POLICY "messages_workspace_member_select" ON public.messages
  USING (is_workspace_member(workspace_id, auth.uid()));

-- push_subscriptions (×4)
ALTER POLICY "push_subscriptions_workspace_member_delete" ON public.push_subscriptions
  USING (is_workspace_member(workspace_id, auth.uid()));

ALTER POLICY "push_subscriptions_workspace_member_insert" ON public.push_subscriptions
  WITH CHECK (is_workspace_member(workspace_id, auth.uid()));

ALTER POLICY "push_subscriptions_workspace_member_select" ON public.push_subscriptions
  USING (is_workspace_member(workspace_id, auth.uid()));

ALTER POLICY "push_subscriptions_workspace_member_update" ON public.push_subscriptions
  USING (is_workspace_member(workspace_id, auth.uid()))
  WITH CHECK (is_workspace_member(workspace_id, auth.uid()));

-- routine_run_progress (×1)
ALTER POLICY "routine_run_progress_authenticated_select" ON public.routine_run_progress
  USING ((auth.uid() IS NOT NULL));

-- routine_runs (×1)
ALTER POLICY "routine_runs_authenticated_select" ON public.routine_runs
  USING ((auth.uid() IS NOT NULL));

-- user_concurrency_slots (×1)
ALTER POLICY "user_concurrency_slots_workspace_member_select" ON public.user_concurrency_slots
  USING (is_workspace_member(workspace_id, auth.uid()));
