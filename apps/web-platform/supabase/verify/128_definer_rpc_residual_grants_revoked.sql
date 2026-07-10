-- Verify 128_revoke_definer_rpc_residual_grants.sql (#6306).
--
-- Contract: every row returns `check_name` + `bad`. Any `bad > 0` row fails
-- CI verify-migrations (run-verify.sh parses tab-separated (check_name TEXT,
-- bad INT) rows under ON_ERROR_STOP=1).
--
-- Sentinels confirm post-apply state from migration 128:
--   * anon / authenticated / PUBLIC do NOT have EXECUTE on any of the five
--     service-role-only SECURITY DEFINER functions (the deny state that
--     closes the #6306 cross-tenant read + write-IDOR surface).
--   * service_role STILL has EXECUTE on the four non-trigger functions
--     (load-bearing: the reaper + slot flows call them via the service-role
--     client — a lost grant breaks legitimate traffic). NOT asserted for the
--     trigger function release_slot_on_archive(), which needs no grant.
--
-- Signature exactness is load-bearing (data-integrity P1): PUBLIC is the
-- lowercase literal 'public'; acquire_conversation_slot is the 4-arg overload
-- (uuid, uuid, integer, uuid) from 093:124 — a wrong signature raises
-- `function … does not exist` and, under ON_ERROR_STOP=1, hard-fails the
-- release pipeline (false red) rather than silently no-op'ing.

-- (1) find_stuck_active_conversations(integer)
SELECT 'find_stuck_active_conversations_anon_revoked' AS check_name,
       CASE WHEN has_function_privilege('anon', 'public.find_stuck_active_conversations(integer)', 'EXECUTE') THEN 1 ELSE 0 END::int AS bad
UNION ALL
SELECT 'find_stuck_active_conversations_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.find_stuck_active_conversations(integer)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'find_stuck_active_conversations_public_revoked',
       CASE WHEN has_function_privilege('public', 'public.find_stuck_active_conversations(integer)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'find_stuck_active_conversations_service_role_grant_present',
       CASE WHEN has_function_privilege('service_role', 'public.find_stuck_active_conversations(integer)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL

-- (2) acquire_conversation_slot(uuid, uuid, integer, uuid) — 4-arg overload
SELECT 'acquire_conversation_slot_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.acquire_conversation_slot(uuid, uuid, integer, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'acquire_conversation_slot_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.acquire_conversation_slot(uuid, uuid, integer, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'acquire_conversation_slot_public_revoked',
       CASE WHEN has_function_privilege('public', 'public.acquire_conversation_slot(uuid, uuid, integer, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'acquire_conversation_slot_service_role_grant_present',
       CASE WHEN has_function_privilege('service_role', 'public.acquire_conversation_slot(uuid, uuid, integer, uuid)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL

-- (3) release_conversation_slot(uuid, uuid)
SELECT 'release_conversation_slot_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.release_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_conversation_slot_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.release_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_conversation_slot_public_revoked',
       CASE WHEN has_function_privilege('public', 'public.release_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_conversation_slot_service_role_grant_present',
       CASE WHEN has_function_privilege('service_role', 'public.release_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL

-- (4) touch_conversation_slot(uuid, uuid)
SELECT 'touch_conversation_slot_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.touch_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'touch_conversation_slot_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.touch_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'touch_conversation_slot_public_revoked',
       CASE WHEN has_function_privilege('public', 'public.touch_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'touch_conversation_slot_service_role_grant_present',
       CASE WHEN has_function_privilege('service_role', 'public.touch_conversation_slot(uuid, uuid)', 'EXECUTE') THEN 0 ELSE 1 END::int
UNION ALL

-- (5) release_slot_on_archive() — trigger fn. Deny checks only; NO service_role
--     positive check (a trigger function needs no EXECUTE grant to fire).
SELECT 'release_slot_on_archive_anon_revoked',
       CASE WHEN has_function_privilege('anon', 'public.release_slot_on_archive()', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_slot_on_archive_authenticated_revoked',
       CASE WHEN has_function_privilege('authenticated', 'public.release_slot_on_archive()', 'EXECUTE') THEN 1 ELSE 0 END::int
UNION ALL
SELECT 'release_slot_on_archive_public_revoked',
       CASE WHEN has_function_privilege('public', 'public.release_slot_on_archive()', 'EXECUTE') THEN 1 ELSE 0 END::int;
