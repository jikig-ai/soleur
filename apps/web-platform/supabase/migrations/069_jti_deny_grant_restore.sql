-- Migration 069: REVOKE EXECUTE ON public.is_jti_denied(uuid) FROM
-- authenticated — restore mig 037's enumeration-oracle closure.
--
-- Empirically verified at #4440 follow-up time: migration 068 added
-- `GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO authenticated`
-- citing the learning 2026-05-06-tenant-jwt-rpc-grant-mismatch-vitest-blind
-- which posits that PostgREST evaluates RLS-policy bodies in the caller's
-- (authenticated) role context BEFORE entering the SECURITY DEFINER body.
-- Three review agents (architecture-strategist F6, data-integrity-guardian
-- F2, git-history-analyzer F3) disputed this, arguing that the
-- `is_jti_denied_from_jwt()` wrapper IS itself SECURITY DEFINER and
-- transitively calling `is_jti_denied(uuid)` inside the DEFINER body
-- runs under the wrapper's definer role (postgres / service_role), NOT
-- the original caller's authenticated role — so the GRANT TO
-- authenticated is unnecessary and re-opens the enumeration-oracle
-- surface mig 037 deliberately closed.
--
-- Empirical procedure (PR #4440):
--   1. With GRANT in place: `tenant-jwt-rls-deny.tenant-isolation.test.ts`
--      PASSES (6 cases green).
--   2. REVOKE EXECUTE ... FROM authenticated.
--   3. Re-run same integration tests: STILL PASS (6 cases green).
-- Conclusion: the wrapper's DEFINER scope IS load-bearing; the GRANT
-- on `is_jti_denied(uuid)` was speculative and adds no policy-evaluation
-- coverage. The 3 review agents were right.
--
-- This migration drops the GRANT and re-pins the closure mig 037
-- originally enforced: only service_role can call is_jti_denied(uuid)
-- with an arbitrary UUID. RLS policy evaluation continues to work via
-- the SECURITY DEFINER `is_jti_denied_from_jwt()` wrapper which has
-- its own GRANT TO authenticated.
--
-- Surface eliminated: an authenticated PostgREST caller can no longer
-- invoke `is_jti_denied('<arbitrary-uuid>')` directly to probe the
-- deny-list. Boolean-only return + 2^128 UUID space made the practical
-- attack infeasible regardless, but eliminating the surface is strictly
-- better than relying on entropy.
--
-- Hard rule reference: cq-pg-security-definer-search-path-pin-pg-temp
-- (search_path is already pinned in the mig 068 function body).
--
-- References:
-- - Plan: knowledge-base/project/plans/2026-05-25-feat-jti-revoke-followups-plan.md §Item 6
-- - Migration 037: original enumeration-oracle closure
-- - Migration 068: speculative GRANT added (now reverted)
-- - PR #4418 review agents: architecture-strategist F6, data-integrity-guardian F2, git-history-analyzer F3

REVOKE EXECUTE ON FUNCTION public.is_jti_denied(uuid) FROM authenticated;

-- Defense-in-depth: also revoke from PUBLIC and anon in case a stray
-- default-privileges grant landed (unlikely, mig 037 closed both, but
-- the cost of REVOKE-on-empty is zero).
REVOKE EXECUTE ON FUNCTION public.is_jti_denied(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.is_jti_denied(uuid) FROM anon;

COMMENT ON FUNCTION public.is_jti_denied(uuid) IS
  'Service-role-only enumeration-oracle wrapper for the denied_jti '
  'table. RLS policies invoke this transitively via the SECURITY '
  'DEFINER is_jti_denied_from_jwt() wrapper which evaluates in the '
  'definer role''s scope — authenticated EXECUTE is therefore '
  'unnecessary and was empirically proven unnecessary at #4440 '
  'follow-up time (mig 069). The mig 068 ACKNOWLEDGED SECURITY NOTE '
  'about enumeration-oracle exposure no longer applies.';
