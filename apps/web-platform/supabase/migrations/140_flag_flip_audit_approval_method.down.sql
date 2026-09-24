-- 140_flag_flip_audit_approval_method.down.sql (#8486, ADR-249)
--
-- ROLLBACK ORDER. Revert the helper change in plugins/soleur/scripts/audit-flag-flip.sh
-- (the body key p_approval_method) and let that revert reach the operator's
-- INSTALLED plugin copy BEFORE this down migration runs. A helper that still
-- sends p_approval_method against the 7-arg function gets a PostgREST non-2xx,
-- and every flag write then exits 4 before any mutation.
--
-- ORDER INSIDE THIS FILE is load-bearing: drop the 8-arg function FIRST. While
-- the 8-arg DEFAULT NULL function exists, recreating the 7-arg one makes every
-- 7-key call ambiguous ("function ... is not unique").
--
-- DATA LOSS. Dropping the column destroys every recorded approval_method value.
-- The rows themselves (WORM) are untouched.

BEGIN;

DROP FUNCTION IF EXISTS public.audit_flag_flip(text,text,text,text,bool,bool,text,text);

CREATE FUNCTION public.audit_flag_flip(
  p_flag_name text, p_env text, p_target text, p_action text,
  p_before_bool bool, p_after_bool bool, p_actor text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.flag_flip_audit (flag_name, env, target, action, before_bool, after_bool, actor)
  VALUES (p_flag_name, p_env, p_target, p_action, p_before_bool, p_after_bool, lower(p_actor))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text) TO service_role;

ALTER TABLE public.flag_flip_audit DROP COLUMN IF EXISTS approval_method;

COMMIT;
