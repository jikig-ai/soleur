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
-- audit_byok_use_no_mutate's founder_id gate (mig 066; the app.worm_bypass
-- GUC it merges is mig 087's) — allow an UPDATE whose only change is
-- `user_id: NOT NULL -> NULL` (the exact transition the SET NULL cascade
-- performs); every other column must be structurally unchanged, so the
-- carve-out cannot be used to mutate the audit trail. DELETE stays
-- universally blocked; app.worm_bypass stays the privileged bypass for
-- the anonymise RPC.
--
-- Initiator check (harder than the 066 precedent): the carve-out also
-- requires that OLD.user_id no longer resolve to a live auth.users row.
-- RI actions fire after the parent row is removed, so the cascade passes
-- — while a direct `UPDATE ... SET user_id = NULL` from a privileged
-- role (service_role bypasses the table's zero-policy RLS) against a LIVE
-- user's audit row is rejected. Without it the gate would let any caller
-- holding UPDATE permanently de-link Art. 5(2) attribution. A dangling
-- non-NULL user_id (only reachable via an RI-bypassed delete) can also be
-- nulled — acceptable: attribution was already destroyed out-of-band and
-- the gate can never re-attribute (NEW.user_id IS NULL required).
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
  -- edit audit content. The NOT EXISTS conjunct binds the transition to
  -- an actually-deleted parent: the cascade fires it after the auth.users
  -- row is gone; a direct UPDATE on a live user's row cannot satisfy it.
  IF TG_OP = 'UPDATE' THEN
    IF OLD.user_id IS NOT NULL
       AND NEW.user_id IS NULL
       AND (to_jsonb(NEW) - 'user_id') = (to_jsonb(OLD) - 'user_id')
       AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = OLD.user_id)
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

COMMENT ON FUNCTION public.dsar_export_audit_pii_no_mutate() IS
  'WORM gate for dsar_export_audit_pii. Allows UPDATE only via the '
  'app.worm_bypass bypass (the anonymise RPC) or the Art-17 SET NULL '
  'cascade transition (user_id NOT NULL -> NULL, all other columns '
  'structurally unchanged, parent auth.users row already gone). DELETE '
  'is universally blocked.';

COMMENT ON COLUMN public.dsar_export_audit_pii.user_id IS
  'NULL after Art-17 erasure: the auth-delete cascade nulls this FK '
  '(ON DELETE SET NULL, mig 041 — the audit row survives anonymised for '
  'Art. 5(2) accountability). Analytics joins must treat NULL as the '
  'anonymised state, not a data gap.';
