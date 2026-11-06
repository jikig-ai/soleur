-- 181_messages_owner_draft_update.sql
--
-- #11569 — public.messages has no UPDATE policy for any role, so the
-- cookie-client UPDATEs in the Discard, Edit and send-archive routes
-- (apps/web-platform/app/api/dashboard/today/[id]/{discard,edit,send}/route.ts)
-- match zero rows: a RESTRICTIVE policy only narrows what a PERMISSIVE one
-- grants, and none exists. This migration adds the missing PERMISSIVE UPDATE
-- policy and, in the same transaction, narrows the table-level UPDATE grant.
--
-- Read-only comparison before writing (2026-10-30): the dev and prod
-- pg_policies sets for public.messages were identical (messages_jti_not_denied
-- ALL RESTRICTIVE, messages_workspace_member_insert, messages_workspace_member_select;
-- no UPDATE or ALL permissive policy), RLS enabled and not forced. This file
-- names its own policy and DROPs IF EXISTS before creating it, so it never
-- inherits a policy name from either project.
--
-- Row scope (CTO ruling D1): the author's own DRAFT rows only. USING requires
-- the author, workspace membership and status = 'draft'; WITH CHECK allows the
-- row to stay a draft or become archived and nothing else, so complete and
-- aborted chat rows stay immutable from the client and a draft cannot be
-- flipped to complete. Every real call already filters id + user_id + status.
-- The RESTRICTIVE messages_jti_not_denied (ALL) is untouched and still ANDs on
-- top, so a revoked-JTI session still cannot update.
--
-- Column scope (CTO ruling D2): authenticated and anon hold a table-level
-- UPDATE on every column (migration 174 snapshot of Supabase defaults). A
-- table-level grant makes a column-level REVOKE a no-op, so the table-level
-- UPDATE is revoked FIRST and only the two columns the routes write are
-- re-granted. The ordering is load-bearing (migration 178): a later REVOKE
-- would strip the column grant. Without this narrowing the policy alone would
-- let a browser session rewrite trust_tier, action_class, template_id or
-- workspace_id on its own draft rows, which is worse than today's inert state.
-- The remaining table-level verbs (DELETE, TRUNCATE, ...) are NOT narrowed
-- here; that belongs to the ADR-303 narrowing line.
--
-- No data movement: the stuck prod drafts are not bulk-archived.

DO $$ BEGIN
    IF to_regclass('public.messages') IS NULL THEN
        RAISE EXCEPTION '181: public.messages is absent';
    END IF;
    IF to_regprocedure('public.is_workspace_member(uuid,uuid)') IS NULL THEN
        RAISE EXCEPTION '181: public.is_workspace_member(uuid,uuid) is absent';
    END IF;
END $$;

DROP POLICY IF EXISTS messages_owner_draft_update ON public.messages;
CREATE POLICY messages_owner_draft_update ON public.messages
    AS PERMISSIVE FOR UPDATE TO authenticated
    USING (user_id = (SELECT auth.uid())
           AND status = 'draft'
           AND public.is_workspace_member(workspace_id, (SELECT auth.uid())))
    WITH CHECK (user_id = (SELECT auth.uid())
                AND status IN ('draft', 'archived')
                AND public.is_workspace_member(workspace_id, (SELECT auth.uid())));

REVOKE UPDATE ON TABLE public.messages FROM PUBLIC, anon, authenticated;
GRANT UPDATE (status, draft_preview) ON TABLE public.messages TO authenticated;
