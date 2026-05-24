-- 064_idempotent_recovery_guards.sql
-- feat-dev-supabase-migration-drift (issue 4325 / 4338 / fixed-by 4339)
-- Delta 3 of the dev-Supabase drift hardening bundle.
--
-- Re-applies CREATE POLICY / ADD CONSTRAINT for the three constructs the
-- 2026-05-22 learning calls out as Branch-A partial-apply survivors. Each
-- is guarded by IF NOT EXISTS in pg_policies / pg_constraint so the
-- migration is a strict no-op against a healthy schema (no DROP, no
-- noise in pg_policies churn) and a one-shot recovery against a schema
-- where 058 or 060 partial-applied.
--
-- Why this exists (post-mortem of issue 4338): the original 053-061 chain
-- applied to dev with non-idempotent CREATE POLICY / ADD CONSTRAINT
-- statements. The Branch A recovery (DELETE _schema_migrations rows; let
-- the runner re-apply) trips on the surviving constructs because the
-- forward bodies have no DROP-IF-EXISTS or pg_policies-membership guard.
--
-- This migration is the canonical idempotency layer. Future migrations
-- whose forward body introduces a policy or constraint SHOULD use the
-- DO $$ IF NOT EXISTS (...) END $$ pattern below to avoid the same trap.
--
-- Per FR1 of the spec (knowledge-base/project/specs/feat-dev-supabase-
-- migration-drift-4325/spec.md): every cross-file FK target gets a
-- to_regclass precondition. mig 064 references three tables created by
-- other migrations (workspace_member_attestations from 058,
-- workspace_members from 053, user_session_state from 060); each gets
-- a self-describing precondition block below.

-- =====================================================================
-- Preconditions: cross-file relations must exist before guard re-create
-- =====================================================================

DO $$
BEGIN
  IF to_regclass('public.workspace_member_attestations') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 064 precondition failed: public.workspace_member_attestations does not exist.',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
  IF to_regclass('public.workspace_members') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 064 precondition failed: public.workspace_members does not exist.',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
  IF to_regclass('public.user_session_state') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 064 precondition failed: public.user_session_state does not exist.',
      DETAIL  = 'Schema-vs-ledger drift class (issue 4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md';
  END IF;
END $$;

-- =====================================================================
-- 1. attestations_select_for_members on public.workspace_member_attestations
--    (originally created by mig 058 line 64)
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'workspace_member_attestations'
       AND policyname = 'attestations_select_for_members'
  ) THEN
    CREATE POLICY attestations_select_for_members ON public.workspace_member_attestations
      FOR SELECT TO authenticated
      USING (public.is_workspace_member(workspace_id, auth.uid()));
  END IF;
END $$;

-- =====================================================================
-- 2. workspace_members_attestation_id_fkey constraint on public.workspace_members
--    (originally added by mig 058 line 148)
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'workspace_members_attestation_id_fkey'
       AND conrelid = 'public.workspace_members'::regclass
  ) THEN
    ALTER TABLE public.workspace_members
      ADD CONSTRAINT workspace_members_attestation_id_fkey
      FOREIGN KEY (attestation_id) REFERENCES public.workspace_member_attestations(id) ON DELETE RESTRICT;
  END IF;
END $$;

-- =====================================================================
-- 3. user_session_state_owner_select on public.user_session_state
--    (originally created by mig 060 line 41)
-- =====================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'user_session_state'
       AND policyname = 'user_session_state_owner_select'
  ) THEN
    CREATE POLICY user_session_state_owner_select ON public.user_session_state
      FOR SELECT TO authenticated
      USING (auth.uid() = user_id);
  END IF;
END $$;
