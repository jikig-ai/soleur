-- 130_authorize_template_grant_ownership_guard.down.sql (#6336)
--
-- Restore the exact pre-130 (mig-053) authorize_template body WITHOUT the
-- p_grant_id ownership guard. CREATE OR REPLACE (089.down idiom) — NOT a DROP:
-- a DROP would sever the `authenticated` EXECUTE grant and break the
-- first-send-IS-authorization write path on rollback. search_path pin and the
-- REVOKE/GRANT/COMMENT block are re-stated verbatim.
--
-- No top-level BEGIN/COMMIT (run-migrations.sh --single-transaction).

CREATE OR REPLACE FUNCTION public.authorize_template(
  p_template_hash text,
  p_action_class  text,
  p_grant_id      uuid
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_existing_id uuid;
  v_new_id uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'authorize_template: authenticated session required'
      USING ERRCODE = '42501';
  END IF;

  -- Input validation (defense-in-depth alongside the column CHECKs).
  IF p_template_hash IS NULL OR length(p_template_hash) < 1 OR length(p_template_hash) > 128 THEN
    RAISE EXCEPTION 'authorize_template: invalid template_hash length'
      USING ERRCODE = '22023';
  END IF;
  IF p_action_class IS NULL OR p_action_class !~ '^[a-z][a-z0-9_.]*$' OR length(p_action_class) > 64 THEN
    RAISE EXCEPTION 'authorize_template: invalid action_class'
      USING ERRCODE = '22023';
  END IF;

  BEGIN
    INSERT INTO public.template_authorizations (
      founder_id, template_hash, action_class, grant_id
    )
    VALUES (
      v_founder_id, p_template_hash, p_action_class, p_grant_id
    )
    RETURNING id INTO v_new_id;
    RETURN v_new_id;
  EXCEPTION
    WHEN unique_violation THEN
      SELECT id INTO v_existing_id
        FROM public.template_authorizations
       WHERE founder_id = v_founder_id
         AND template_hash = p_template_hash
       ORDER BY authorized_at DESC
       LIMIT 1;
      IF v_existing_id IS NULL THEN
        RAISE;
      END IF;
      RETURN v_existing_id;
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.authorize_template(text, text, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_template(text, text, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.authorize_template(text, text, uuid) IS
  'First-send-IS-authorization writer. INSERTs a template_authorizations '
  'row for the calling founder. Idempotent on 23505 partial-UNIQUE '
  'conflict (returns existing active row''s id). Art. 7(3) "specific" + '
  '"informed" consent — call site is the founder''s Send click.';
