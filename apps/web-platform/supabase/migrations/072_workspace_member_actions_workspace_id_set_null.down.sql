-- Down migration for 072: restore workspace_member_actions.workspace_id
-- to ON DELETE RESTRICT + NOT NULL + pure-reject WORM trigger.

-- =====================================================================
-- 1. Restore pure-reject WORM trigger (mig 063 original)
-- =====================================================================

CREATE OR REPLACE FUNCTION public.workspace_member_actions_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'workspace_member_actions is append-only (WORM); % rejected', TG_OP
    USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.workspace_member_actions_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

-- =====================================================================
-- 2. Restore FK to ON DELETE RESTRICT
-- =====================================================================

ALTER TABLE public.workspace_member_actions
  DROP CONSTRAINT workspace_member_actions_workspace_id_fkey;

ALTER TABLE public.workspace_member_actions
  ADD CONSTRAINT workspace_member_actions_workspace_id_fkey
    FOREIGN KEY (workspace_id) REFERENCES public.workspaces(id)
    ON DELETE RESTRICT;

-- =====================================================================
-- 3. Restore NOT NULL (requires no existing NULL rows)
-- =====================================================================

ALTER TABLE public.workspace_member_actions
  ALTER COLUMN workspace_id SET NOT NULL;

COMMENT ON FUNCTION public.workspace_member_actions_no_mutate() IS
  'WORM trigger — pure-reject for UPDATE and DELETE. Restored by 072 down migration.';
