-- #4906 — service-role-only, RLS-bypassing append to a target user's
-- public.users.kb_sync_history, keyed by an explicit p_user_id parameter.
--
-- Background:
--   `workspace-reconcile-on-push.ts` attributes each reconciled workspace's
--   kb_sync_history audit row to the workspace OWNER (workspace_members,
--   role='owner') and writes it via `appendKbSyncRow` → the auth.uid()-pinned
--   `append_kb_sync_row` RPC (migration 053). When the owner lookup returns
--   null (an owner-canary invariant drift, ADR-038 N2), all three audit writes
--   were skipped behind `if (ownerId)`, so a successfully self-healed
--   (#4901) owner-less workspace left no forensic trail in the admin analytics
--   audit surface.
--
--   The owner-less reconcile runs in the Inngest worker with NO user JWT, so
--   the 053 RPC's `auth.uid()` pin would `RAISE EXCEPTION 'no auth.uid()'` and
--   lose the row. The correct model is migration 037's `write_byok_audit`: a
--   service-role-only SECURITY DEFINER writer taking the target identity as a
--   parameter.
--
-- Solution:
--   A sibling of `append_kb_sync_row` that takes the target user id as
--   `p_user_id` (no auth.uid() guard), reuses 053's atomic read-merge-cap-write
--   CTE, and is granted to `service_role` ONLY. For solo workspaces
--   `workspaces.id = users.id` (ADR-038 N2), so the workspace id resolves
--   directly to the backing user row. If `p_user_id` is not a users.id (a
--   non-solo / org owner-less workspace), the UPDATE affects zero rows (no
--   error, no row written) — the caller's drift warn still fires.
--
-- Grant note (load-bearing): Supabase runs
--   `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON FUNCTIONS TO
--    anon, authenticated, service_role`, so a bare `REVOKE ALL FROM PUBLIC`
--   does NOT undo the auto-grant to `authenticated`. The explicit named-role
--   `REVOKE … FROM PUBLIC, anon, authenticated` is required so a tenant client
--   cannot call this RPC to write another user's history (037:98-104).
--
-- search_path pin per cq-pg-security-definer-search-path-pin-pg-temp.

CREATE OR REPLACE FUNCTION public.append_kb_sync_row_for_user(
  p_user_id uuid,
  p_row jsonb,
  p_cap int DEFAULT 100
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.users
     SET kb_sync_history = (
       WITH appended AS (
         SELECT elem, ord
           FROM jsonb_array_elements(COALESCE(kb_sync_history, '[]'::jsonb))
                  WITH ORDINALITY t(elem, ord)
         UNION ALL
         SELECT p_row, COALESCE(jsonb_array_length(kb_sync_history), 0) + 1
       ),
       trimmed AS (
         SELECT elem, ord
           FROM appended
           ORDER BY ord DESC
           LIMIT p_cap
       )
       SELECT COALESCE(jsonb_agg(elem ORDER BY ord), '[]'::jsonb)
         FROM trimmed
     )
   WHERE id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.append_kb_sync_row_for_user(uuid, jsonb, int) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.append_kb_sync_row_for_user(uuid, jsonb, int) TO service_role;

COMMENT ON FUNCTION public.append_kb_sync_row_for_user(uuid, jsonb, int) IS
  '#4906 — appends a row to a target user''s public.users.kb_sync_history JSONB array (keyed by p_user_id), capped at p_cap rows. SECURITY DEFINER, service_role-only — the owner-less workspace reconcile path has no auth.uid(), so it cannot use append_kb_sync_row (053). Mirrors the write_byok_audit (037) service-role writer shape. UPDATE affects 0 rows if p_user_id is not a users.id.';
