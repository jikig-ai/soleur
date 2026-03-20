-- Remediation: null out fabricated tc_accepted_at timestamps
--
-- Bug: PR #898 introduced a fallback INSERT in callback/route.ts that
-- unconditionally set tc_accepted_at = now() regardless of whether the
-- user accepted T&C. Fixed in PR #927. This migration remediates any
-- rows created by the buggy fallback path.
--
-- Discriminator: Join auth.users to check raw_user_meta_data->>'tc_accepted'.
-- Rows where tc_accepted_at IS NOT NULL but the user metadata does not
-- confirm T&C acceptance are fabricated and must be nulled.
--
-- GDPR Article 7(1): Controller must demonstrate consent was given.
-- Fabricated timestamps fail this requirement. This remediation is itself
-- evidence of the controller's corrective action (documented in PR #927,
-- issue #934, and this migration's git history).
--
-- Auth schema safety: This migration only READS from auth.users (via JOIN).
-- It does NOT modify any auth-managed tables, columns, or constraints.
--
-- Idempotent: safe to run multiple times. The WHERE clause excludes rows
-- where tc_accepted_at is already NULL.
--
-- Not reversible: fabricated timestamps are intentionally discarded.
-- Restoring them would re-create false consent evidence.

-- Dry-run: uncomment to preview affected rows before executing
-- SELECT u.id, u.email, u.tc_accepted_at, u.created_at,
--        a.raw_user_meta_data->>'tc_accepted' as tc_meta
-- FROM public.users u
-- JOIN auth.users a ON a.id = u.id
-- WHERE u.tc_accepted_at IS NOT NULL
--   AND (a.raw_user_meta_data->>'tc_accepted') IS DISTINCT FROM 'true';

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
