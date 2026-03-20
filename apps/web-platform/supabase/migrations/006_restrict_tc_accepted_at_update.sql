-- Restrict tc_accepted_at and other server-managed columns from user-initiated updates.
--
-- A column-level REVOKE alone is ineffective when a table-level grant exists
-- (see: supabase.com/docs/guides/database/postgres/column-level-security).
-- We must revoke the table-level grant first, then re-grant only safe columns.

REVOKE UPDATE ON TABLE public.users FROM authenticated;

-- IMPORTANT: When adding new columns to public.users, decide whether they
-- should be user-updatable and add them to this GRANT if so.
GRANT UPDATE (email) ON TABLE public.users TO authenticated;
