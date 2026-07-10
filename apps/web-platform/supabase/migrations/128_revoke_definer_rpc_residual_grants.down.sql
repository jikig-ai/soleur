-- =====================================================================
-- 128_revoke_definer_rpc_residual_grants.down.sql
-- =====================================================================
--
-- Restores the pre-128 (residual, CREATE-time-default) EXECUTE grants to
-- `anon` + `authenticated` on the five functions migration 128 revoked.
-- Provided ONLY for migration-rollback machinery, mirroring
-- 069_jti_deny_grant_restore.down.sql and the 093 down convention.
--
-- IMPORTANT CAVEAT (knowingly-broken): applying this down migration
-- KNOWINGLY re-opens the exact #6306 vulnerability migration 128 closed —
-- it re-grants EXECUTE on these SECURITY DEFINER functions to anon and
-- authenticated, restoring:
--   * cross-tenant enumeration of (conversation_id, user_id) pairs via
--     find_stuck_active_conversations (GDPR Art. 5(1)(f) confidentiality
--     break), and
--   * the write-IDOR on the concurrency-slot RPCs (one user can free /
--     steal / heartbeat another user's slot).
-- Do NOT run this in production. It exists purely as rollback machinery /
-- for a controlled regression test; the up-migration is the canonical
-- path forward.
-- =====================================================================

grant execute on function public.find_stuck_active_conversations(integer) to anon, authenticated;
grant execute on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) to anon, authenticated;
grant execute on function public.release_conversation_slot(uuid, uuid) to anon, authenticated;
grant execute on function public.touch_conversation_slot(uuid, uuid) to anon, authenticated;
grant execute on function public.release_slot_on_archive() to anon, authenticated;

-- Note: we do NOT restore migration 037's original COMMENT ON FUNCTION text.
-- The COMMENT set by the up-migration is the canonical post-128 state and is
-- replaced by the next migration that re-comments the function (or stays in
-- place if none lands). We also intentionally do NOT re-grant PUBLIC — the
-- pre-128 live state had PUBLIC already revoked (by the original 037/029/036/093
-- `revoke … from public`), so restoring it would over-widen beyond the state
-- this migration is rolling back.
