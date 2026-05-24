-- Down migration for 066: restore the statement-level "no-mutate"
-- WORM trigger from mig 037.
--
-- WARNING: this re-introduces the Art-17 cascade deadlock fixed by 066.

CREATE OR REPLACE FUNCTION public.audit_byok_use_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'audit_byok_use is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

DROP TRIGGER IF EXISTS audit_byok_use_no_update ON public.audit_byok_use;
CREATE TRIGGER audit_byok_use_no_update
  BEFORE UPDATE ON public.audit_byok_use
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.audit_byok_use_no_mutate();

DROP TRIGGER IF EXISTS audit_byok_use_no_delete ON public.audit_byok_use;
CREATE TRIGGER audit_byok_use_no_delete
  BEFORE DELETE ON public.audit_byok_use
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.audit_byok_use_no_mutate();
