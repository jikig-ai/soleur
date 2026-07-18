-- 134_rls_initplan_hotspots.sql
-- perf: wrap per-row auth.uid() in the hottest RLS policies as (select
-- auth.uid()) so Postgres evaluates it ONCE per query (InitPlan) instead of
-- once per row (auth_rls_initplan advisor finding). Semantics-preserving:
-- only the auth.<fn>() call is wrapped; every other clause is byte-identical.
--
-- Part of the Disk-IO write-reduction PR. This is a read/CPU-initplan
-- optimization (relieves CPU contention on the Micro tier), a DIFFERENT axis
-- from the WAL-cadence backoff in migration 133 — bounded here to the
-- advisor-confirmed hottest tables.
--
-- SCOPE: exactly the 18 policies that /advisors/performance flagged as
-- auth_rls_initplan across the 7 write-churn-priority + read-hot tables
-- (conversations ×5, kb_files ×4, push_subscriptions ×4, messages ×2,
-- routine_run_progress ×1, routine_runs ×1, user_concurrency_slots ×1). The
-- remaining ~40 flagged low-traffic policies are DEFERRED to a labeled
-- follow-up. The 3 `users` guard policies are DELIBERATELY EXCLUDED (their
-- auth.uid() already sits in an uncorrelated scalar subquery Postgres hoists;
-- mangling them re-enables GitHub-installation takeover per mig 016 — pure
-- risk, zero gain).
--
-- CRITICAL — sourced from LIVE pg_policies (2026-07-18), NOT the defining
-- migrations. Several targets were redefined AFTER their original migration:
-- conversations_owner_insert/_update + kb_files_owner_update carry the
-- `AND is_workspace_member(workspace_id, auth.uid())` WITH CHECK conjunct that
-- migration 129 (#6334/ADR-111) added to close cross-tenant row-rehoming.
-- That conjunct is PRESERVED verbatim below — only its auth.uid() argument is
-- wrapped. Sourcing the stale original would silently drop it and reopen #6334.
--
-- NOTE: pg_get_expr reserializes the wrapped form as `( SELECT auth.uid() AS
-- uid)`. AC5 verifies safety by stripping the `(select …)` wrapper from the
-- after-form and asserting BYTE-EQUALITY with the pre-134 before-form, plus
-- polpermissive/polroles/polcmd unchanged — a substring "contains" test cannot
-- catch a dropped conjunct, so a full-expression diff is used instead.
--
-- FORWARD-ONLY, txn-safe (ALTER POLICY only). .down.sql restores every
-- unwrapped form from the same live pre-134 snapshot.
-- Plan: knowledge-base/project/plans/2026-07-18-perf-supabase-disk-io-write-reduction-plan.md

-- conversations (×5)
ALTER POLICY "conversations_owner_delete" ON public.conversations
  USING ((user_id = (select auth.uid())));

ALTER POLICY "conversations_owner_insert" ON public.conversations
  WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));

ALTER POLICY "conversations_owner_select" ON public.conversations
  USING ((user_id = (select auth.uid())));

ALTER POLICY "conversations_owner_update" ON public.conversations
  USING ((user_id = (select auth.uid())))
  WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));

ALTER POLICY "conversations_shared_select" ON public.conversations
  USING (((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, (select auth.uid()))));

-- kb_files (×4)
ALTER POLICY "kb_files_member_insert" ON public.kb_files
  WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));

ALTER POLICY "kb_files_owner_delete" ON public.kb_files
  USING ((user_id = (select auth.uid())));

ALTER POLICY "kb_files_owner_or_shared" ON public.kb_files
  USING (((user_id = (select auth.uid())) OR ((visibility = 'workspace'::text) AND is_workspace_member(workspace_id, (select auth.uid())))));

ALTER POLICY "kb_files_owner_update" ON public.kb_files
  USING ((user_id = (select auth.uid())))
  WITH CHECK (((user_id = (select auth.uid())) AND is_workspace_member(workspace_id, (select auth.uid()))));

-- messages (×2)
ALTER POLICY "messages_workspace_member_insert" ON public.messages
  WITH CHECK (is_workspace_member(workspace_id, (select auth.uid())));

ALTER POLICY "messages_workspace_member_select" ON public.messages
  USING (is_workspace_member(workspace_id, (select auth.uid())));

-- push_subscriptions (×4)
ALTER POLICY "push_subscriptions_workspace_member_delete" ON public.push_subscriptions
  USING (is_workspace_member(workspace_id, (select auth.uid())));

ALTER POLICY "push_subscriptions_workspace_member_insert" ON public.push_subscriptions
  WITH CHECK (is_workspace_member(workspace_id, (select auth.uid())));

ALTER POLICY "push_subscriptions_workspace_member_select" ON public.push_subscriptions
  USING (is_workspace_member(workspace_id, (select auth.uid())));

ALTER POLICY "push_subscriptions_workspace_member_update" ON public.push_subscriptions
  USING (is_workspace_member(workspace_id, (select auth.uid())))
  WITH CHECK (is_workspace_member(workspace_id, (select auth.uid())));

-- routine_run_progress (×1)
ALTER POLICY "routine_run_progress_authenticated_select" ON public.routine_run_progress
  USING (((select auth.uid()) IS NOT NULL));

-- routine_runs (×1)
ALTER POLICY "routine_runs_authenticated_select" ON public.routine_runs
  USING (((select auth.uid()) IS NOT NULL));

-- user_concurrency_slots (×1)
ALTER POLICY "user_concurrency_slots_workspace_member_select" ON public.user_concurrency_slots
  USING (is_workspace_member(workspace_id, (select auth.uid())));
