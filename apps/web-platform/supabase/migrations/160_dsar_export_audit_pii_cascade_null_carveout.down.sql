-- 160_dsar_export_audit_pii_cascade_null_carveout.down.sql
-- Reverse 160: restore the mig-087 WORM body (no Art-17 carve-out).
-- WARNING: reverting reinstates the defect — auth.admin.deleteUser 500s
-- again for any user with a dsar_export_audit_pii row. Only run this to
-- roll back a broken 160 deploy.

CREATE OR REPLACE FUNCTION public.dsar_export_audit_pii_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'dsar_export_audit_pii is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.dsar_export_audit_pii_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;
