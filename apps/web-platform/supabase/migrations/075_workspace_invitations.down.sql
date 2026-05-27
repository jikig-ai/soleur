-- 075_workspace_invitations.down.sql — rollback

DROP FUNCTION IF EXISTS public.lookup_invitation_by_token(text);
DROP FUNCTION IF EXISTS public.anonymise_workspace_invitations(uuid);
DROP FUNCTION IF EXISTS public.decline_workspace_invitation(uuid, uuid);
DROP FUNCTION IF EXISTS public.accept_workspace_invitation(uuid, uuid);
DROP FUNCTION IF EXISTS public.create_workspace_invitation(uuid, text, text, text, text, uuid);
DROP TRIGGER IF EXISTS workspace_invitations_no_delete ON public.workspace_invitations;
DROP TRIGGER IF EXISTS workspace_invitations_no_update ON public.workspace_invitations;
DROP FUNCTION IF EXISTS public.workspace_invitations_no_mutate();
DROP TABLE IF EXISTS public.workspace_invitations;
