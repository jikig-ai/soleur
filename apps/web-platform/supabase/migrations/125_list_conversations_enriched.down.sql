-- Rollback for 125_list_conversations_enriched.sql.
-- Drops the enriched-list RPC (exact signature) and the supporting index.
drop function if exists public.list_conversations_enriched(text, uuid, text, text, text, int);
drop index if exists public.idx_conversations_rail;
