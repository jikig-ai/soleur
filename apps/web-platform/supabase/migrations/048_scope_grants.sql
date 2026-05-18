-- 048_scope_grants.sql
-- PR-G (#3947) — Per-action-class scope grants. Append-only WORM ledger
-- gating `inngest.send` in the Stripe webhook predicate (#3940 §F).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public FIRST).
-- Precedent: 044_add_tc_acceptances_ledger.sql.
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- service_role (or authenticated, as appropriate) on each caller-facing
-- RPC.

CREATE TABLE IF NOT EXISTS public.scope_grants (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  founder_id      uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
  -- NULL-able (not NOT NULL) so anonymise_scope_grants can zero the
  -- discriminator while keeping the audit row. Mirrors migration 044's
  -- tc_acceptances.user_id pattern. RLS `auth.uid() = founder_id` returns
  -- zero rows for NULL founder_id (any auth.uid() is non-NULL); INSERTs
  -- via grant_action_class always set founder_id = auth.uid() so the
  -- only legitimate NULL is the post-anonymise state.
  action_class    text         NOT NULL CHECK (length(action_class) BETWEEN 1 AND 64),
  tier            text         NOT NULL CHECK (tier IN ('auto','draft_one_click','approve_every_time')),
  granted_at      timestamptz  NOT NULL DEFAULT now(),
  revoked_at      timestamptz  NULL,
  revoked_reason  text         NULL CHECK (revoked_reason IS NULL OR length(revoked_reason) BETWEEN 1 AND 256),
  created_at      timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.scope_grants ENABLE ROW LEVEL SECURITY;

-- Founder-readable SELECT only. INSERT routed through grant_action_class
-- RPC; UPDATE only via revoke_action_class (column flip on revoked_at).
CREATE POLICY scope_grants_owner_select ON public.scope_grants
  FOR SELECT USING (auth.uid() = founder_id);

-- WORM trigger: only `revoked_at` and `revoked_reason` columns may be
-- updated, and only when transitioning NULL → non-NULL (revocation).
-- DELETE is unconditionally rejected (use anonymise_scope_grants for
-- Art. 17 cascade).
CREATE OR REPLACE FUNCTION public.scope_grants_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_anonymise_flag text;
BEGIN
  -- current_setting(name, missing_ok=true) returns '' (not NULL) when unset.
  v_anonymise_flag := current_setting('app.scope_grants_anonymise_in_progress', true);
  -- Bypass gate: GUC set. Role-check intentionally omitted — see #3984 CI
  -- failure analysis. Migration 044's `current_user = 'service_role'` check
  -- does NOT fire under PostgREST routing: inside a SECURITY DEFINER
  -- function body, current_user is the function OWNER (postgres in Supabase
  -- migrations), NOT the caller's PostgREST-set role. INVOKER triggers
  -- inherit that elevated context. The role check is silently always-false.
  -- 044's pattern was authored on a now-discredited theory of what INVOKER
  -- preserves and shipped without an integration test against PostgREST
  -- routing — see learning 2026-05-18-worm-trigger-bypass-role-check-fails-
  -- under-postgrest-routing.md.
  --
  -- Defense in depth WITHOUT the role check: (1) anonymise_scope_grants is
  -- the SINGLE SET-site for app.scope_grants_anonymise_in_progress in this
  -- migration (grep-verified at write time + lint-enforced going forward);
  -- (2) anonymise_scope_grants is SECURITY DEFINER + `REVOKE EXECUTE FROM
  -- PUBLIC, anon, authenticated` + `GRANT EXECUTE TO service_role` only,
  -- so only service_role-authenticated callers can ever set the GUC;
  -- (3) the GUC is `SET LOCAL` (transaction-scoped), so it auto-reverts at
  -- COMMIT/ROLLBACK and cannot leak across requests. The chain
  -- "service_role caller → SECURITY DEFINER function → SET LOCAL GUC →
  -- trigger sees GUC" is the proof of legitimate cascade; the role check
  -- was a redundant defense-in-depth that turned out to never fire.
  IF v_anonymise_flag <> '' THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'scope_grants is append-only; use anonymise_scope_grants for Art. 17 cascade' USING ERRCODE = 'P0001';
  END IF;

  -- TG_OP = 'UPDATE': allow only revoked_at / revoked_reason transitions
  -- from NULL to non-NULL.
  IF OLD.founder_id IS DISTINCT FROM NEW.founder_id
     OR OLD.action_class IS DISTINCT FROM NEW.action_class
     OR OLD.tier IS DISTINCT FROM NEW.tier
     OR OLD.granted_at IS DISTINCT FROM NEW.granted_at
     OR OLD.created_at IS DISTINCT FROM NEW.created_at
     OR (OLD.revoked_at IS NOT NULL AND NEW.revoked_at IS DISTINCT FROM OLD.revoked_at)
     OR (OLD.revoked_reason IS NOT NULL AND NEW.revoked_reason IS DISTINCT FROM OLD.revoked_reason)
  THEN
    RAISE EXCEPTION 'scope_grants is append-only; only NULL->value revocation is permitted' USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.scope_grants_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS scope_grants_no_update ON public.scope_grants;
CREATE TRIGGER scope_grants_no_update
  BEFORE UPDATE ON public.scope_grants
  FOR EACH ROW EXECUTE FUNCTION public.scope_grants_no_mutate();

DROP TRIGGER IF EXISTS scope_grants_no_delete ON public.scope_grants;
CREATE TRIGGER scope_grants_no_delete
  BEFORE DELETE ON public.scope_grants
  FOR EACH ROW EXECUTE FUNCTION public.scope_grants_no_mutate();

-- Covering index for the webhook predicate's "is there an active grant for
-- (founder_id, action_class)?" hot path. Filters on revoked_at IS NULL
-- via partial index keeps the index small.
CREATE INDEX scope_grants_active_idx
  ON public.scope_grants (founder_id, action_class, granted_at DESC)
  WHERE revoked_at IS NULL;

-- grant_action_class: founder-callable INSERT (NOT service-role-only —
-- unlike accept_terms, the founder is the authenticated caller).
CREATE OR REPLACE FUNCTION public.grant_action_class(
  p_action_class text,
  p_tier         text
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_grant_id   uuid;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated' USING ERRCODE = '28000';
  END IF;

  IF p_tier NOT IN ('auto','draft_one_click','approve_every_time') THEN
    RAISE EXCEPTION 'invalid tier: %', p_tier USING ERRCODE = '22P02';
  END IF;

  -- INSERT a fresh row; revoke the previous active grant for the same
  -- (founder_id, action_class) atomically. Tier change is a re-grant
  -- by design — preserves the chain of consent.
  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = 'tier_change'
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;

  INSERT INTO public.scope_grants (founder_id, action_class, tier)
       VALUES (v_founder_id, p_action_class, p_tier)
       RETURNING id INTO v_grant_id;

  RETURN v_grant_id;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_action_class(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.grant_action_class(text, text)
  TO authenticated;

-- revoke_action_class: founder-callable UPDATE (NULL → value transition
-- per WORM trigger).
CREATE OR REPLACE FUNCTION public.revoke_action_class(
  p_action_class text,
  p_reason       text
) RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_founder_id uuid := auth.uid();
  v_rows int;
BEGIN
  IF v_founder_id IS NULL THEN
    RAISE EXCEPTION 'auth.uid() is NULL — caller must be authenticated' USING ERRCODE = '28000';
  END IF;

  UPDATE public.scope_grants
     SET revoked_at = now(),
         revoked_reason = p_reason
   WHERE founder_id = v_founder_id
     AND action_class = p_action_class
     AND revoked_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_action_class(text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.revoke_action_class(text, text)
  TO authenticated;

-- anonymise_scope_grants: Art. 17 cascade. Mirror migration 044's
-- anonymise_tc_acceptances pattern. Called from account-delete.ts
-- BEFORE auth.admin.deleteUser() per ON DELETE RESTRICT FK ordering.
CREATE OR REPLACE FUNCTION public.anonymise_scope_grants(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- WORM-bypass: SET LOCAL scopes to the current transaction; reverts at
  -- COMMIT/ROLLBACK. THE SINGLE SET-SITE for this GUC. Mirrors migration
  -- 044's anonymise_tc_acceptances exactly (PERFORM set_config(..., true)
  -- is semantically equivalent but the literal `SET LOCAL` form is the
  -- one verified to fire the trigger bypass under PostgREST/service_role
  -- routing — see #3984 CI failure analysis).
  SET LOCAL app.scope_grants_anonymise_in_progress = 'on';

  UPDATE public.scope_grants
     SET founder_id = NULL
   WHERE founder_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_scope_grants(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_scope_grants(uuid)
  TO service_role;

COMMENT ON TABLE public.scope_grants IS
  'Append-only per-action-class scope grants. PR-G (#3947). One active '
  'row per (founder_id, action_class); tier change = revoke previous + '
  'insert new. WORM-gated; only revoked_at/revoked_reason mutable. '
  'auth.uid() = founder_id RLS self-select. Anonymise cascade via '
  'anonymise_scope_grants(user_id).';
