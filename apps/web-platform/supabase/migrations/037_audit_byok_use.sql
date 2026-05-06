-- 037_audit_byok_use.sql
-- PR-B (#3244) — Soleur server-side agentic runtime: BYOK audit + JWT
-- mint coordination tables.
--
-- Resolution A (#3363): Node holds SUPABASE_JWT_SECRET; this migration
-- supplies the DB-resident invariants (rate limit, jti generation,
-- audit row writes) but NOT the JWT signing — Node does that with
-- jsonwebtoken using the claims from precheck_jwt_mint plus static
-- claims (sub = founder_id, role = 'authenticated', aud = 'soleur-runtime',
-- iss = supabase project URL).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every
-- SECURITY DEFINER function pins SET search_path = public, pg_temp
-- (in that order, public first) and qualifies every relation as
-- public.<table>.
--
-- Per 2026-04-18-supabase-migration-concurrently-forbidden: NO
-- CREATE INDEX CONCURRENTLY (Supabase wraps each migration in a
-- transaction).

-- ============================================================================
-- audit_byok_use: append-only WORM audit table for every BYOK use.
--
-- One row per Anthropic SDK call inside runWithByokLease. RLS
-- founder-readable so the usage dashboard (PR-D §3.1 Today section)
-- can read without service-role; WORM enforced by trigger so service-
-- role cannot retroactively edit (the trigger drop is itself a
-- forensic signal logged elsewhere).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.audit_byok_use (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  invocation_id   uuid         NOT NULL,
  founder_id      uuid         NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  agent_role      text         NOT NULL,
  ts              timestamptz  NOT NULL DEFAULT now(),
  token_count     int          NOT NULL,
  unit_cost_cents int          NOT NULL,
  created_at      timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.audit_byok_use ENABLE ROW LEVEL SECURITY;

-- Founder-readable SELECT only. No INSERT/UPDATE/DELETE policies; writes
-- go through write_byok_audit (SECURITY DEFINER) below.
CREATE POLICY audit_byok_use_owner_select ON public.audit_byok_use
  FOR SELECT USING (auth.uid() = founder_id);

-- WORM trigger function. Raised on UPDATE or DELETE.
CREATE OR REPLACE FUNCTION public.audit_byok_use_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'audit_byok_use is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.audit_byok_use_no_mutate() FROM PUBLIC;

CREATE TRIGGER audit_byok_use_no_update
  BEFORE UPDATE ON public.audit_byok_use
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.audit_byok_use_no_mutate();

CREATE TRIGGER audit_byok_use_no_delete
  BEFORE DELETE ON public.audit_byok_use
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.audit_byok_use_no_mutate();

-- Covering index for the §3.5 sliding-window SUM hot path. INCLUDE
-- enables index-only scans on the per-Anthropic-call gate.
CREATE INDEX audit_byok_use_founder_ts_idx
  ON public.audit_byok_use (founder_id, ts DESC)
  INCLUDE (token_count, unit_cost_cents);

-- write_byok_audit: append-only RPC, service-role only.
CREATE OR REPLACE FUNCTION public.write_byok_audit(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.audit_byok_use(
    invocation_id, founder_id, agent_role, token_count, unit_cost_cents
  )
  VALUES (
    p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents
  );
$$;

REVOKE ALL ON FUNCTION public.write_byok_audit(uuid, uuid, text, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.write_byok_audit(uuid, uuid, text, int, int) TO service_role;

COMMENT ON TABLE public.audit_byok_use IS
  'Append-only audit row per Anthropic SDK call inside runWithByokLease. '
  'Founder-readable; WORM enforced by trigger. PR-B #3244.';

COMMENT ON FUNCTION public.write_byok_audit(uuid, uuid, text, int, int) IS
  'Service-role-only writer for audit_byok_use. RLS-bypass via SECURITY DEFINER.';

-- ============================================================================
-- denied_jti: revocation list for runtime JWTs (jti claim).
--
-- Auth probe in lib/supabase/tenant.ts checks is_jti_denied(jti)
-- before accepting a cached JWT in getFreshTenantClient. Service-role-
-- only via the SECURITY DEFINER reader below — no founder needs to
-- query the table directly.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.denied_jti (
  jti         uuid         PRIMARY KEY,
  founder_id  uuid         NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  denied_at   timestamptz  NOT NULL DEFAULT now(),
  reason      text
);

ALTER TABLE public.denied_jti ENABLE ROW LEVEL SECURITY;
-- Zero policies: service-role-only via is_jti_denied SECURITY DEFINER fn.

CREATE INDEX denied_jti_founder_idx ON public.denied_jti (founder_id, denied_at DESC);

CREATE OR REPLACE FUNCTION public.is_jti_denied(p_jti uuid) RETURNS boolean
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
  STABLE
AS $$
  SELECT EXISTS (SELECT 1 FROM public.denied_jti WHERE jti = p_jti);
$$;

REVOKE ALL ON FUNCTION public.is_jti_denied(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_jti_denied(uuid) TO service_role;

COMMENT ON TABLE public.denied_jti IS
  'Revocation list for runtime JWTs. Service-role-only insert; '
  'reads via is_jti_denied SECURITY DEFINER fn. PR-B #3244.';

-- ============================================================================
-- mint_rate_window: per-founder JWT-mint rate limit (60/hour rolling).
--
-- Anomalous mint patterns are a compromise indicator. Service-role-
-- only via precheck_jwt_mint RPC below.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.mint_rate_window (
  founder_id   uuid         PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  window_start timestamptz  NOT NULL DEFAULT now(),
  mints_count  int          NOT NULL DEFAULT 0
);

ALTER TABLE public.mint_rate_window ENABLE ROW LEVEL SECURITY;
-- Zero policies: service-role-only via precheck_jwt_mint RPC.

-- precheck_jwt_mint: atomic rate-limit increment + jti generation.
--
-- Resolution A (#3363) shape: returns the non-secret claim values
-- (jti, exp, iat) that Node combines with static claims (sub, role,
-- aud, iss) before signing with SUPABASE_JWT_SECRET via jsonwebtoken.
--
-- Race-safety: INSERT ... ON CONFLICT DO UPDATE acquires the row-level
-- lock before incrementing, so two concurrent calls for the same
-- founder produce exactly two increments (not one or zero). When the
-- post-increment count exceeds 60, RAISE EXCEPTION rolls back the
-- function's effects (plpgsql atomic-volatile semantics) so the
-- counter does NOT drift past 60.
--
-- Sliding-window approximation: a perfectly-timed call burst across a
-- 1h window boundary may permit ~120 mints (60 in the closing window,
-- 60 in the opening one). Acceptable — the gate is a compromise
-- indicator, not a hard ceiling.
CREATE OR REPLACE FUNCTION public.precheck_jwt_mint(
  p_founder_id uuid,
  p_ttl_sec    int DEFAULT 600
) RETURNS TABLE(jti uuid, exp_epoch int, iat_epoch int)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_now          timestamptz := now();
  v_window_start timestamptz;
  v_count        int;
BEGIN
  -- Atomic rate-limit increment under the row's lock.
  INSERT INTO public.mint_rate_window AS m (founder_id, window_start, mints_count)
  VALUES (p_founder_id, v_now, 1)
  ON CONFLICT (founder_id) DO UPDATE
    SET window_start = CASE
          WHEN m.window_start < v_now - interval '1 hour' THEN v_now
          ELSE m.window_start
        END,
        mints_count  = CASE
          WHEN m.window_start < v_now - interval '1 hour' THEN 1
          ELSE m.mints_count + 1
        END
  RETURNING m.window_start, m.mints_count INTO v_window_start, v_count;

  IF v_count > 60 THEN
    RAISE EXCEPTION 'mint_rate_exceeded' USING ERRCODE = 'P0001';
  END IF;

  RETURN QUERY SELECT
    gen_random_uuid()                                                 AS jti,
    EXTRACT(epoch FROM (v_now + (p_ttl_sec || ' seconds')::interval))::int AS exp_epoch,
    EXTRACT(epoch FROM v_now)::int                                    AS iat_epoch;
END;
$$;

REVOKE ALL ON FUNCTION public.precheck_jwt_mint(uuid, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.precheck_jwt_mint(uuid, int) TO service_role;

COMMENT ON TABLE public.mint_rate_window IS
  'Per-founder runtime-JWT-mint rate-limit state (60/hour rolling). '
  'Service-role-only via precheck_jwt_mint RPC. PR-B #3244.';

COMMENT ON FUNCTION public.precheck_jwt_mint(uuid, int) IS
  'Atomic rate-limit gate + jti supplier for runtime JWT minting. '
  'Returns (jti, exp_epoch, iat_epoch) so Node-side jsonwebtoken can '
  'combine with static claims (sub, role, aud=soleur-runtime, iss) '
  'and sign with SUPABASE_JWT_SECRET. PR-B #3244 / Resolution A #3363.';
