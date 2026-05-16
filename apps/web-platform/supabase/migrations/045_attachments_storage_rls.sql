-- 045_attachments_storage_rls.sql
-- PR-D scope (#3244 §4): close cross-tenant attachment read vector by adding
-- the INSERT/UPDATE/DELETE Storage policies that migration 019 left out, plus
-- the missing message_attachments INSERT policy.
--
-- Migration 019 created the chat-attachments bucket + the storage.objects
-- SELECT policy and the message_attachments SELECT policy, but no INSERT/
-- UPDATE/DELETE policies. Pre-PR-D, persistAndDownloadAttachments() was
-- service-role at the application layer, so the missing write policies
-- never surfaced. PR-D's call-site swap to tenant client makes these
-- policies load-bearing for both write paths and read paths.
--
-- Refs: #3244 (umbrella), #3854 (PR-C), #3869 items 4-5.
--
-- Design notes:
--
--   * Storage.objects policy uses FOR ALL with USING and NO WITH CHECK.
--     Per 2026-04-18-rls-for-all-using-applies-to-writes.md: when WITH
--     CHECK is omitted, the USING expression also applies to INSERT/
--     UPDATE row-being-written. Adding `WITH CHECK (true)` here would
--     silently disable tenant isolation on writes — DO NOT add one in
--     a future migration without re-reading that learning.
--
--   * message_attachments policy joins through messages →
--     conversations.user_id. DELETE handled by FK ON DELETE CASCADE
--     from messages → conversations, so no explicit DELETE policy is
--     defined here (brainstorm Open Question §3 provisional decision —
--     follow-up issue if un-attach UX is requested).
--
--   * RLS evaluates after table-level GRANT. The `authenticated` role
--     already holds INSERT/UPDATE/DELETE on storage.objects (granted by
--     supabase-storage extension defaults) and message_attachments
--     (granted by supabase's anon/authenticated role bootstrap). Phase
--     0.4b GRANT presence check confirms this at apply time.

-- Rollback procedure: drop both policies via the matching DROP statements
-- below. The 019 SELECT policy survives the drop, so reads keep working;
-- INSERT/UPDATE/DELETE through tenant clients fall back to the pre-PR-D
-- "no policy → authenticated deny" posture. Application code must roll
-- back to service-role at the same time to keep the attachment pipeline
-- functional.
--
-- DROP POLICY IF EXISTS "Users can write own attachment objects" ON storage.objects;
-- DROP POLICY IF EXISTS "Users can insert own message attachments" ON public.message_attachments;
-- DROP FUNCTION IF EXISTS public.is_message_owner(uuid, uuid);

-- 1. storage.objects FOR ALL policy — INSERT/UPDATE/DELETE for chat-attachments
--    bucket scoped to the caller's user-folder prefix. SELECT policy with the
--    same predicate already exists from migration 019.
--
--    Idempotent DROP-then-CREATE preamble so the migration runner can replay
--    safely after a partial failure or dev reset. Postgres has no
--    `CREATE POLICY IF NOT EXISTS`; the standard pattern is drop-first.
DROP POLICY IF EXISTS "Users can write own attachment objects" ON storage.objects;
CREATE POLICY "Users can write own attachment objects"
  ON storage.objects FOR ALL
  USING (
    bucket_id = 'chat-attachments'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- 2. SECURITY DEFINER ownership helper for message_attachments.
--    Bypasses chained RLS evaluation: the migration 019 SELECT policy
--    on `messages` itself filters via conversations.user_id, which means
--    a WITH CHECK predicate that joins `messages JOIN conversations`
--    under a tenant JWT triggers a chain of RLS-gated reads that empirically
--    returns zero rows even for the legitimate same-tenant case (caught by
--    the same-tenant positive-control integration test in PR-D's first CI
--    run). Running the ownership check inside a SECURITY DEFINER function
--    elevates the inner JOIN out of the tenant-JWT RLS chain so the check
--    resolves correctly. The function is `SECURITY DEFINER` per Postgres
--    convention; `search_path` is pinned to `public, pg_temp` (public FIRST
--    per `cq-pg-security-definer-search-path-pin-pg-temp`) and every body
--    relation is qualified `public.<table>` as belt-and-suspenders against
--    `pg_temp.<table>` planting attacks. EXECUTE is REVOKEd from PUBLIC,
--    anon, authenticated then GRANTed back to authenticated only — the
--    explicit role-list REVOKE neutralises Supabase's `ALTER DEFAULT
--    PRIVILEGES` bootstrap grants (per
--    `2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md`)
--    so the function is unreachable from anon.
-- Drop the dependent policy BEFORE the function so DROP FUNCTION succeeds on
-- replay. Postgres refuses `DROP FUNCTION` while any policy references it
-- (cannot DROP, other objects depend on it). The policy is recreated in
-- section 3 below after the function is re-created.
DROP POLICY IF EXISTS "Users can insert own message attachments" ON public.message_attachments;
DROP FUNCTION IF EXISTS public.is_message_owner(uuid, uuid);
CREATE FUNCTION public.is_message_owner(p_message_id uuid, p_user_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_exists boolean;
BEGIN
  -- LANGUAGE plpgsql (not sql) + no STABLE/IMMUTABLE keyword is required:
  -- Postgres's planner inlines sql-language STABLE functions, dissolving
  -- the SECURITY DEFINER boundary back into the caller's tenant-JWT RLS
  -- context. plpgsql functions are NOT inlinable, so the inner SELECT
  -- runs at the function owner's superuser RLS context as intended.
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

-- 3. message_attachments INSERT policy.
DROP POLICY IF EXISTS "Users can insert own message attachments" ON public.message_attachments;
CREATE POLICY "Users can insert own message attachments"
  ON public.message_attachments FOR INSERT
  WITH CHECK (
    public.is_message_owner(message_attachments.message_id, auth.uid())
  );
