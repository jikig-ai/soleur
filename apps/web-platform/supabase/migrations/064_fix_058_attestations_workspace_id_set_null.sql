-- 064_fix_058_attestations_workspace_id_set_null.sql
-- issue #4329 — sister-table fix to PR #4294 (mig 062 workspace_member_removals).
--
-- DEFECT: workspace_member_attestations.workspace_id was created with
-- ON DELETE RESTRICT in mig 058 (058:43). When the account-delete cascade
-- in apps/web-platform/server/account-delete.ts reaches step 3.92
-- (anonymise_organization_membership at 058:419-468), the orphan-org
-- branch issues `DELETE FROM public.workspaces WHERE organization_id = …`
-- (058:445). That DELETE is BLOCKED by any attestation row pointing at
-- those workspaces — auth.admin.deleteUser() never fires; the cascade
-- aborts with `{ success: false }`. A deterministic GDPR Art. 17 erasure
-- failure for any user who sole-owns a workspace they ever invited a
-- member into.
--
-- FIX: mirror the carve-out PR #4294 applied to mig 062's sister table
-- (workspace_member_removals.workspace_id) per ADR-039 §Invariants.1:
--   1. Demote attestations.workspace_id FK to ON DELETE SET NULL.
--   2. DROP NOT NULL on workspace_id (NULL state == "the workspace this
--      attestation referenced no longer exists" — same semantics as 062).
--   3. Rewrite the WORM trigger to admit the implicit NOT NULL → NULL
--      transition issued by the ON DELETE SET NULL cascade.
--
-- All three clauses MUST land in a single multi-clause ALTER TABLE
-- statement (Postgres statement-level atomicity) to prevent the window
-- where the new SET NULL FK could fire on a still-NOT-NULL column.
--
-- DEPLOY NOTE: the sister-table 063 (workspace_member_actions) has the
-- SAME defect class at 063:51 and is tracked separately at #4355 —
-- block the #4284 flag-flip on both being resolved. 063's fix shape may
-- differ (pure-reject trigger at 063:116-124 vs structural-shape here);
-- see #4355 for the pending Option A (FK-only) vs Option B (mirror this
-- pattern) decision.
--
-- TRIGGER REWRITE: structural-shape pattern verbatim from mig 062's
-- workspace_member_removals_no_mutate (062:140-212), adapted for
-- attestations' 5 PII columns + lineage = (id, accepted_at) only
-- (workspace_id REMOVED from strict-immutable lineage; now governed by
-- the explicit NULL-transition admit-arm).
--
-- LEARNINGS APPLIED:
--   - 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md — no
--     role-gate (current_user check is fragile under PostgREST routing).
--     Defense-in-depth via REVOKE matrix + SECURITY DEFINER on the
--     anonymise RPC.
--   - 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
--     routing.md — bypass is structural-state, not role-gated.
--   - 2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-bypass.md
--     — no owner-insert RLS policy on the ledger.
--   - cq-pg-security-definer-search-path-pin-pg-temp — SET search_path
--     = public, pg_temp on the trigger function.
--
-- REFERENCES:
--   - apps/web-platform/supabase/migrations/058_workspace_member_attestations.sql:43, 72-141
--   - apps/web-platform/supabase/migrations/062_workspace_member_removals_and_remove_rpc_update.sql:140-212
--   - apps/web-platform/server/account-delete.ts (cascade steps 3.90 → 3.92)
--   - ADR-038 §Invariants (new) + ADR-039 §Invariants.1 (cross-reference)
--   - knowledge-base/legal/article-30-register.md PA-2, PA-19
--   - #4329 (this issue), #4294 (PR establishing the pattern), #4284
--     (flag-flip follow-through, gated on this + #4355)

-- =====================================================================
-- 1. Preflight: assert the table + constraint exist; abort loudly if not.
-- =====================================================================
--
-- Constraint name follows Postgres-default convention
-- `<tablename>_<columnname>_fkey`. If a target db diverged (operator
-- previously renamed the constraint by hand), the DROP CONSTRAINT IF
-- EXISTS silently leaves the RESTRICT FK in place. Raise loudly so the
-- operator notices BEFORE the migration leaves the table in a half-fixed
-- state.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'workspace_member_attestations'
  ) THEN
    RAISE EXCEPTION 'mig 064 preflight: public.workspace_member_attestations not found. Apply mig 058 first.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'workspace_member_attestations_workspace_id_fkey'
      AND conrelid = 'public.workspace_member_attestations'::regclass
  ) THEN
    RAISE EXCEPTION 'mig 064 preflight: constraint workspace_member_attestations_workspace_id_fkey not found on public.workspace_member_attestations. The constraint name may have diverged on this database; run `\d public.workspace_member_attestations` and rename the actual FK to the canonical name BEFORE re-applying.'
      USING ERRCODE = 'P0001';
  END IF;
END $$;

-- =====================================================================
-- 2. ALTER TABLE: FK demote + DROP NOT NULL in one atomic statement.
-- =====================================================================
--
-- AC2 + AC2.5: single multi-clause ALTER TABLE form (Postgres
-- statement-level atomicity). The comma-separated clauses run as ONE
-- transaction step so the new SET NULL FK never sees a still-NOT-NULL
-- column.

ALTER TABLE public.workspace_member_attestations
  DROP CONSTRAINT IF EXISTS workspace_member_attestations_workspace_id_fkey,
  ADD CONSTRAINT workspace_member_attestations_workspace_id_fkey
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE SET NULL,
  ALTER COLUMN workspace_id DROP NOT NULL;

-- =====================================================================
-- 3. WORM trigger rewrite — structural-shape pattern (mirror 062:140-212)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.workspace_member_attestations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- DELETE always rejected. Use anonymise_workspace_member_attestations
  -- for Art. 17 cascade. (Attestations has no retention sweep — the
  -- audit lineage is preserved indefinitely past account-delete.)
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_member_attestations is append-only; use anonymise_workspace_member_attestations for Art. 17 cascade'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE shape "Art. 17 anonymise OR orphan-org cleanup":
  --   * every PII column transitions NOT NULL → NULL (or stays unchanged)
  --   * workspace_id transitions NOT NULL → NULL (or stays unchanged) —
  --     via the ON DELETE SET NULL cascade from anonymise_organization_membership
  --   * audit lineage (id, accepted_at) unchanged
  --
  -- workspace_id was REMOVED from strict-immutable lineage in mig 064
  -- (was at 058:97-99); it is now governed by the explicit NULL-transition
  -- admit-arm below. Recognized by column-state transition rather than
  -- GUC + role gate per learning 2026-05-18-worm-trigger-bypass-role-
  -- check-fails-under-postgrest-routing.md.
  --
  -- Defense-in-depth: anonymise_workspace_member_attestations is SECURITY
  -- DEFINER with REVOKE EXECUTE FROM PUBLIC, anon, authenticated; only
  -- service-role-authenticated callers can issue the UPDATE that matches
  -- this shape. The ON DELETE SET NULL cascade itself fires as a system
  -- action (no role assertable) — the structural admit-arm handles it.
  IF NEW.id            IS DISTINCT FROM OLD.id
    OR NEW.accepted_at IS DISTINCT FROM OLD.accepted_at
  THEN
    RAISE EXCEPTION 'workspace_member_attestations audit lineage is immutable (id, accepted_at)'
      USING ERRCODE = 'P0001';
  END IF;

  -- workspace_id may transition NOT NULL → NULL via the ON DELETE
  -- SET NULL FK cascade when anonymise_organization_membership
  -- deletes the workspace. NULL → NOT NULL or value-change is
  -- rejected (lineage integrity for live rows).
  IF (OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL)
    OR (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NOT NULL AND NEW.workspace_id IS DISTINCT FROM OLD.workspace_id)
  THEN
    RAISE EXCEPTION 'workspace_member_attestations.workspace_id is append-only; only ON DELETE SET NULL transitions permitted'
      USING ERRCODE = 'P0001';
  END IF;

  -- Each PII column must transition NOT NULL → NULL OR stay unchanged.
  -- Any NULL → NOT NULL transition or value-change (NOT NULL → NOT NULL
  -- with different value) is rejected.
  IF (OLD.inviter_user_id  IS NULL AND NEW.inviter_user_id  IS NOT NULL)
    OR (OLD.inviter_user_id  IS NOT NULL AND NEW.inviter_user_id  IS NOT NULL AND NEW.inviter_user_id  IS DISTINCT FROM OLD.inviter_user_id)
    OR (OLD.invitee_user_id  IS NULL AND NEW.invitee_user_id  IS NOT NULL)
    OR (OLD.invitee_user_id  IS NOT NULL AND NEW.invitee_user_id  IS NOT NULL AND NEW.invitee_user_id  IS DISTINCT FROM OLD.invitee_user_id)
    OR (OLD.attestation_text IS NULL AND NEW.attestation_text IS NOT NULL)
    OR (OLD.attestation_text IS NOT NULL AND NEW.attestation_text IS NOT NULL AND NEW.attestation_text IS DISTINCT FROM OLD.attestation_text)
    OR (OLD.ip_hash          IS NULL AND NEW.ip_hash          IS NOT NULL)
    OR (OLD.ip_hash          IS NOT NULL AND NEW.ip_hash          IS NOT NULL AND NEW.ip_hash          IS DISTINCT FROM OLD.ip_hash)
    OR (OLD.user_agent       IS NULL AND NEW.user_agent       IS NOT NULL)
    OR (OLD.user_agent       IS NOT NULL AND NEW.user_agent       IS NOT NULL AND NEW.user_agent       IS DISTINCT FROM OLD.user_agent)
  THEN
    RAISE EXCEPTION 'workspace_member_attestations is append-only; only Art. 17 anonymise (NOT NULL → NULL) transitions permitted'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_member_attestations_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 4. Re-attach triggers (DROP IF EXISTS first for idempotent re-runs).
-- =====================================================================

DROP TRIGGER IF EXISTS workspace_member_attestations_no_update ON public.workspace_member_attestations;
CREATE TRIGGER workspace_member_attestations_no_update
  BEFORE UPDATE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();

DROP TRIGGER IF EXISTS workspace_member_attestations_no_delete ON public.workspace_member_attestations;
CREATE TRIGGER workspace_member_attestations_no_delete
  BEFORE DELETE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();
