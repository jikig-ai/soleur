-- 064_fix_058_attestations_workspace_id_set_null.down.sql
-- Reverts mig 064. Restores RESTRICT FK + NOT NULL + the original
-- 058:72-125 trigger body verbatim.
--
-- The verbatim copy is load-bearing — AC10 includes a parity test that
-- diffs the body extracted from this file against 058's source body
-- (post-comment-strip, post-whitespace-collapse). Edits to one MUST be
-- mirrored to the other.

-- =====================================================================
-- 0. 0-row guard on workspace_id IS NULL.
-- =====================================================================
--
-- Per plan §3.1: attestations is expected to have rows (it accumulates
-- audit lineage). The guard targets the specific class that breaks
-- `SET NOT NULL` — any row whose workspace_id was nulled by an orphan-org
-- cleanup post-064. SET NOT NULL would fail with a generic Postgres error;
-- the explicit guard surfaces the class with a clearer message + recovery
-- hint (restore-from-backup OR delete-affected-rows-with-CLO-signoff).

DO $$
DECLARE v_null_count int;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public'
      AND table_name = 'workspace_member_attestations'
  ) THEN
    EXECUTE 'SELECT count(*) FROM public.workspace_member_attestations WHERE workspace_id IS NULL'
      INTO v_null_count;
    IF v_null_count > 0 THEN
      RAISE EXCEPTION 'Refusing to revert mig 064: % rows have workspace_id NULL (set by orphan-org cleanup post-064). Down-migration would either re-link them to dead workspaces (impossible) or fail at SET NOT NULL. Restore from backup OR delete affected rows after CLO sign-off.', v_null_count
        USING ERRCODE = 'P0001';
    END IF;
  END IF;
END $$;

-- =====================================================================
-- 1. Restore the original 058:72-125 trigger body verbatim.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.workspace_member_attestations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- DELETE always rejected. Use anonymise_workspace_member_attestations
  -- for Art. 17 cascade.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'workspace_member_attestations is append-only; use anonymise_workspace_member_attestations for Art. 17 cascade'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE shape "Art. 17 anonymise":
  --   * every PII column transitions NOT NULL → NULL
  --   * audit lineage (id, workspace_id, accepted_at) unchanged
  -- Mirrors migration 048 §scope_grants_no_mutate Shape 2. Recognized
  -- by structural shape rather than GUC + role gate per learning
  -- 2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-
  -- routing.md.
  --
  -- Defense-in-depth: anonymise_workspace_member_attestations is
  -- SECURITY DEFINER with `REVOKE EXECUTE FROM PUBLIC, anon,
  -- authenticated`; only service-role-authenticated callers can issue
  -- the UPDATE that matches this shape.
  IF NEW.id              IS DISTINCT FROM OLD.id
    OR NEW.workspace_id  IS DISTINCT FROM OLD.workspace_id
    OR NEW.accepted_at   IS DISTINCT FROM OLD.accepted_at
  THEN
    RAISE EXCEPTION 'workspace_member_attestations audit lineage is immutable'
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
-- 2. Re-attach triggers (idempotent).
-- =====================================================================

DROP TRIGGER IF EXISTS workspace_member_attestations_no_update ON public.workspace_member_attestations;
CREATE TRIGGER workspace_member_attestations_no_update
  BEFORE UPDATE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();

DROP TRIGGER IF EXISTS workspace_member_attestations_no_delete ON public.workspace_member_attestations;
CREATE TRIGGER workspace_member_attestations_no_delete
  BEFORE DELETE ON public.workspace_member_attestations
  FOR EACH ROW EXECUTE FUNCTION public.workspace_member_attestations_no_mutate();

-- =====================================================================
-- 3. Revert ALTER TABLE: restore RESTRICT FK + NOT NULL in one statement.
-- =====================================================================
--
-- Same atomic-statement rationale as the up migration: all three clauses
-- execute as one transaction step. SET NOT NULL would fail at this point
-- if any workspace_id IS NULL row exists — but the 0-row guard above
-- already aborted in that case with a clearer message.

ALTER TABLE public.workspace_member_attestations
  DROP CONSTRAINT IF EXISTS workspace_member_attestations_workspace_id_fkey,
  ADD CONSTRAINT workspace_member_attestations_workspace_id_fkey
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  ALTER COLUMN workspace_id SET NOT NULL;
