-- Migration 064 down: revert anonymise_scope_grants to mig 050's
-- single-column UPDATE, and revoke service_role SELECT on
-- workspace_member_actions.
--
-- NOTE: applying this down-migration re-introduces the bug fixed by 064 up
-- (Art. 17 anonymise will fail CHECK 23514). Use only for emergency revert
-- during a deploy issue; expected immediately followed by a forward-fix.

-- =============================================================
-- Part 1 — Revert anonymise_scope_grants to mig 050 body
-- =============================================================

CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  UPDATE public.scope_grants
     SET founder_id = NULL
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_scope_grants(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_scope_grants(uuid)
  TO service_role;

-- =============================================================
-- Part 2 — Revoke service_role SELECT on workspace_member_actions
-- =============================================================

REVOKE SELECT ON public.workspace_member_actions FROM service_role;
