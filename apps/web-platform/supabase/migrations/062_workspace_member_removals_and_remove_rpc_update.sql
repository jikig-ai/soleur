-- 062_workspace_member_removals_and_remove_rpc_update.sql
-- feat-dsar-departed-member-coverage (#4230, PR #4294) — WORM audit
-- ledger of workspace-member removal events + Art. 17 anonymise RPC
-- + 36-month retention sweep + CREATE OR REPLACE remove_workspace_member
-- so every successful removal appends a row inside the same SECURITY
-- DEFINER body as the DELETE (atomic; FK violation rolls back DELETE).
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(c) legal obligation. Art. 30(1)(g)
-- requires controllers to maintain records of processing activities
-- affecting data subjects across the lifecycle — the join event is
-- captured in workspace_member_attestations (058); the removal event
-- is captured here. PA-19 of the Article 30 register tracks this
-- processing activity.
--
-- RETENTION: 36 months on removed_at. Deviates from the 24-month
-- PA-PII envelope tracked in compliance-posture.md for
-- dsar_export_audit_pii because the limitation horizon under
-- Art. 82(2) varies by member-state (FR 5y / DE 3y / UK 6y for
-- data-protection causes of action); 36 months covers the
-- shortest-jurisdiction floor (DE 3y) while limiting indefinite
-- PII surface. ADR-039 records the rationale.
--
-- WORM contract (mirrors migration 058's workspace_member_attestations
-- pattern). Two bypass paths:
--   1. UPDATE: structural-shape detection. The anonymise RPC issues
--      `UPDATE ... SET removed_user_id = NULL, removed_by_user_id =
--      NULL` for matching rows. The trigger allows the UPDATE iff
--      every PII column transitions NOT NULL → NULL (or stays
--      unchanged) AND every lineage column is unchanged. Any other
--      UPDATE raises P0001. No GUC, no role gate — the column-state
--      transition IS the authorization (mirrors 058:88-91 per
--      learning 2026-05-18-worm-trigger-bypass-role-check-fails-
--      under-postgrest-routing.md).
--   2. DELETE: row-state gating on retention. The trigger allows
--      DELETE iff TG_OP = 'DELETE' AND OLD.removed_at < now() -
--      interval '36 months'. pg_cron's scheduling role is
--      `postgres`, not `service_role`, so role-gated bypasses
--      silently fail per learning
--      2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md.
--      Row-state gates couple the bypass to the Art. 5(1)(e)
--      retention authorization, independent of caller role.
--
-- All other UPDATE/DELETE attempts raise P0001 'is append-only'.
--
-- Cascade order: anonymise_workspace_member_removals(p_user_id)
-- runs from account-delete.ts AFTER anonymise_workspace_member_
-- attestations and BEFORE auth.admin.deleteUser() (the ON DELETE
-- RESTRICT FKs on removed_user_id and removed_by_user_id block the
-- auth-cascade otherwise). Failure to thread this leaves Art. 17
-- erasure broken for any user who has ever been removed from a
-- workspace.
--
-- INSERT path: only public.remove_workspace_member (CREATE OR REPLACE
-- below) inserts rows. TS-level inserts are forbidden by
-- cq-WORM-bypass; verified by grep at AC8. REVOKE INSERT FROM
-- PUBLIC, anon, authenticated below; no owner-insert RLS policy
-- per 2026-05-21-worm-ledger-rls-owner-insert-policy-is-an-rpc-
-- bypass.md.

-- =====================================================================
-- 0. Precondition: public.workspaces must exist (#4338)
-- =====================================================================
-- The CREATE TABLE below has a FK to public.workspaces(id). The FK
-- declaration parses at DDL time, so an IF EXISTS clause cannot guard
-- against a missing referenced table — by the time the FK parser fires,
-- the body has already errored with the cryptic
--   ERROR:  relation "public.workspaces" does not exist
--
-- That error masks the actual drift class: dev-Supabase's
-- _schema_migrations ledger claims 053_organizations_and_workspace_
-- members.sql is applied, but the schema state disagrees. Surface the
-- real class with a self-describing RAISE EXCEPTION + link to the
-- recovery procedure, so the next operator who trips this has a
-- one-click path to fix rather than a three-layer-deep parser trace.
DO $$
BEGIN
  IF to_regclass('public.workspaces') IS NULL THEN
    RAISE EXCEPTION USING
      MESSAGE = 'Migration 062 precondition failed: public.workspaces does not exist.',
      DETAIL  = '_schema_migrations may claim 053_organizations_and_workspace_members is applied while the workspaces table is absent (schema-vs-ledger drift class #4338).',
      HINT    = 'Recovery: knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md (delete the stale ledger rows; the runner re-applies 053-061 on the next CI run).';
  END IF;
END $$;

-- =====================================================================
-- 1. Table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.workspace_member_removals (
  id                  uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- workspace_id is ON DELETE SET NULL (NOT RESTRICT) so the orphan-
  -- org cleanup branch of anonymise_organization_membership (058:442-
  -- 447) can DELETE the workspace without being blocked by an audit
  -- row pointing at it. Once the workspace + org are gone, the
  -- workspace_id loses semantic value anyway — no co-member remains
  -- to read the row via RLS. The row's surviving identifiers
  -- (removed_user_id, removed_by_user_id, removed_at) still serve
  -- DSAR Art. 15 export under the requester's userId scope. See
  -- ADR-039 §Invariants.1 carve-out. The pre-existing
  -- workspace_member_attestations.workspace_id (058:43) is filed
  -- separately as a pre-existing-unrelated defect on `main`.
  workspace_id        uuid         NULL REFERENCES public.workspaces(id) ON DELETE SET NULL,
  -- PII columns — NULL after Art. 17 anonymise.
  removed_user_id     uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  removed_by_user_id  uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  -- Audit lineage — id + removed_at never cleared. (workspace_id
  -- carve-out documented above.)
  removed_at          timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.workspace_member_removals ENABLE ROW LEVEL SECURITY;

-- Column-level posture mirroring 058:59-61. REVOKE table-level
-- writes FIRST per learning
-- 2026-03-20-supabase-column-level-grant-override. No column-level
-- GRANT — all mutations route through SECURITY DEFINER RPCs.
REVOKE UPDATE ON TABLE public.workspace_member_removals FROM PUBLIC, anon, authenticated;
REVOKE DELETE ON TABLE public.workspace_member_removals FROM PUBLIC, anon, authenticated;
REVOKE INSERT ON TABLE public.workspace_member_removals FROM PUBLIC, anon, authenticated;

-- SELECT visible to workspace co-members. RLS deviation from
-- workspace_member_attestations: a departed member CANNOT read their
-- own removal row via this policy (is_workspace_member returns FALSE
-- post-removal). They access it through the DSAR export pipeline
-- (service-role read). This is intentional — the removal row is
-- co-member audit metadata, not the departed user's profile data.
-- See ADR-039 §Invariants.4.
CREATE POLICY removals_select_for_members ON public.workspace_member_removals
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- Covering index for the per-workspace audit-read hot path.
CREATE INDEX IF NOT EXISTS workspace_member_removals_workspace_idx
  ON public.workspace_member_removals (workspace_id, removed_at DESC);

-- =====================================================================
-- 2. WORM trigger (BEFORE UPDATE/DELETE)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.workspace_member_removals_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- DELETE allowed only when the row is past 36-mo retention. The
  -- retention sweep (cron.schedule below) issues this DELETE; pg_cron
  -- runs as `postgres`, so role-gated bypasses cannot apply. Row-state
  -- gating couples the bypass to the Art. 5(1)(e) retention
  -- authorization. See learning
  -- 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md and
  -- 043_tenant_deploy_audit.sql:116-146 for the canonical precedent.
  IF TG_OP = 'DELETE' THEN
    IF OLD.removed_at IS NOT NULL
       AND OLD.removed_at < now() - interval '36 months' THEN
      RETURN OLD;
    END IF;
    RAISE EXCEPTION 'workspace_member_removals is append-only; only rows past 36-month retention may be deleted'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE shape "Art. 17 anonymise OR orphan-org cleanup":
  --   * every PII column AND workspace_id transitions NOT NULL → NULL
  --     (or stays unchanged)
  --   * audit lineage (id, removed_at) unchanged
  -- Mirrors 058:85-121's structural-shape recognition (extended to
  -- cover workspace_id NULL transition for orphan-org cleanup). The
  -- ON DELETE SET NULL on workspace_id triggers an implicit UPDATE
  -- by PostgreSQL when the workspaces row is deleted by
  -- anonymise_organization_membership; this trigger must permit that
  -- transition. Recognised by column-state transition rather than
  -- GUC + role gate per learning
  -- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
  -- routing.md.
  --
  -- Defense-in-depth: anonymise_workspace_member_removals is SECURITY
  -- DEFINER with REVOKE EXECUTE FROM PUBLIC, anon, authenticated;
  -- only service-role-authenticated callers can issue the UPDATE that
  -- matches this shape.
  IF NEW.id              IS DISTINCT FROM OLD.id
    OR NEW.removed_at    IS DISTINCT FROM OLD.removed_at
  THEN
    RAISE EXCEPTION 'workspace_member_removals audit lineage is immutable (id, removed_at)'
      USING ERRCODE = 'P0001';
  END IF;

  -- workspace_id may transition NOT NULL → NULL via the ON DELETE
  -- SET NULL FK cascade when anonymise_organization_membership
  -- deletes the workspace. NULL → NOT NULL or value-change is
  -- rejected (lineage integrity for live rows).
  IF (OLD.workspace_id IS NULL AND NEW.workspace_id IS NOT NULL)
    OR (OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NOT NULL AND NEW.workspace_id IS DISTINCT FROM OLD.workspace_id)
  THEN
    RAISE EXCEPTION 'workspace_member_removals.workspace_id is append-only; only ON DELETE SET NULL transitions permitted'
      USING ERRCODE = 'P0001';
  END IF;

  -- Each PII column must transition NOT NULL → NULL OR stay unchanged.
  -- Any NULL → NOT NULL transition or value-change (NOT NULL → NOT NULL
  -- with different value) is rejected.
  IF (OLD.removed_user_id    IS NULL AND NEW.removed_user_id    IS NOT NULL)
    OR (OLD.removed_user_id    IS NOT NULL AND NEW.removed_user_id    IS NOT NULL AND NEW.removed_user_id    IS DISTINCT FROM OLD.removed_user_id)
    OR (OLD.removed_by_user_id IS NULL AND NEW.removed_by_user_id IS NOT NULL)
    OR (OLD.removed_by_user_id IS NOT NULL AND NEW.removed_by_user_id IS NOT NULL AND NEW.removed_by_user_id IS DISTINCT FROM OLD.removed_by_user_id)
  THEN
    RAISE EXCEPTION 'workspace_member_removals is append-only; only Art. 17 anonymise (NOT NULL → NULL) transitions permitted'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_member_removals_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS workspace_member_removals_no_update ON public.workspace_member_removals;
CREATE TRIGGER workspace_member_removals_no_update
  BEFORE UPDATE ON public.workspace_member_removals
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_removals_no_mutate();

DROP TRIGGER IF EXISTS workspace_member_removals_no_delete ON public.workspace_member_removals;
CREATE TRIGGER workspace_member_removals_no_delete
  BEFORE DELETE ON public.workspace_member_removals
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_removals_no_mutate();

-- =====================================================================
-- 3. anonymise_workspace_member_removals RPC (Art. 17 cascade)
-- =====================================================================
--
-- Clears PII columns to NULL for every removal row where p_user_id is
-- the removed user OR the actor. Workspace_id + removed_at + id stay
-- intact for forensic windows. Called from account-delete.ts AFTER
-- anonymise_workspace_member_attestations and BEFORE
-- auth.admin.deleteUser() per ON DELETE RESTRICT FK ordering.

CREATE OR REPLACE FUNCTION public.anonymise_workspace_member_removals(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.workspace_member_removals
     SET removed_user_id    = NULL,
         removed_by_user_id = NULL
   WHERE removed_user_id    = p_user_id
      OR removed_by_user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_workspace_member_removals(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_workspace_member_removals(uuid)
  TO service_role;

-- =====================================================================
-- 4. CREATE OR REPLACE remove_workspace_member — pasted verbatim from
--    058:267-326 PLUS the INSERT into workspace_member_removals BEFORE
--    the DELETE. All AC-FLOW4 guards preserved (owner-self-remove
--    rejection at line 300; owner-target rejection at line 315; idempotent-
--    not-a-member RETURN 0 at line 312). All SECURITY clauses preserved
--    verbatim (SECURITY DEFINER, SET search_path, REVOKE matrix, GRANT
--    EXECUTE) per Kieran P1-4. The INSERT lands inside the same SECURITY
--    DEFINER body — if it raises (FK violation), the DELETE rolls back
--    atomically (AC2 verifies).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_target_role    text;
  v_rows           int;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  -- Authorize: caller must be an owner of the target workspace.
  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  -- AC-FLOW4: owner cannot remove themselves.
  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot remove themselves; use account-delete to cascade-anonymise instead'
      USING ERRCODE = '22023';
  END IF;

  -- AC-FLOW4 part 2: cannot remove another owner role (preserve
  -- workspace-has-at-least-one-owner invariant). Member-only removal.
  SELECT role INTO v_target_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN 0;  -- already not a member; idempotent
  END IF;

  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'cannot remove another owner; only members can be removed'
      USING ERRCODE = '22023';
  END IF;

  -- ADDED in migration 062 (#4230): append the WORM removal-event row
  -- BEFORE the DELETE so the audit ledger and the membership table
  -- are atomically consistent. If the INSERT raises (e.g., FK
  -- violation on p_user_id / v_caller_user_id), the DELETE rolls back
  -- — AC2 verifies via integration test.
  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id
  ) VALUES (
    p_workspace_id, p_user_id, v_caller_user_id
  );

  DELETE FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid)
  TO authenticated;

-- =====================================================================
-- 5. pg_cron retention sweep at 36 months
-- =====================================================================
--
-- The WORM trigger's row-state DELETE bypass is the authorization
-- substrate; pg_cron just issues the DELETE and the trigger evaluates
-- `OLD.removed_at < now() - interval '36 months'` per row. No GUC, no
-- role gate — those would silently fail per learning
-- 2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md (pg_cron
-- runs as `postgres`, not `service_role`).
--
-- Schedule mirrors 041:382-396 shape. Idempotent — duplicate_object
-- on re-run is no-op.

DO $$
BEGIN
  PERFORM cron.schedule(
    'workspace-member-removals-retention-sweep',
    '0 4 * * *',
    $cron$
      DELETE FROM public.workspace_member_removals
       WHERE removed_at < now() - interval '36 months';
    $cron$
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
