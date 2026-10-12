-- 160_dsar_export_audit_pii_cascade_null_carveout.sql
--
-- #9994 / Art-17 erasure defect: auth.admin.deleteUser 500s for every user
-- holding a dsar_export_audit_pii row (i.e., anyone who has ever requested
-- a DSAR export).
--
-- Root cause: dsar_export_audit_pii.user_id is `ON DELETE SET NULL` by
-- design (mig 041 — the audit row survives erasure with user_id=NULL for
-- Art. 5(2) accountability). But the WORM gate
-- dsar_export_audit_pii_no_mutate() raises P0001 on the cascade's internal
-- `UPDATE ... SET user_id = NULL` — GoTrue's delete transaction cannot set
-- app.worm_bypass, so the erasure saga aborts with the opaque 500.
--
-- Fix shape: the Art-17 anonymization carve-out already proven by
-- audit_byok_use_no_mutate's founder_id gate (mig 087) — allow an UPDATE
-- whose only change is `user_id: NOT NULL -> NULL` (the exact transition
-- the SET NULL cascade performs); every other column must be byte-
-- identical, so the carve-out cannot be used to mutate the audit trail.
-- DELETE stays universally blocked; app.worm_bypass stays the privileged
-- bypass for the anonymise RPC.
--
-- Repro (dev, 2026-10-12):
--   DELETE FROM auth.users WHERE id=...
--   -- ERROR: dsar_export_audit_pii is append-only (WORM)
--   -- CONTEXT: SQL statement "UPDATE ONLY public.dsar_export_audit_pii
--   --          SET user_id = NULL WHERE $1 = user_id"

CREATE OR REPLACE FUNCTION public.dsar_export_audit_pii_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Privileged bypass (anonymise_dsar_export_audit_pii sets this GUC).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- DELETE: universally blocked — the audit trail is append-only.
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'dsar_export_audit_pii is append-only (WORM); DELETE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  -- UPDATE: allow only the Art-17 erasure transition the user_id
  -- ON DELETE SET NULL FK performs. Drift-proof check — every column
  -- except user_id must be unchanged, so this gate cannot be used to
  -- edit audit content.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.user_id IS NOT NULL
       AND NEW.user_id IS NULL
       AND (to_jsonb(NEW) - 'user_id') = (to_jsonb(OLD) - 'user_id')
    THEN
      RETURN NEW;  -- Art-17 anonymization carve-out (mirrors audit_byok_use).
    END IF;
    RAISE EXCEPTION 'dsar_export_audit_pii is append-only (WORM); UPDATE rejected'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION public.dsar_export_audit_pii_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;
