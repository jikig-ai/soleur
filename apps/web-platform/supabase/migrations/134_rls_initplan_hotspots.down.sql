-- 134_rls_initplan_hotspots.down.sql
-- Restore the 18 wrapped RLS policies to their pre-134 unwrapped form (the live
-- pg_policies snapshot captured 2026-07-18). Byte-identical to before except the
-- (select …) wrapper is removed from auth.uid(); is_workspace_member(...) #6334
-- conjuncts preserved. Same pg_policies IF-EXISTS guard as the up file (dev/prod
-- RLS state diverges; a wrap that no-op'd on the up side has nothing to restore).

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_delete') THEN
    ALTER POLICY "conversations_owner_delete" ON public.conversations
      USING ((user_id = auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_insert') THEN
    ALTER POLICY "conversations_owner_insert" ON public.conversations
      WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_select') THEN
    ALTER POLICY "conversations_owner_select" ON public.conversations
      USING ((user_id = auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_update') THEN
    ALTER POLICY "conversations_owner_update" ON public.conversations
      USING ((user_id = auth.uid()))
      WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_shared_select') THEN
    ALTER POLICY "conversations_shared_select" ON public.conversations
      USING (((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_member_insert') THEN
    ALTER POLICY "kb_files_member_insert" ON public.kb_files
      WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_owner_delete') THEN
    ALTER POLICY "kb_files_owner_delete" ON public.kb_files
      USING ((user_id = auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_owner_or_shared') THEN
    ALTER POLICY "kb_files_owner_or_shared" ON public.kb_files
      USING (((user_id = auth.uid()) OR ((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, auth.uid()))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_owner_update') THEN
    ALTER POLICY "kb_files_owner_update" ON public.kb_files
      USING ((user_id = auth.uid()))
      WITH CHECK (((user_id = auth.uid()) AND is_workspace_member(workspace_id, auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='messages' AND policyname='messages_workspace_member_insert') THEN
    ALTER POLICY "messages_workspace_member_insert" ON public.messages
      WITH CHECK (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='messages' AND policyname='messages_workspace_member_select') THEN
    ALTER POLICY "messages_workspace_member_select" ON public.messages
      USING (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_delete') THEN
    ALTER POLICY "push_subscriptions_workspace_member_delete" ON public.push_subscriptions
      USING (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_insert') THEN
    ALTER POLICY "push_subscriptions_workspace_member_insert" ON public.push_subscriptions
      WITH CHECK (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_select') THEN
    ALTER POLICY "push_subscriptions_workspace_member_select" ON public.push_subscriptions
      USING (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_update') THEN
    ALTER POLICY "push_subscriptions_workspace_member_update" ON public.push_subscriptions
      USING (is_workspace_member(workspace_id, auth.uid()))
      WITH CHECK (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='routine_run_progress' AND policyname='routine_run_progress_authenticated_select') THEN
    ALTER POLICY "routine_run_progress_authenticated_select" ON public.routine_run_progress
      USING ((auth.uid() IS NOT NULL));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='routine_runs' AND policyname='routine_runs_authenticated_select') THEN
    ALTER POLICY "routine_runs_authenticated_select" ON public.routine_runs
      USING ((auth.uid() IS NOT NULL));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_concurrency_slots' AND policyname='user_concurrency_slots_workspace_member_select') THEN
    ALTER POLICY "user_concurrency_slots_workspace_member_select" ON public.user_concurrency_slots
      USING (is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $do$; 

