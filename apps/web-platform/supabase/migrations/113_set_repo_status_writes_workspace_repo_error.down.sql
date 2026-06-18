-- 113_set_repo_status_writes_workspace_repo_error.down.sql
-- Reverse of 113 — restore migration 108's set_repo_status body (the
-- users.repo_error split-write). Schema-only reversal: no data change (the fn is
-- CREATE OR REPLACE'd back; workspaces.repo_error rows written while 113 was live
-- are left intact — harmless, and the gate already prefers them). This re-opens
-- the AC6c member split-write bug, so this down is for emergency rollback only.

BEGIN;

CREATE OR REPLACE FUNCTION public.set_repo_status(
  p_workspace_id uuid,
  p_status       text,
  p_error        text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF NOT public.is_workspace_member(p_workspace_id, v_user_id) THEN
    RAISE EXCEPTION 'caller is not a member of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('ready', 'error') THEN
    RAISE EXCEPTION 'set_repo_status: p_status must be ready|error, got %', p_status
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.workspaces
     SET repo_status         = p_status,
         repo_last_synced_at = CASE WHEN p_status = 'ready' THEN now()
                                    ELSE repo_last_synced_at END
   WHERE id = p_workspace_id;

  UPDATE public.users
     SET repo_error = CASE WHEN p_status = 'ready' THEN NULL ELSE p_error END
   WHERE id = v_user_id;
END;
$$;

REVOKE ALL ON FUNCTION public.set_repo_status(uuid, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_repo_status(uuid, text, text)
  TO authenticated;

COMMIT;
