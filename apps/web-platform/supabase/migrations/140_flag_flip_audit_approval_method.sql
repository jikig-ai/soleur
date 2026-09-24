-- 140_flag_flip_audit_approval_method.sql (#8486, ADR-249)
--
-- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest (unchanged from 071)
-- LIA: knowledge-base/legal/legitimate-interest-assessments/2026-05-25-flag-flip-audit-lia.md
--
-- WHAT. The flag-flip WORM audit row records HOW a production write was
-- approved, not only who owns the key. `approval_method` is 'tty-ack' when the
-- operator script's TTY acknowledgement returned in the same process
-- (plugins/soleur/scripts/lib/operator-script.sh soleur_op_ack_or_die sets
-- SOLEUR_OP_ACKED, and plugins/soleur/scripts/audit-flag-flip.sh refuses to
-- append without it). It is self-reported by the script, not proof that a person
-- typed (ADR-249 D6). NULL means the caller did not say.
--
-- SHAPE. Mirrors 137_byok_cap_breach_audit_row.sql: one transaction, an ADD
-- COLUMN on the audit table, DROP of the old signature, a plain CREATE FUNCTION
-- for the new signature (CREATE OR REPLACE cannot change a signature and would
-- leave both overloads live), then REVOKE/GRANT re-issued on the new signature
-- because DROP FUNCTION discards the grants with the function.
--
-- COMPATIBILITY. The new last parameter defaults to NULL, so a caller that still
-- sends the seven 071 keys (an older plugin install) resolves to this function
-- through PostgREST named arguments and records NULL.
--
-- DOWNTIME. None: the column is nullable with no default (no table rewrite), the
-- inline CHECK validates only NULLs on existing rows, and flag_flip_audit is a
-- small, cold, append-only table.

BEGIN;

ALTER TABLE public.flag_flip_audit
  ADD COLUMN approval_method text
  CHECK (approval_method IS NULL OR approval_method IN ('tty-ack'));

DROP FUNCTION IF EXISTS public.audit_flag_flip(text,text,text,text,bool,bool,text);

CREATE FUNCTION public.audit_flag_flip(
  p_flag_name text, p_env text, p_target text, p_action text,
  p_before_bool bool, p_after_bool bool, p_actor text,
  p_approval_method text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.flag_flip_audit (flag_name, env, target, action, before_bool, after_bool, actor, approval_method)
  VALUES (p_flag_name, p_env, p_target, p_action, p_before_bool, p_after_bool, lower(p_actor), p_approval_method)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;
REVOKE ALL ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.audit_flag_flip(text,text,text,text,bool,bool,text,text) TO service_role;

COMMENT ON COLUMN public.flag_flip_audit.approval_method IS
  'How the write was approved: tty-ack = the operator script''s TTY acknowledgement returned in the same process (self-reported, ADR-249); NULL = caller did not say.';

COMMIT;
