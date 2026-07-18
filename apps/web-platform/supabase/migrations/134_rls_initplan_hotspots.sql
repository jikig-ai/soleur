-- 134_rls_initplan_hotspots.sql
-- perf: wrap per-row auth.uid() in the hottest RLS policies as (select
-- auth.uid()) so Postgres evaluates it ONCE per query (InitPlan) instead of
-- once per row (auth_rls_initplan advisor finding). Semantics-preserving:
-- only the auth.<fn>() call is wrapped; every other clause is byte-identical.
--
-- Part of the Disk-IO write-reduction PR. This is a read/CPU-initplan
-- optimization (relieves CPU contention on the Micro tier), a DIFFERENT axis
-- from the WAL-cadence backoff in migration 133.
--
-- SCOPE: the 18 policies that /advisors/performance flagged as auth_rls_initplan
-- across the 7 write-churn-priority + read-hot tables (conversations ×5,
-- kb_files ×4, push_subscriptions ×4, messages ×2, routine_run_progress ×1,
-- routine_runs ×1, user_concurrency_slots ×1). The remaining ~40 flagged
-- low-traffic policies are DEFERRED. The 3 `users` guard policies are
-- DELIBERATELY EXCLUDED (mig 016 GitHub-installation-takeover risk).
--
-- CRITICAL — sourced from LIVE pg_policies (2026-07-18), NOT the defining
-- migrations. conversations_owner_insert/_update + kb_files_owner_update carry
-- the `AND is_workspace_member(workspace_id, auth.uid())` WITH CHECK conjunct
-- that migration 129 (#6334/ADR-111) added to close cross-tenant row-rehoming;
-- that conjunct is PRESERVED verbatim below — only its auth.uid() argument is
-- wrapped.
--
-- IF-EXISTS GUARD (dev/prod divergence, hr-dev-prd-distinct-supabase-projects):
-- the policy NAME set was sourced from the PROD project's live pg_policies, but
-- dev and prod are DISTINCT Supabase projects whose RLS state has diverged
-- (e.g. conversations_owner_delete is present on prod but absent on the CI dev
-- DB). `ALTER POLICY` has no IF EXISTS, so each wrap is guarded by a pg_policies
-- existence check: where the target policy is absent, the wrap no-ops (a
-- performance optimization has nothing to optimize there). On prod all 18 exist
-- so every wrap applies; AC5's before/after pg_get_expr diff verifies the prod
-- result.
--
-- NOTE: pg_get_expr reserializes the wrapped form as `( SELECT auth.uid() AS
-- uid)`. AC5 strips the `(select …)` wrapper from the after-form and asserts
-- BYTE-EQUALITY with the pre-134 before-form, plus polpermissive/polroles/polcmd
-- unchanged.
--
-- FORWARD-ONLY, txn-safe. .down.sql restores every unwrapped form (same guard).
-- Plan: knowledge-base/project/plans/2026-07-18-perf-supabase-disk-io-write-reduction-plan.md

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_delete') THEN
    ALTER POLICY "conversations_owner_delete" ON public.conversations
      USING ((user_id = (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_insert') THEN
    ALTER POLICY "conversations_owner_insert" ON public.conversations
      WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_select') THEN
    ALTER POLICY "conversations_owner_select" ON public.conversations
      USING ((user_id = (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_owner_update') THEN
    ALTER POLICY "conversations_owner_update" ON public.conversations
      USING ((user_id = (select auth.uid())))
      WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='conversations' AND policyname='conversations_shared_select') THEN
    ALTER POLICY "conversations_shared_select" ON public.conversations
      USING (((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, (select auth.uid()))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_member_insert') THEN
    ALTER POLICY "kb_files_member_insert" ON public.kb_files
      WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_owner_delete') THEN
    ALTER POLICY "kb_files_owner_delete" ON public.kb_files
      USING ((user_id = (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_owner_or_shared') THEN
    ALTER POLICY "kb_files_owner_or_shared" ON public.kb_files
      USING (((user_id = (select auth.uid())) OR ((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, (select auth.uid())))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='kb_files' AND policyname='kb_files_owner_update') THEN
    ALTER POLICY "kb_files_owner_update" ON public.kb_files
      USING ((user_id = (select auth.uid())))
      WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='messages' AND policyname='messages_workspace_member_insert') THEN
    ALTER POLICY "messages_workspace_member_insert" ON public.messages
      WITH CHECK (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='messages' AND policyname='messages_workspace_member_select') THEN
    ALTER POLICY "messages_workspace_member_select" ON public.messages
      USING (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_delete') THEN
    ALTER POLICY "push_subscriptions_workspace_member_delete" ON public.push_subscriptions
      USING (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_insert') THEN
    ALTER POLICY "push_subscriptions_workspace_member_insert" ON public.push_subscriptions
      WITH CHECK (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_select') THEN
    ALTER POLICY "push_subscriptions_workspace_member_select" ON public.push_subscriptions
      USING (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='push_subscriptions' AND policyname='push_subscriptions_workspace_member_update') THEN
    ALTER POLICY "push_subscriptions_workspace_member_update" ON public.push_subscriptions
      USING (is_workspace_member(workspace_id, (select auth.uid())))
      WITH CHECK (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='routine_run_progress' AND policyname='routine_run_progress_authenticated_select') THEN
    ALTER POLICY "routine_run_progress_authenticated_select" ON public.routine_run_progress
      USING (((select auth.uid()) IS NOT NULL));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='routine_runs' AND policyname='routine_runs_authenticated_select') THEN
    ALTER POLICY "routine_runs_authenticated_select" ON public.routine_runs
      USING (((select auth.uid()) IS NOT NULL));
  END IF;
END $do$; 

DO $do$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='user_concurrency_slots' AND policyname='user_concurrency_slots_workspace_member_select') THEN
    ALTER POLICY "user_concurrency_slots_workspace_member_select" ON public.user_concurrency_slots
      USING (is_workspace_member(workspace_id, (select auth.uid())));
  END IF;
END $do$; 

