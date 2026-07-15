-- 129_rls_write_check_workspace_member.sql (#6334)
--
-- Tenant-boundary WITH CHECK gap: the write-side policies on `conversations`
-- and `kb_files` re-check only `user_id = auth.uid()`, NOT that the row's
-- NEW `workspace_id` references a workspace the caller is a member of. So a
-- row owner can:
--   * UPDATE … SET workspace_id = <other-ws>  → re-home a row into a
--     workspace they are not a member of (conversations + kb_files), OR
--   * INSERT a conversation directly with workspace_id = <other-ws>
--     (conversations_owner_insert has no membership check — kb_files INSERT
--     already carries it, so the INSERT gap is conversations-specific).
-- Either way the row lands in a non-member workspace where
-- `conversations_shared_select` / `kb_files_*_select` expose it to that
-- workspace's members (cross-tenant injection).
--
-- Fix: add `public.is_workspace_member(workspace_id, auth.uid())` to the
-- WITH CHECK of all three write-side policies, mirroring the INSERT precedent
-- (kb_files_member_insert, 077:46-51) and the workspace-keyed sweep precedent
-- (kb_share_links_workspace_member_all / push_subscriptions_workspace_member_update,
-- 059:148-153,192-195). The `user_id = auth.uid()` owner-binding is retained.
--
-- is_workspace_member (053_organizations_and_workspace_members.sql:115-137) is
-- SECURITY DEFINER + plpgsql (non-inlinable) so it runs at the function owner's
-- RLS context; EXECUTE is granted to authenticated. Callable from a policy
-- predicate as `public.is_workspace_member(workspace_id, auth.uid())`.
--
-- No top-level BEGIN/COMMIT — run-migrations.sh wraps each file
-- --single-transaction (learning build-errors/2026-05-25-migration-body-no-top-level-begin-commit).
--
-- Ref #6334; found by #6307 (RLS/authz-fuzz harness Phase 5); ADR-111.

-- conversations UPDATE — sole authoritative def: 075_conversation_visibility.sql:67-70
DROP POLICY IF EXISTS conversations_owner_update ON public.conversations;
CREATE POLICY conversations_owner_update ON public.conversations
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_workspace_member(workspace_id, auth.uid())
  );

-- conversations INSERT — sole authoritative def: 075_conversation_visibility.sql:63-65
-- (deepen-plan Path C: INSERT-placement into a non-member workspace)
DROP POLICY IF EXISTS conversations_owner_insert ON public.conversations;
CREATE POLICY conversations_owner_insert ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_workspace_member(workspace_id, auth.uid())
  );

-- kb_files UPDATE — sole authoritative def: 077_kb_files_metadata.sql:54-57
DROP POLICY IF EXISTS kb_files_owner_update ON public.kb_files;
CREATE POLICY kb_files_owner_update ON public.kb_files
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND public.is_workspace_member(workspace_id, auth.uid())
  );
