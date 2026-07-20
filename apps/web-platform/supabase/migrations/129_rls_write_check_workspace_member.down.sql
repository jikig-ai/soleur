-- 129_rls_write_check_workspace_member.down.sql (#6334)
--
-- Revert the three write-side WITH CHECKs to `user_id = auth.uid()` only,
-- restoring the prior (pre-129) definitions verbatim:
--   * conversations_owner_update / conversations_owner_insert — 075:63-70
--   * kb_files_owner_update — 077:54-57
--
-- No top-level BEGIN/COMMIT (run-migrations.sh --single-transaction).

DROP POLICY IF EXISTS conversations_owner_update ON public.conversations;
CREATE POLICY conversations_owner_update ON public.conversations
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS conversations_owner_insert ON public.conversations;
CREATE POLICY conversations_owner_insert ON public.conversations
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS kb_files_owner_update ON public.kb_files;
CREATE POLICY kb_files_owner_update ON public.kb_files
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
