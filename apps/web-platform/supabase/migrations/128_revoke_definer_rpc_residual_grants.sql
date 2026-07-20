-- Migration 128: REVOKE residual anon/authenticated EXECUTE on five
-- service-role-only SECURITY DEFINER functions — close the cross-tenant
-- disclosure / write-IDOR surface reported in #6306.
--
-- Root cause: Supabase's default privileges grant EXECUTE on every new
-- `public` function to `anon`, `authenticated`, `service_role` at CREATE
-- time. Migrations 029/036/037/093 intended service-role-only access but
-- ran only `revoke all on function … from public`, which removes the
-- PUBLIC grant while leaving the *explicit* anon/authenticated grants
-- intact. Live proacl on find_stuck_active_conversations:
--   {postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--
-- Because these functions are SECURITY DEFINER, their definer rights bypass
-- base-table RLS. So any authenticated (or anonymous) PostgREST caller could:
--   * find_stuck_active_conversations(integer) — enumerate EVERY tenant's
--     stuck-active (conversation_id, user_id) pairs (cross-tenant read;
--     GDPR Art. 5(1)(f) confidentiality break).
--   * acquire/release/touch_conversation_slot(…) — mutate ANOTHER user's
--     concurrency-slot ledger, locking a free-tier user (cap=1) out of
--     starting any conversation (write IDOR / denial-of-service).
--   * release_slot_on_archive() — a trigger function; PostgREST never
--     exposes trigger-returning functions as RPC endpoints, so its practical
--     disclosure risk is nil. Included for shape-uniformity only.
--
-- Fix: forward-only grant-change migration restoring the stated
-- service-role-only intent. This is a mechanical application of the
-- canonical repo pattern:
--   * 027_mtd_cost_aggregate.sql:67-69  (REVOKE … FROM PUBLIC; authenticated; anon)
--   * 116_worktree_write_lease.sql:203-205 (revoke all … from public, anon, authenticated)
--   * 069_jti_deny_grant_restore.sql (the pure grant-change migration +
--     verify-sentinel + down-migration triad this file copies verbatim).
-- 125_list_conversations_enriched.sql:172-179 records the same DEFINER
-- grant-hygiene rule; 037 (the finder) plus 029/036/093 (the slot RPCs) are
-- the precedents that got it wrong — each ran revoke-from-public-only.
--
-- No function BODY is edited (grants only), so the existing
-- `set search_path = public, pg_temp` pins are untouched
-- (cq-pg-security-definer-search-path-pin-pg-temp — no regression surface).
--
-- Durability: `CREATE OR REPLACE` preserves a function's ACL, but
-- `DROP FUNCTION` + `CREATE` does NOT (it re-applies Supabase's default
-- grants — which is exactly how the 4-arg acquire_conversation_slot got
-- re-granted at 093:42,50). The load-bearing durability guard is therefore
-- verify/128 running on EVERY deploy, not ACL-preservation — it must never
-- be removed from web-platform-release.yml. The sentinel covers only these
-- 5 signatures; a broad-class guard (ALTER DEFAULT PRIVILEGES / migration
-- lint) is deferred to a tracked #6306 follow-up and #6256.
--
-- References:
-- - Issue: #6306
-- - Plan: knowledge-base/project/plans/2026-07-11-fix-revoke-definer-rpc-residual-grants-plan.md
-- - Precedent triad: migrations/069_jti_deny_grant_restore.sql (+ .down + verify/069)
-- - Sibling audit: migrations 029 (release/touch), 036 (trigger), 037 (finder),
--   093 (4-arg acquire); exemplars 027, 116, 125.

-- (1) find_stuck_active_conversations(integer) — cross-tenant read (primary).
revoke execute on function public.find_stuck_active_conversations(integer) from anon, authenticated;
revoke execute on function public.find_stuck_active_conversations(integer) from public;

-- (2) acquire_conversation_slot — 4-arg overload from 093:124 (the 3-arg form
--     was dropped at 093:42; do NOT reference it). Write IDOR (slot theft).
revoke execute on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) from anon, authenticated;
revoke execute on function public.acquire_conversation_slot(uuid, uuid, integer, uuid) from public;

-- (3) release_conversation_slot(uuid, uuid) — write IDOR (slot free).
revoke execute on function public.release_conversation_slot(uuid, uuid) from anon, authenticated;
revoke execute on function public.release_conversation_slot(uuid, uuid) from public;

-- (4) touch_conversation_slot(uuid, uuid) — write IDOR (heartbeat).
revoke execute on function public.touch_conversation_slot(uuid, uuid) from anon, authenticated;
revoke execute on function public.touch_conversation_slot(uuid, uuid) from public;

-- (5) release_slot_on_archive() — trigger fn, defense-in-depth (not RPC-exposable).
revoke execute on function public.release_slot_on_archive() from anon, authenticated;
revoke execute on function public.release_slot_on_archive() from public;

comment on function public.find_stuck_active_conversations(integer) is
  'Service-role-only stuck-active conversation finder. SECURITY DEFINER '
  'bypasses conversations RLS, so it must be callable ONLY by the '
  'application-layer reaper via the service-role client '
  '(server/agent-runner.ts). EXECUTE for anon/authenticated was a '
  'residual CREATE-time default grant that migration 037 failed to revoke '
  '(037 revoked from PUBLIC only); it enabled cross-tenant enumeration of '
  '(conversation_id, user_id) pairs. Revoked in migration 128. Ref #6306.';
