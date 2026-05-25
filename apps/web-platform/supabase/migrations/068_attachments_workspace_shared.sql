-- 068_attachments_workspace_shared.sql
-- feat-attachments-rls-bundle-pr2-4318 (#4318) — workspace co-member attachment
-- visibility for the chat-attachments Storage bucket + uploader-identity cascade
-- on account-delete AND workspace-member-removal.
--
-- LAWFUL_BASIS: GDPR Art. 6(1)(b) workspace collaboration contract +
--               Art. 6(1)(f) shared-asset retention legitimate interest.
-- See knowledge-base/legal/article-30-register.md PA-2 §(c), §(d), §(g)(10).
--
-- This migration is shipped behind the runtime flag TEAM_WORKSPACE_INVITE_ENABLED
-- (currently OFF in prd). The new SELECT predicate evaluates regardless of the
-- flag because the SECURITY DEFINER helper runs in the storage RLS context; the
-- flag only gates whether co-members can be invited in the first place. In a
-- prd snapshot with no multi-user workspaces, the new co-member branch is
-- empirically dormant (PROBE-A..D / R-9 spike, Phase 0 worklog).
--
-- INVARIANTS:
--   F1 (FK-safe pseudonymisation): messages.user_id is uuid REFERENCES
--      auth.users(id) ON DELETE CASCADE (mig 046:93). The cascade RPC sets
--      user_id = NULL (mirrors mig 051 anonymise_action_sends:226 et al.) —
--      no synthetic pseudonym is minted; uploader identity for "former
--      member" rows is reconstructed via the workspace_member_removals
--      ledger join. Phase 0 emergent finding E-1 (worklog 2026-05-25).
--   F2 (cascade ordering): in remove_workspace_member, the internal
--      pseudonymisation call MUST run BEFORE the DELETE FROM workspace_members
--      so is_workspace_member(p_workspace_id, p_user_id) still returns true
--      inside the predicate. The cascade-RPC ordering (account-delete step
--      3.901 before 3.91) enforces the same invariant via the TS pipeline.
--   F3 (write narrowing): the mig 045 FOR ALL policy is split into a widened
--      SELECT (own OR co-member) and three narrow INSERT/UPDATE/DELETE
--      policies (own-folder only). FOR ALL USING governs both reads AND
--      writes per security-issues/2026-04-18-rls-for-all-using-applies-to-
--      writes.md — widening SELECT without splitting would leak write
--      eligibility into other users' folders.
--   F4 (SECURITY DEFINER helper from storage context): empirically verified
--      via the R-9 spike (Phase 0 worklog). The helper resolves correctly
--      under `SET LOCAL ROLE authenticated; SET LOCAL request.jwt.claims =
--      '{"sub":"<uuid>"}'` simulated tenant contexts.

BEGIN;

-- =====================================================================
-- 1. Helper: derive workspace_id from a conversation-id path segment and
--    check membership. SECURITY DEFINER plpgsql per cq-pg-security-definer-
--    search-path-pin-pg-temp + mig 045 precedent (plpgsql NOT sql to defeat
--    planner inlining; without this, the SELECT inside would inline into
--    the caller's RLS context and re-trigger tenant-isolation chains).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.is_attachment_path_workspace_member(
  p_conversation_id uuid,
  p_user_id         uuid
) RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_workspace_id uuid;
BEGIN
  IF p_conversation_id IS NULL OR p_user_id IS NULL THEN
    RETURN false;
  END IF;
  SELECT workspace_id INTO v_workspace_id
    FROM public.conversations
    WHERE id = p_conversation_id;
  IF v_workspace_id IS NULL THEN
    RETURN false;
  END IF;
  RETURN public.is_workspace_member(v_workspace_id, p_user_id);
END;
$$;

-- REVOKE list mirrors mig 045 precedent (all four roles) to defeat
-- ALTER DEFAULT PRIVILEGES per 2026-05-06-supabase-default-privileges-
-- defeat-revoke-from-public.md.
REVOKE ALL ON FUNCTION public.is_attachment_path_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_attachment_path_workspace_member(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.is_attachment_path_workspace_member(uuid, uuid) IS
  'Returns TRUE if p_user_id is a member of the workspace owning '
  'p_conversation_id. SECURITY DEFINER plpgsql so planner-inlining cannot '
  'dissolve the tenant-isolation boundary. Substrate for the mig 068 '
  'storage.objects SELECT policy widening (#4318).';

-- =====================================================================
-- 2. Storage RLS policy split: drop the mig 045 FOR ALL policy and
--    replace with widened SELECT + three narrow INSERT/UPDATE/DELETE
--    policies. Mig 019's "Users can read own attachment objects" SELECT
--    policy is left in place — additive OR semantics with the new policy
--    is benign (both grant own-folder access; only the new policy grants
--    the co-member case).
-- =====================================================================

DROP POLICY IF EXISTS "Users can write own attachment objects" ON storage.objects;

CREATE POLICY "Users read own + co-member attachment objects"
  ON storage.objects FOR SELECT
  USING (
    bucket_id = 'chat-attachments'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR (
        (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
        AND public.is_attachment_path_workspace_member(
          ((storage.foldername(name))[2])::uuid,
          auth.uid()
        )
      )
    )
  );

CREATE POLICY "Users write own attachment objects only (insert)"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users write own attachment objects only (update)"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Users write own attachment objects only (delete)"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

COMMENT ON POLICY "Users read own + co-member attachment objects" ON storage.objects IS
  'Read-path widened per #4318 / mig 068. Co-member visibility derived from '
  'conversations.workspace_id via is_attachment_path_workspace_member(). '
  'Writes are governed by the sibling FOR INSERT/UPDATE/DELETE policies — '
  'do NOT collapse back to FOR ALL without re-reading '
  'security-issues/2026-04-18-rls-for-all-using-applies-to-writes.md.';

-- =====================================================================
-- 3. Private internal helper for cascade pseudonymisation. Sets
--    messages.user_id = NULL for messages-with-attachments authored by
--    the departing user in shared-workspace conversations (i.e., convs
--    the departing user does NOT own). Mirrors mig 051's
--    anonymise_action_sends shape — NULL not a synthetic pseudonym,
--    because messages.user_id has a FK to auth.users(id) ON DELETE
--    CASCADE and any synthetic uuid would violate the FK (Phase 0
--    emergent finding E-1). The departing user's auth.users row will
--    be deleted later in the cascade; nulling user_id here ensures
--    those rows survive that delete.
--
--    Authorisation: no public GRANT — the function is reachable only
--    via the two sibling SECURITY DEFINER public RPCs below.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._anonymise_authored_messages_internal(
  p_departing_user uuid,
  p_workspace_id   uuid
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_updated integer := 0;
BEGIN
  IF p_departing_user IS NULL OR p_workspace_id IS NULL THEN
    RETURN 0;
  END IF;
  UPDATE public.messages AS m
     SET user_id = NULL
   WHERE m.user_id      = p_departing_user
     AND m.workspace_id = p_workspace_id
     AND EXISTS (SELECT 1 FROM public.message_attachments ma
                  WHERE ma.message_id = m.id)
     AND EXISTS (SELECT 1 FROM public.conversations c
                  WHERE c.id = m.conversation_id
                    AND c.user_id <> p_departing_user);
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

REVOKE ALL ON FUNCTION public._anonymise_authored_messages_internal(uuid, uuid)
  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON FUNCTION public._anonymise_authored_messages_internal(uuid, uuid) IS
  'Cascade pseudonymisation core. Nulls messages.user_id for the departing '
  'user''s authored-with-attachments rows in shared-workspace conversations. '
  'Called by anonymise_departed_user_across_workspaces (account-delete) AND '
  'remove_workspace_member (member-removal). NO public GRANT; reachable only '
  'via the two sibling SECURITY DEFINER bodies. #4318 / E-1.';

-- =====================================================================
-- 4. Public RPC for full account-delete: iterates the departing user's
--    workspaces and calls the internal helper once per workspace.
--    Returns the total affected row count for the structured log line.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.anonymise_departed_user_across_workspaces(
  p_departing_user uuid
) RETURNS integer
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_total integer := 0;
  v_one   integer;
  r       record;
BEGIN
  IF p_departing_user IS NULL THEN
    RETURN 0;
  END IF;
  -- Iterate distinct workspaces the departing user authored messages in.
  -- workspace_id IS NOT NULL filter is precautionary; PROBE-A (Phase 0)
  -- confirmed 0 such rows on prd at migration time.
  FOR r IN
    SELECT DISTINCT m.workspace_id
      FROM public.messages m
     WHERE m.user_id = p_departing_user
       AND m.workspace_id IS NOT NULL
  LOOP
    v_one := public._anonymise_authored_messages_internal(p_departing_user, r.workspace_id);
    v_total := v_total + COALESCE(v_one, 0);
  END LOOP;
  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_departed_user_across_workspaces(uuid)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.anonymise_departed_user_across_workspaces(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_departed_user_across_workspaces(uuid) IS
  'Account-delete entry point for attachment-uploader-identity cascade. '
  'Iterates the departing user''s authored-message workspaces and calls '
  '_anonymise_authored_messages_internal per workspace. Wired into '
  'account-delete.ts at step 3.901 (between anonymise_workspace_member_'
  'attestations and anonymise_workspace_member_removals). #4318.';

-- =====================================================================
-- 5. Amended remove_workspace_member — reproduces mig 067:117-206
--    verbatim with one inserted call: _anonymise_authored_messages_internal
--    runs AFTER the role-validation guards and BEFORE the WORM-removals
--    INSERT, so is_workspace_member(p_workspace_id, p_user_id) is still
--    true when the predicate evaluates inside the helper.
--
--    Postgres has no `ALTER FUNCTION BODY`; the whole body must be
--    redeclared. The down.sql restores mig 067's body verbatim.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.remove_workspace_member(
  p_workspace_id uuid,
  p_user_id      uuid
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_user_id uuid := auth.uid();
  v_is_owner       boolean;
  v_target_role    text;
  v_org_id         uuid;
  v_rows           int;
  v_anon_count     int;
BEGIN
  IF v_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.workspace_members
    WHERE workspace_id = p_workspace_id
      AND user_id      = v_caller_user_id
      AND role         = 'owner'
  ) INTO v_is_owner;

  IF NOT v_is_owner THEN
    RAISE EXCEPTION 'caller is not an owner of workspace %', p_workspace_id
      USING ERRCODE = '42501';
  END IF;

  IF v_caller_user_id = p_user_id THEN
    RAISE EXCEPTION 'owner cannot remove themselves; use account-delete to cascade-anonymise instead'
      USING ERRCODE = '22023';
  END IF;

  SELECT role INTO v_target_role
  FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;

  IF v_target_role IS NULL THEN
    RETURN 0;
  END IF;

  IF v_target_role = 'owner' THEN
    RAISE EXCEPTION 'cannot remove another owner; only members can be removed'
      USING ERRCODE = '22023';
  END IF;

  SELECT organization_id INTO v_org_id
    FROM public.workspaces WHERE id = p_workspace_id;

  -- mig 068 #4318 — cascade-pseudonymise authored messages-with-attachments
  -- BEFORE deleting the membership row; the internal helper's predicate
  -- relies on is_workspace_member(p_workspace_id, p_user_id) = true (F2).
  v_anon_count := public._anonymise_authored_messages_internal(p_user_id, p_workspace_id);

  -- Append WORM revocation row with the new columns populated. The INSERT
  -- lands inside the same SECURITY DEFINER body as the DELETE; FK violation
  -- rolls the DELETE back atomically per mig 062 AC2.
  INSERT INTO public.workspace_member_removals (
    workspace_id, removed_user_id, removed_by_user_id,
    revoked_after, revocation_reason
  ) VALUES (
    p_workspace_id, p_user_id, v_caller_user_id,
    now(), 'removed'
  );

  DELETE FROM public.workspace_members
  WHERE workspace_id = p_workspace_id AND user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  -- F6: clear user_session_state.current_organization_id if it points to the
  -- affected organization AND the user has no remaining workspaces in it.
  -- The hook at mig 060 doesn't re-validate membership before injecting
  -- current_organization_id into the next JWT; clearing here ensures the
  -- post-refresh JWT lands the user on /login instead of a half-broken
  -- dashboard. Best-effort — a follow-up (AC20-1) will add membership
  -- validation to the hook itself.
  IF v_org_id IS NOT NULL THEN
    UPDATE public.user_session_state uss
       SET current_organization_id = NULL
     WHERE uss.user_id = p_user_id
       AND uss.current_organization_id = v_org_id
       AND NOT EXISTS (
         SELECT 1 FROM public.workspace_members m
         JOIN public.workspaces w ON w.id = m.workspace_id
         WHERE m.user_id = p_user_id AND w.organization_id = v_org_id
       );
  END IF;

  RETURN v_rows;
END;
$$;

-- GRANT matrix unchanged from mig 067:208-211 (REVOKE from PUBLIC/anon/
-- authenticated; GRANT EXECUTE to authenticated). service_role retains
-- default EXECUTE per mig 062:344 pattern (the TS wrapper invokes via
-- createServiceClient()).
REVOKE ALL ON FUNCTION public.remove_workspace_member(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.remove_workspace_member(uuid, uuid)
  TO authenticated;

COMMENT ON FUNCTION public.remove_workspace_member(uuid, uuid) IS
  'Workspace-member removal RPC. Atomic SECURITY DEFINER body: '
  '(1) authorise caller-is-owner; (2) reject self-removal; (3) reject '
  'owner-target; (4) cascade-pseudonymise authored messages-with-'
  'attachments in shared convs via _anonymise_authored_messages_internal '
  '(mig 068 #4318); (5) INSERT workspace_member_removals WORM row with '
  'revocation_reason=removed (mig 067 #4307); (6) DELETE workspace_members '
  'row; (7) clear user_session_state.current_organization_id (F6).';

COMMIT;
