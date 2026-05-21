-- 055_workspace_keyed_rls_sweep.down.sql
-- Reverse migration. Order: drop new policies → restore old policies →
-- drop view → revert is_message_owner → drop workspace_id columns.

DROP VIEW IF EXISTS public.workspace_cost_aggregate;

-- Revert is_message_owner to the migration 045 shape (per-user
-- semantic).
CREATE OR REPLACE FUNCTION public.is_message_owner(p_message_id uuid, p_user_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_exists boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM public.messages m
    JOIN public.conversations c ON c.id = m.conversation_id
    WHERE m.id = p_message_id
      AND c.user_id = p_user_id
  ) INTO v_exists;
  RETURN v_exists;
END;
$$;

REVOKE ALL ON FUNCTION public.is_message_owner(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_message_owner(uuid, uuid) TO authenticated;

-- Drop new policies + restore originals, table by table.

-- conversations (001)
DROP POLICY IF EXISTS conversations_workspace_member_all ON public.conversations;
CREATE POLICY "Users can manage own conversations" ON public.conversations
  FOR ALL USING (auth.uid() = user_id);

-- messages (001)
DROP POLICY IF EXISTS messages_workspace_member_select ON public.messages;
DROP POLICY IF EXISTS messages_workspace_member_insert ON public.messages;
CREATE POLICY "Users can read own messages" ON public.messages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id AND c.user_id = auth.uid()
    )
  );
CREATE POLICY "Users can insert own messages" ON public.messages FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.conversations c
      WHERE c.id = conversation_id AND c.user_id = auth.uid()
    )
  );

-- kb_share_links (017)
DROP POLICY IF EXISTS kb_share_links_workspace_member_all ON public.kb_share_links;
CREATE POLICY "Users can manage own share links" ON public.kb_share_links
  FOR ALL USING (auth.uid() = user_id);

-- push_subscriptions (020) — 4 policies
DROP POLICY IF EXISTS push_subscriptions_workspace_member_select ON public.push_subscriptions;
DROP POLICY IF EXISTS push_subscriptions_workspace_member_insert ON public.push_subscriptions;
DROP POLICY IF EXISTS push_subscriptions_workspace_member_update ON public.push_subscriptions;
DROP POLICY IF EXISTS push_subscriptions_workspace_member_delete ON public.push_subscriptions;
CREATE POLICY "Users can read own subscriptions"   ON public.push_subscriptions FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert own subscriptions" ON public.push_subscriptions FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own subscriptions" ON public.push_subscriptions FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can delete own subscriptions" ON public.push_subscriptions FOR DELETE USING (auth.uid() = user_id);

-- user_concurrency_slots (029)
DROP POLICY IF EXISTS user_concurrency_slots_workspace_member_select ON public.user_concurrency_slots;
CREATE POLICY slots_owner_read ON public.user_concurrency_slots FOR SELECT USING (auth.uid() = user_id);

-- audit_byok_use (037)
DROP POLICY IF EXISTS audit_byok_use_workspace_member_select ON public.audit_byok_use;
CREATE POLICY audit_byok_use_owner_select ON public.audit_byok_use FOR SELECT USING (auth.uid() = founder_id);

-- dsar_export_jobs (041): policy was already user_id-based both pre
-- and post 055, but the policy name is identical so no change needed.
-- (The 055 forward re-created the same-named policy with the same
-- predicate.)

-- scope_grants (048)
DROP POLICY IF EXISTS scope_grants_workspace_member_select ON public.scope_grants;
CREATE POLICY scope_grants_owner_select ON public.scope_grants FOR SELECT USING (auth.uid() = founder_id);

-- audit_github_token_use (052)
DROP POLICY IF EXISTS audit_github_token_use_workspace_member_select ON public.audit_github_token_use;
CREATE POLICY audit_github_token_use_owner_select ON public.audit_github_token_use FOR SELECT USING (auth.uid() = founder_id);

-- Drop workspace_id columns (each with WORM-trigger-disable cycle for
-- the WORM tables, even though we're DROPping not UPDATEing — ALTER
-- TABLE DROP COLUMN doesn't fire row triggers, but the disable is
-- harmless and mirrors forward-migration shape for audit).

DROP INDEX IF EXISTS public.conversations_workspace_id_idx;
DROP INDEX IF EXISTS public.messages_workspace_id_idx;
DROP INDEX IF EXISTS public.audit_byok_use_workspace_id_idx;

ALTER TABLE public.scope_grants DROP CONSTRAINT IF EXISTS scope_grants_workspace_id_check;

ALTER TABLE public.audit_github_token_use DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.scope_grants DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.dsar_export_jobs DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.audit_byok_use DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.user_concurrency_slots DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.push_subscriptions DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.kb_share_links DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.messages DROP COLUMN IF EXISTS workspace_id;
ALTER TABLE public.conversations DROP COLUMN IF EXISTS workspace_id;
