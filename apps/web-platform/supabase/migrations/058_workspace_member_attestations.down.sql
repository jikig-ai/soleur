-- 054_workspace_member_attestations.down.sql
-- Reverse migration. Order: RPCs → FK → triggers → policy → table.

DROP FUNCTION IF EXISTS public.anonymise_organization_membership(uuid);
DROP FUNCTION IF EXISTS public.anonymise_workspace_members(uuid);
DROP FUNCTION IF EXISTS public.anonymise_workspace_member_attestations(uuid);
DROP FUNCTION IF EXISTS public.remove_workspace_member(uuid, uuid);
DROP FUNCTION IF EXISTS public.invite_workspace_member(uuid, uuid, text, text, text);

ALTER TABLE public.workspace_members
  DROP CONSTRAINT IF EXISTS workspace_members_attestation_id_fkey;

DROP TRIGGER IF EXISTS workspace_member_attestations_no_update ON public.workspace_member_attestations;
DROP TRIGGER IF EXISTS workspace_member_attestations_no_delete ON public.workspace_member_attestations;
DROP FUNCTION IF EXISTS public.workspace_member_attestations_no_mutate();

DROP POLICY IF EXISTS attestations_select_for_members ON public.workspace_member_attestations;

DROP INDEX IF EXISTS public.workspace_member_attestations_workspace_idx;
DROP TABLE IF EXISTS public.workspace_member_attestations;
