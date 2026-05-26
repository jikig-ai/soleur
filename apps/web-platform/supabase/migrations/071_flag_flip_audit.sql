-- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest
-- LIA: knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md

CREATE TABLE public.flag_flip_audit (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  flag_name text NOT NULL,
  env text NOT NULL CHECK (env IN ('dev','prd')),
  target text NOT NULL,
  action text NOT NULL CHECK (action IN ('on','off','create','archive')),
  before_bool bool,
  after_bool bool,
  actor text NOT NULL CHECK (actor ~ '^[a-z0-9._+-]+@[a-z0-9.-]+\.[a-z]{2,}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  retention_until timestamptz NOT NULL DEFAULT (now() + interval '7 years')
);
ALTER TABLE public.flag_flip_audit ENABLE ROW LEVEL SECURITY;

CREATE FUNCTION public.flag_flip_audit_no_update() RETURNS trigger
  LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'flag_flip_audit is WORM (insert-only); UPDATE forbidden';
END $$;
REVOKE ALL ON FUNCTION public.flag_flip_audit_no_update() FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.flag_flip_audit_no_delete() RETURNS trigger
  LANGUAGE plpgsql SECURITY INVOKER SET search_path = public, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' AND OLD.retention_until IS NOT NULL AND OLD.retention_until < now() THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'flag_flip_audit is WORM; DELETE only permitted for retention sweep on expired rows';
END $$;
REVOKE ALL ON FUNCTION public.flag_flip_audit_no_delete() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER trg_flag_flip_audit_no_update
  BEFORE UPDATE ON public.flag_flip_audit
  FOR EACH ROW EXECUTE FUNCTION public.flag_flip_audit_no_update();

CREATE TRIGGER trg_flag_flip_audit_no_delete
  BEFORE DELETE ON public.flag_flip_audit
  FOR EACH ROW EXECUTE FUNCTION public.flag_flip_audit_no_delete();

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
