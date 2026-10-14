-- 161_audit_github_token_use_cascade_null_carveout.down.sql
-- Reverse 161: restore the mig-087 WORM body (no Art-17 carve-out).
-- WARNING: reverting reinstates the defect — auth.admin.deleteUser 500s
-- again for any user with an audit_github_token_use row once such rows
-- exist. Only run this to roll back a broken 161 deploy.

CREATE OR REPLACE FUNCTION public.audit_github_token_use_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $fn$
BEGIN
  -- Art-17 erasure bypass (anonymise_audit_github_token_use).
  IF current_setting('app.worm_bypass', true) = 'on' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  RAISE EXCEPTION 'audit_github_token_use is append-only (PR-H #3244)'
    USING ERRCODE = 'P0001';
END;
$fn$;

REVOKE ALL ON FUNCTION public.audit_github_token_use_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- Restore the pre-161 catalog comment (052's original text — stale under
-- 087's worm_bypass gate too, but faithful to the rollback target).
COMMENT ON FUNCTION public.audit_github_token_use_no_mutate() IS
  'PR-H (#3244) — WORM trigger for audit_github_token_use. Fires '
  'BEFORE UPDATE/DELETE; raises P0001 unless the caller has set '
  'session_replication_role=replica (the documented bypass for the '
  'anonymise_audit_github_token_use RPC). Mirrors mig 037 + 044 '
  'pattern; no role-check bypass (learning 2026-05-18).';
