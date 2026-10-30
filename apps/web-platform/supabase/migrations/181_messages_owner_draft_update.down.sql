-- 181_messages_owner_draft_update.down.sql — restores the pre-181 posture:
-- no owner UPDATE policy, and the table-level UPDATE grant migration 174
-- recorded for anon and authenticated (defects included, matching the 176
-- down convention). Rollback machinery only: this knowingly re-opens the
-- default-era grant. Pair it with the reverse table-grants.ts edit, or the
-- RLS-fuzz grant gate expects the narrowed posture.

DROP POLICY IF EXISTS messages_owner_draft_update ON public.messages;

DO $$ BEGIN IF to_regclass('public.messages') IS NOT NULL THEN
    -- Column-level grants live in attacl and survive a table-level GRANT; drop
    -- them first so the restored state is exactly 174's recorded posture.
    REVOKE UPDATE (status, draft_preview) ON TABLE public.messages FROM authenticated;
    GRANT UPDATE ON TABLE public.messages TO anon, authenticated;
END IF; END $$;
