-- Remediation: null out fabricated tc_accepted_at timestamps
--
-- Bug: PR #898 introduced a fallback INSERT that unconditionally set
-- tc_accepted_at = now() regardless of actual T&C acceptance. Fixed in
-- PR #927. Rows where auth.users metadata does not confirm acceptance
-- are fabricated and must be nulled.
--
-- GDPR Art 7(1): fabricated consent evidence must be corrected.

DO $$
DECLARE
  _affected integer;
BEGIN
  UPDATE public.users
  SET tc_accepted_at = NULL
  FROM auth.users a
  WHERE public.users.id = a.id
    AND public.users.tc_accepted_at IS NOT NULL
    AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';

  GET DIAGNOSTICS _affected = ROW_COUNT;
  RAISE NOTICE '[007] Remediated % row(s) with fabricated tc_accepted_at', _affected;
END
$$;
