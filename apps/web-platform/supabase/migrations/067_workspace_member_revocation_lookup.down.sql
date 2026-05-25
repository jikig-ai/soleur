-- 064 down: drop the two new SECURITY DEFINER functions, drop the lookup
-- index, drop the new columns, and restore remove_workspace_member to its
-- mig 062 body. The base table and WORM trigger are unchanged so they
-- need no rollback.

DROP FUNCTION IF EXISTS public.update_workspace_member_role(uuid, uuid, text);
DROP FUNCTION IF EXISTS public.check_my_revocation(timestamptz);

DROP INDEX IF EXISTS public.workspace_member_removals_revocation_lookup_idx;

ALTER TABLE public.workspace_member_removals
  DROP COLUMN IF EXISTS revoked_after,
  DROP COLUMN IF EXISTS revocation_reason;

-- remove_workspace_member rollback: re-CREATE OR REPLACE with the mig 062
-- body. Operators applying 064.down MUST also re-run mig 062 to restore
-- the original function body (since CREATE OR REPLACE in this file would
-- need to duplicate ~70 lines of 062 verbatim and drift risk is high).
-- See knowledge-base/project/learnings/2026-05-22-schema-vs-ledger-drift-on-dev-supabase.md
-- for the recovery procedure.
