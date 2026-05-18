-- Migration 049: runtime_mint_intent marker table.
--
-- Discriminator channel between the runtime JWT mint path and the
-- user-facing dashboard OTP login. Phase-4 empirical probe (ADR-033 §0.7,
-- 2026-05-18) established that Supabase's Custom Access Token Hook event
-- payload contains NO field that discriminates the two paths — both
-- generateLink+verifyOtp(token_hash) and signInWithOtp+verifyOtp(token)
-- produce identical aud/amr/exp/app_metadata structure. The
-- 'authentication_method = otp' gate from migration 047 is therefore
-- insufficient: it would silently rewrite every dashboard login JWT with
-- aud='soleur-runtime' and exp=600s (10-min auto-logout).
--
-- Mechanism: tenant.ts UPSERTs a row into this table immediately before
-- its auth.admin.generateLink call. Migration 050 updates the hook to
-- atomically DELETE-and-check via CTE; if a row was consumed AND
-- authentication_method='otp', the hook proceeds to mint. Otherwise
-- pass-through. Dashboard logins never UPSERT, so they always pass-through.
--
-- Residual race window: ~700ms between tenant.ts UPSERT and hook DELETE.
-- A dashboard login firing within that window for the same user_id steals
-- the intent row → dashboard user gets the runtime claims (mild harm:
-- 10-min session; self-recovering via re-login), and the runtime path's
-- verifyOtp returns a JWT without precheck jti → tenant.ts decodeJwtPayloadUnsafe
-- check throws RuntimeAuthError. Probability per dashboard login is
-- bounded by mint frequency: ~0.02% under steady-state founder load.
--
-- ON DELETE CASCADE from auth.users: an intent row for a deleted user is
-- semantically dead and would block FK-checked deletes. Also satisfies
-- GDPR Art. 17 erasure hygiene (no orphan after delete).
--
-- Plan: knowledge-base/project/plans/2026-05-18-refactor-runtime-jwt-asymmetric-signing-substrate-plan.md §Phase 4 amendment
-- ADR:  knowledge-base/engineering/architecture/decisions/ADR-033-runtime-jwt-signing-substrate.md §0.7

-- LAWFUL_BASIS: Art. 6(1)(f) legitimate interest — the marker is a transient
-- gate signal (≤10s lifetime), no PII beyond user_id (already in auth.users).

CREATE TABLE IF NOT EXISTS public.runtime_mint_intent (
  user_id    uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.runtime_mint_intent IS
  'Per-user gate marker written by lib/supabase/tenant.ts:mintFounderJwt '
  'before auth.admin.generateLink and atomically consumed by '
  'public.runtime_jwt_mint_hook (migration 050). Discriminates the runtime '
  'mint path from user-facing dashboard OTP logins, which produce '
  'indistinguishable hook event payloads (ADR-033 §0.7). Rows have a '
  '10-second effective TTL enforced by the hook; stale rows are harmless '
  'and overwritten by the next UPSERT via ON CONFLICT.';

COMMENT ON COLUMN public.runtime_mint_intent.user_id IS
  'Founder user_id whose runtime JWT is being minted. PRIMARY KEY allows '
  'idempotent UPSERT under concurrent mint attempts for the same founder.';

COMMENT ON COLUMN public.runtime_mint_intent.created_at IS
  'Insertion timestamp. The hook (migration 050) gates on '
  'created_at > NOW() - INTERVAL ''10 seconds'' to bound the race window.';

ALTER TABLE public.runtime_mint_intent ENABLE ROW LEVEL SECURITY;

-- No RLS policies: the table is only readable/writable by service_role and
-- supabase_auth_admin (granted explicitly below). PUBLIC/anon/authenticated
-- have no path to the rows even if RLS were disabled, but RLS-on is
-- defense-in-depth per Soleur's table-creation convention.

REVOKE ALL ON TABLE public.runtime_mint_intent FROM PUBLIC, anon, authenticated;

-- service_role: tenant.ts uses supabase-js .from().upsert() which compiles
-- to INSERT ... ON CONFLICT DO UPDATE — both INSERT and UPDATE are needed.
-- Narrow UPDATE to (created_at) — user_id is the PK and must never be
-- re-keyed; only the timestamp refreshes under ON CONFLICT.
GRANT INSERT ON TABLE public.runtime_mint_intent TO service_role;
GRANT UPDATE (created_at) ON TABLE public.runtime_mint_intent TO service_role;

-- supabase_auth_admin: the hook runs as this role. SELECT supports
-- diagnostic queries; DELETE is the load-bearing privilege for the
-- DELETE...RETURNING CTE in migration 050.
GRANT SELECT, DELETE ON TABLE public.runtime_mint_intent TO supabase_auth_admin;
