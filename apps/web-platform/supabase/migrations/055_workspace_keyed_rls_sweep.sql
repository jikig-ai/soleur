-- 055_workspace_keyed_rls_sweep.sql
-- feat-team-workspace-multi-user (#4229, PR #4225) — workspace-keyed
-- RLS sweep across the 9 user-keyed tables enumerated in plan §1.3.2.
--
-- DEPENDENCY: migration 053 must have applied successfully (helper
-- public.is_workspace_member + tables organizations, workspaces,
-- workspace_members + backfill).
--
-- For each of the 9 tables:
--   (a) ADD COLUMN workspace_id uuid REFERENCES workspaces(id) ON DELETE RESTRICT
--   (b) Backfill workspace_id from workspace_members WHERE m.user_id =
--       t.user_id (or t.founder_id) AND m.role = 'owner'. The
--       backfilled-owner row is unambiguous post-053 (the canary
--       discriminator guarantees workspaces.id = users.id = owner row).
--       IS DISTINCT FROM discriminator + GET DIAGNOSTICS rc; RAISE NOTICE
--       audit per learning 2026-03-20-gdpr-remediation-migration-
--       discriminator-strategy.
--   (c) ALTER COLUMN workspace_id SET NOT NULL (after backfill verified
--       non-zero for non-empty tables).
--   (d) DROP old auth.uid() = user_id / auth.uid() = founder_id policy.
--   (e) CREATE new is_workspace_member(workspace_id, auth.uid()) policy.
--
-- Plus:
--   * Update public.is_message_owner to be workspace-aware (preserves
--     all 045/019/046 call sites transitively — the function signature
--     is unchanged; the predicate becomes is_workspace_member-routed).
--   * Create public.workspace_cost_aggregate VIEW with
--     security_invoker = true (per plan §G4 + AC4).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: helper updates
-- pin SET search_path = public, pg_temp.
-- Per hr-write-boundary-sentinel-sweep-all-write-sites: AC4 enumerates
-- the FULL output of:
--   git grep -nE "auth\.uid\(\)\s*=\s*(user_id|founder_id)" apps/web-platform/supabase/migrations/
-- Documented exemptions: team_names (018, per NG10), api_keys (001:41,
-- per spec §3 reconciliation row 3 — BYOK keys per-user not workspace),
-- users.id RLS (001:19,23 — user_id is THE user's primary identity, not
-- a workspace ref).

-- =====================================================================
-- 1. conversations (migration 001)
-- =====================================================================

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.conversations c
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = c.user_id
     AND m.workspace_id = c.user_id  -- backfilled-solo canary
     AND m.role         = 'owner'
     AND c.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill conversations] % rows', v_rc;
END $$;

ALTER TABLE public.conversations ALTER COLUMN workspace_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS conversations_workspace_id_idx
  ON public.conversations (workspace_id);

DROP POLICY IF EXISTS "Users can manage own conversations" ON public.conversations;

CREATE POLICY conversations_workspace_member_all ON public.conversations
  FOR ALL TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()))
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 2. messages (migration 001)
-- =====================================================================

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.messages msg
     SET workspace_id = c.workspace_id
    FROM public.conversations c
   WHERE c.id = msg.conversation_id
     AND msg.workspace_id IS DISTINCT FROM c.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill messages] % rows', v_rc;
END $$;

ALTER TABLE public.messages ALTER COLUMN workspace_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS messages_workspace_id_idx
  ON public.messages (workspace_id);

DROP POLICY IF EXISTS "Users can read own messages" ON public.messages;
DROP POLICY IF EXISTS "Users can insert own messages" ON public.messages;

CREATE POLICY messages_workspace_member_select ON public.messages
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

CREATE POLICY messages_workspace_member_insert ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

-- 046 introduced "Users can read own external drafts" + "Users can
-- insert own external drafts" policies on messages. They use
-- (user_id = auth.uid()) directly. Per plan §1.3.7, fold into the
-- workspace-member SELECT/INSERT policies above by dropping the
-- external-drafts-specific ones. The new policies above cover the
-- read/insert surfaces for ALL messages (including external drafts);
-- the tier check inside the original external-drafts INSERT WITH CHECK
-- (`AND tier IN ('external_brand_critical','external_low_stakes')`) is
-- application-layer concern post-sweep — the messages table doesn't
-- have a tier column.

DROP POLICY IF EXISTS "Users can read own external drafts"   ON public.messages;
DROP POLICY IF EXISTS "Users can insert own external drafts" ON public.messages;

-- =====================================================================
-- 3. kb_share_links (migration 017)
-- =====================================================================

ALTER TABLE public.kb_share_links
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.kb_share_links k
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = k.user_id
     AND m.workspace_id = k.user_id
     AND m.role         = 'owner'
     AND k.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill kb_share_links] % rows', v_rc;
END $$;

ALTER TABLE public.kb_share_links ALTER COLUMN workspace_id SET NOT NULL;

DROP POLICY IF EXISTS "Users can manage own share links" ON public.kb_share_links;

CREATE POLICY kb_share_links_workspace_member_all ON public.kb_share_links
  FOR ALL TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()))
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 4. push_subscriptions (migration 020) — 4 policies + 1 WITH CHECK
-- =====================================================================

ALTER TABLE public.push_subscriptions
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.push_subscriptions p
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = p.user_id
     AND m.workspace_id = p.user_id
     AND m.role         = 'owner'
     AND p.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill push_subscriptions] % rows', v_rc;
END $$;

ALTER TABLE public.push_subscriptions ALTER COLUMN workspace_id SET NOT NULL;

DROP POLICY IF EXISTS "Users can read own subscriptions"   ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can insert own subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can update own subscriptions" ON public.push_subscriptions;
DROP POLICY IF EXISTS "Users can delete own subscriptions" ON public.push_subscriptions;

CREATE POLICY push_subscriptions_workspace_member_select ON public.push_subscriptions
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

CREATE POLICY push_subscriptions_workspace_member_insert ON public.push_subscriptions
  FOR INSERT TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

CREATE POLICY push_subscriptions_workspace_member_update ON public.push_subscriptions
  FOR UPDATE TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()))
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));

CREATE POLICY push_subscriptions_workspace_member_delete ON public.push_subscriptions
  FOR DELETE TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 5. user_concurrency_slots (migration 029)
-- =====================================================================

ALTER TABLE public.user_concurrency_slots
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.user_concurrency_slots s
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = s.user_id
     AND m.workspace_id = s.user_id
     AND m.role         = 'owner'
     AND s.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill user_concurrency_slots] % rows', v_rc;
END $$;

ALTER TABLE public.user_concurrency_slots ALTER COLUMN workspace_id SET NOT NULL;

DROP POLICY IF EXISTS slots_owner_read ON public.user_concurrency_slots;

CREATE POLICY user_concurrency_slots_workspace_member_select ON public.user_concurrency_slots
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 6. audit_byok_use (migration 037) — workspace_id ON TOP of founder_id
-- =====================================================================
--
-- audit_byok_use already has founder_id (the BYOK-key-owner). We ADD
-- workspace_id (the WORKSPACE-context of the agent run) without
-- removing founder_id — they encode different concepts post-PR. The
-- byok-lease split (Phase 3) writes BOTH columns: founder_id =
-- keyOwnerUserId, workspace_id = workspaceContextUserId resolved to
-- workspace.

ALTER TABLE public.audit_byok_use
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

-- WORM trigger bypass: audit_byok_use_no_update is FOR EACH STATEMENT
-- BEFORE UPDATE and unconditionally raises. Disable around backfill;
-- re-enable immediately after. The DDL ALTER TABLE … DISABLE/ENABLE
-- TRIGGER pattern is the canonical migration-time bypass for unparam-
-- eterized WORM triggers (vs scope_grants' shape-discriminated trigger
-- which accepts certain UPDATE shapes via the structural-check branch).
ALTER TABLE public.audit_byok_use DISABLE TRIGGER audit_byok_use_no_update;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.audit_byok_use a
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = a.founder_id
     AND m.workspace_id = a.founder_id
     AND m.role         = 'owner'
     AND a.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill audit_byok_use] % rows', v_rc;
END $$;

ALTER TABLE public.audit_byok_use ENABLE TRIGGER audit_byok_use_no_update;

ALTER TABLE public.audit_byok_use ALTER COLUMN workspace_id SET NOT NULL;

CREATE INDEX IF NOT EXISTS audit_byok_use_workspace_id_idx
  ON public.audit_byok_use (workspace_id);

DROP POLICY IF EXISTS audit_byok_use_owner_select ON public.audit_byok_use;

-- Workspace co-members can read each others' BYOK audit rows in the
-- same workspace (cost transparency). founder_id stays on the row so
-- the UI can attribute cost to a specific user within the workspace.
CREATE POLICY audit_byok_use_workspace_member_select ON public.audit_byok_use
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 7. dsar_export_jobs (migration 041)
-- =====================================================================

ALTER TABLE public.dsar_export_jobs
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.dsar_export_jobs d
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = d.user_id
     AND m.workspace_id = d.user_id
     AND m.role         = 'owner'
     AND d.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill dsar_export_jobs] % rows', v_rc;
END $$;

ALTER TABLE public.dsar_export_jobs ALTER COLUMN workspace_id SET NOT NULL;

DROP POLICY IF EXISTS dsar_export_jobs_owner_select ON public.dsar_export_jobs;

-- DSAR export is per-USER (Art. 15 is the user's right; co-members
-- cannot see each others' DSAR jobs even if they share a workspace).
-- Use user_id, NOT is_workspace_member. The workspace_id column is
-- for cost-attribution + cross-workspace export targeting (Phase 7
-- DSAR endpoint extension).
CREATE POLICY dsar_export_jobs_owner_select ON public.dsar_export_jobs
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- =====================================================================
-- 8. scope_grants (migration 048) — workspace_id ON TOP of founder_id
-- =====================================================================
--
-- scope_grants is per-FOUNDER currently. Post-PR, scope grants can be
-- workspace-scoped: an owner's "auto-tier for action-class X" applies
-- to all agent runs within the workspace, regardless of which member
-- triggers them. The workspace_id column captures this. founder_id
-- stays for audit attribution.

ALTER TABLE public.scope_grants
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

-- scope_grants_no_update rejects every UPDATE shape EXCEPT Shape 1
-- (revoke flip) and Shape 2 (Art. 17 anonymise). workspace_id backfill
-- matches neither; disable trigger around backfill.
ALTER TABLE public.scope_grants DISABLE TRIGGER scope_grants_no_update;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.scope_grants g
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = g.founder_id
     AND m.workspace_id = g.founder_id
     AND m.role         = 'owner'
     AND g.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill scope_grants] % rows', v_rc;
END $$;

ALTER TABLE public.scope_grants ENABLE TRIGGER scope_grants_no_update;

-- NOT NULL set carefully: scope_grants has anonymise rows where
-- founder_id IS NULL (the Art. 17 cascade shape). For these rows,
-- workspace_id is also legitimately NULL (the audit row is detached
-- from any live workspace). Allow NULL when founder_id IS NULL.
ALTER TABLE public.scope_grants
  ADD CONSTRAINT scope_grants_workspace_id_check
  CHECK ((founder_id IS NULL AND workspace_id IS NULL) OR (founder_id IS NOT NULL AND workspace_id IS NOT NULL));

DROP POLICY IF EXISTS scope_grants_owner_select ON public.scope_grants;

CREATE POLICY scope_grants_workspace_member_select ON public.scope_grants
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 9. audit_github_token_use (migration 052, "multi_source_dedup" per plan §1.3.2)
-- =====================================================================

ALTER TABLE public.audit_github_token_use
  ADD COLUMN IF NOT EXISTS workspace_id uuid REFERENCES public.workspaces(id) ON DELETE RESTRICT;

-- audit_github_token_use_no_mutate is FOR EACH ROW BEFORE UPDATE OR
-- DELETE, unconditionally raises. Disable + re-enable around backfill.
ALTER TABLE public.audit_github_token_use DISABLE TRIGGER audit_github_token_use_no_mutate;

DO $$
DECLARE
  v_rc int;
BEGIN
  UPDATE public.audit_github_token_use a
     SET workspace_id = m.workspace_id
    FROM public.workspace_members m
   WHERE m.user_id      = a.founder_id
     AND m.workspace_id = a.founder_id
     AND m.role         = 'owner'
     AND a.workspace_id IS DISTINCT FROM m.workspace_id;
  GET DIAGNOSTICS v_rc = ROW_COUNT;
  RAISE NOTICE '[055-backfill audit_github_token_use] % rows', v_rc;
END $$;

ALTER TABLE public.audit_github_token_use ENABLE TRIGGER audit_github_token_use_no_mutate;

ALTER TABLE public.audit_github_token_use ALTER COLUMN workspace_id SET NOT NULL;

DROP POLICY IF EXISTS audit_github_token_use_owner_select ON public.audit_github_token_use;

CREATE POLICY audit_github_token_use_workspace_member_select ON public.audit_github_token_use
  FOR SELECT TO authenticated
  USING (public.is_workspace_member(workspace_id, auth.uid()));

-- =====================================================================
-- 10. is_message_owner update — workspace-aware (transitively covers
--     019 message_attachments, 045 attachments, 046 messages external
--     drafts callers per plan §1.3.7)
-- =====================================================================
--
-- Signature unchanged: is_message_owner(p_message_id uuid, p_user_id
-- uuid). Semantic shift: "is p_user_id a member of the workspace
-- whose conversation owns p_message_id". messages.workspace_id is now
-- populated (step 2 above), so the predicate is straight is_workspace_
-- member lookup.

CREATE OR REPLACE FUNCTION public.is_message_owner(p_message_id uuid, p_user_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_exists boolean;
BEGIN
  -- Workspace-aware: p_user_id sees this message if they are a member
  -- of messages.workspace_id. The legacy "owner-only" semantic from
  -- migration 045 is intentionally widened — workspace co-members can
  -- read each others' messages + attachments. ADR-038.
  SELECT EXISTS (
    SELECT 1 FROM public.messages m
    WHERE m.id = p_message_id
      AND public.is_workspace_member(m.workspace_id, p_user_id)
  ) INTO v_exists;
  RETURN v_exists;
END;
$$;

REVOKE ALL ON FUNCTION public.is_message_owner(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_message_owner(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.is_message_owner(uuid, uuid) IS
  'Workspace-aware message visibility predicate. Returns TRUE if '
  'p_user_id is a member of the workspace that owns p_message_id. '
  'Semantically widens from migration 045 (per-user) to workspace-co-'
  'member (ADR-038). Signature unchanged; all 045-era callers '
  '(message_attachments storage RLS + INSERT policy) inherit the new '
  'semantic transparently.';

-- =====================================================================
-- 11. workspace_cost_aggregate VIEW
-- =====================================================================
--
-- Per plan §G4 + AC4: workspace-grain rollup of audit_byok_use for
-- dashboard rendering. security_invoker = true so the view runs with
-- the calling role's RLS context (audit_byok_use's workspace_member
-- SELECT policy gates visibility automatically).

CREATE OR REPLACE VIEW public.workspace_cost_aggregate
WITH (security_invoker = true)
AS
SELECT
  a.workspace_id,
  a.founder_id                                          AS user_id,
  date_trunc('month', a.ts)                             AS month_bucket,
  SUM(a.unit_cost_cents::bigint * a.token_count::bigint) AS total_cost_cents,
  SUM(a.token_count)                                    AS total_tokens,
  COUNT(*)                                              AS row_count
FROM public.audit_byok_use a
GROUP BY a.workspace_id, a.founder_id, date_trunc('month', a.ts);

COMMENT ON VIEW public.workspace_cost_aggregate IS
  'Workspace-grain BYOK cost rollup for the workspace cost dashboard. '
  'security_invoker = true so RLS on audit_byok_use gates visibility — '
  'every caller sees only their workspace''s rows. Grouped by '
  '(workspace_id, user_id, month) so per-member contribution within a '
  'workspace stays attributable. ADR-038.';
