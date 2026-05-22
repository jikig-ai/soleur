-- 063_byok_delegations.sql
-- BYOK Delegations PR-A (#4232; parent #4229). Adds the
-- `public.byok_delegations` WORM ledger that lets a grantor fund a
-- grantee's BYOK runs within a single workspace, capped by a per-day +
-- per-hour USD budget, with revoke + Art. 17 cascade + cap-update flow.
--
-- LAWFUL_BASIS: Art. 6(1)(b) contract — the delegation row IS the
--   contract between grantor and grantee inside a shared workspace.
-- RETENTION: 7 years (joint controllership audit trail per DPD §2.3).
--
-- DEPENDENCY: mig 037 (audit_byok_use), mig 053 (is_workspace_member,
-- workspaces), mig 055 (audit_byok_use.workspace_id), mig 058
-- (workspace_member_attestations), mig 061 (write_byok_audit/
-- record_byok_use_and_check_cap 6-arg signatures). `runWithByokLease`
-- lease split lives at apps/web-platform/server/byok-lease.ts (PR
-- #4225); cites #4232 in the MissingByokKeyError ADR comment at lines
-- 101-122.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public FIRST).
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT
-- to the intended caller role(s) on every RPC.
--
-- Trigger (not CHECK) for same_workspace because is_workspace_member is
-- LANGUAGE plpgsql VOLATILE and cannot appear in a table CHECK.
--
-- WORM column-enumeration sentinel reminder: byok_delegations_no_mutate
-- enumerates every column of byok_delegations explicitly across three
-- legitimate UPDATE shapes (revoke flip / Art. 17 anonymise / cap-update
-- flip). FUTURE migrations that add columns to byok_delegations MUST
-- update this trigger too; the column-enum smoke test
-- (test/server/byok-delegations-worm-column-enum.test.ts) fails loudly
-- when information_schema.columns and pg_get_functiondef diverge.

BEGIN;

-- =====================================================================
-- 1. byok_delegations table
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.byok_delegations (
  id                      uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Identity columns. ON DELETE RESTRICT for all FKs: anonymise
  -- proceeds via UPDATE-to-NULL through WORM Shape 2 (see trigger), not
  -- by removing the parent row.
  grantor_user_id         uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
  grantee_user_id         uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
  workspace_id            uuid         REFERENCES public.workspaces(id) ON DELETE RESTRICT,
  -- Cap columns. v3 ceilings: $10K/day (SS F2 brand-survival floor),
  -- hourly ≤ daily as a secondary brake without PR-G dependency
  -- (Arch A1).
  daily_usd_cap_cents     int          CHECK (
    daily_usd_cap_cents IS NULL
    OR daily_usd_cap_cents BETWEEN 1 AND 1000000
  ),
  hourly_usd_cap_cents    int          CHECK (
    hourly_usd_cap_cents IS NULL
    OR (hourly_usd_cap_cents BETWEEN 1 AND 1000000)
  ),
  created_by_user_id      uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
  created_at              timestamptz  NOT NULL DEFAULT now(),
  expires_at              timestamptz  NULL,
  revoked_at              timestamptz  NULL,
  revoked_by_user_id      uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  revocation_reason       text         NULL CHECK (
    revocation_reason IS NULL OR revocation_reason IN (
      'grantor_revoke','grantee_decline','member_departed','admin_revoke','art_17_anonymise'
    )
  ),
  -- v3 Shape 3 (Arch A6): cap-update flip — daily/hourly may change
  -- accompanied by these two markers. WORM trigger enforces shape.
  cap_updated_at          timestamptz  NULL,
  cap_updated_by_user_id  uuid         NULL REFERENCES public.users(id) ON DELETE RESTRICT,

  -- Pre-anonymise invariants. After Shape 2 fires, identity cols are
  -- NULL and these table-level constraints intentionally do not
  -- reference them (NULL-tolerant via "IS NULL OR" guards).
  CONSTRAINT byok_delegations_grantor_distinct_from_grantee CHECK (
    grantor_user_id IS NULL
    OR grantee_user_id IS NULL
    OR grantor_user_id <> grantee_user_id
  ),
  CONSTRAINT byok_delegations_expires_after_created CHECK (
    expires_at IS NULL OR expires_at > created_at
  ),
  CONSTRAINT byok_delegations_revoked_after_created CHECK (
    revoked_at IS NULL OR revoked_at >= created_at
  ),
  CONSTRAINT byok_delegations_hourly_le_daily CHECK (
    hourly_usd_cap_cents IS NULL
    OR daily_usd_cap_cents IS NULL
    OR hourly_usd_cap_cents <= daily_usd_cap_cents
  ),
  -- Identity + cap columns are NOT NULL for non-anonymised rows. The
  -- anonymise path (Shape 2) intentionally nulls them; the WORM trigger
  -- enforces that the transition only happens via the anonymise shape,
  -- so direct INSERT of NULL identity is structurally impossible
  -- (write surface is gated by SECURITY DEFINER RPCs).
  CONSTRAINT byok_delegations_pre_anon_identity CHECK (
    -- Either every identity column is set (live row),
    -- or every one is NULL (post-anonymise row).
    (grantor_user_id IS NOT NULL AND grantee_user_id IS NOT NULL
     AND workspace_id IS NOT NULL AND created_by_user_id IS NOT NULL
     AND daily_usd_cap_cents IS NOT NULL AND hourly_usd_cap_cents IS NOT NULL)
    OR
    (grantor_user_id IS NULL AND grantee_user_id IS NULL
     AND workspace_id IS NULL AND created_by_user_id IS NULL)
  )
);

-- v3 (DIG F10): drop `expires_at > now()` from the unique-index
-- predicate. Postgres does not re-evaluate partial-index predicates
-- against now() after INSERT, so the v2 form would stay stale and
-- block re-grant after natural expiry. Active = "not revoked"; expiry
-- is enforced inside check_and_record_byok_delegation_use.
CREATE UNIQUE INDEX IF NOT EXISTS byok_delegations_active_triple_uidx
  ON public.byok_delegations (grantor_user_id, grantee_user_id, workspace_id)
  WHERE revoked_at IS NULL;

-- Hot path for resolve_byok_key_owner: "active delegation for grantee
-- in this workspace?"
CREATE INDEX IF NOT EXISTS byok_delegations_grantee_workspace_active_idx
  ON public.byok_delegations (grantee_user_id, workspace_id)
  WHERE revoked_at IS NULL;

-- =====================================================================
-- 2. audit_byok_use column additions (delegation attribution data
--    substrate per Arch A2; reconciliation flow consumes
--    attribution_shift_reason)
-- =====================================================================

ALTER TABLE public.audit_byok_use
  ADD COLUMN IF NOT EXISTS delegation_id uuid NULL
    REFERENCES public.byok_delegations(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS attribution_shift_reason text NULL
    CHECK (
      attribution_shift_reason IS NULL
      OR attribution_shift_reason IN ('revoked_post_grace','expired')
    );

-- v3 Phase 0.9 prereq: audit_byok_use.invocation_id was NOT NULL in
-- mig 037 but never UNIQUE. R4 idempotency (Inngest retries) requires
-- UNIQUE. Adding here under transaction safety.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'audit_byok_use_invocation_id_uniq'
       AND conrelid = 'public.audit_byok_use'::regclass
  ) THEN
    ALTER TABLE public.audit_byok_use
      ADD CONSTRAINT audit_byok_use_invocation_id_uniq UNIQUE (invocation_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS audit_byok_use_delegation_ts_idx
  ON public.audit_byok_use (delegation_id, ts)
  WHERE delegation_id IS NOT NULL;

-- =====================================================================
-- 3. same-workspace trigger
-- =====================================================================
--
-- Trigger (not CHECK) because public.is_workspace_member is LANGUAGE
-- plpgsql VOLATILE — table CHECK expressions cannot invoke such
-- functions. P0001 with `byok_delegations:cross-tenant: <role>` so the
-- TS layer can tag art_33_breach="true" on the Sentry event.

CREATE OR REPLACE FUNCTION public.byok_delegations_check_same_workspace()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- Tolerate the Shape 2 anonymise transition: when both grantor and
  -- grantee go NULL (and workspace too), is_workspace_member is
  -- inapplicable and the WORM trigger handles shape validation.
  IF NEW.grantor_user_id IS NULL AND NEW.grantee_user_id IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.workspace_id IS NULL THEN
    RAISE EXCEPTION 'byok_delegations:cross-tenant: workspace_id is NULL on live row'
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.grantor_user_id IS NOT NULL
     AND NOT public.is_workspace_member(NEW.workspace_id, NEW.grantor_user_id) THEN
    RAISE EXCEPTION 'byok_delegations:cross-tenant: grantor % is not a member of workspace %',
      NEW.grantor_user_id, NEW.workspace_id
      USING ERRCODE = 'P0001';
  END IF;

  IF NEW.grantee_user_id IS NOT NULL
     AND NOT public.is_workspace_member(NEW.workspace_id, NEW.grantee_user_id) THEN
    RAISE EXCEPTION 'byok_delegations:cross-tenant: grantee % is not a member of workspace %',
      NEW.grantee_user_id, NEW.workspace_id
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.byok_delegations_check_same_workspace()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS byok_delegations_same_workspace ON public.byok_delegations;
CREATE TRIGGER byok_delegations_same_workspace
  BEFORE INSERT OR UPDATE OF grantor_user_id, grantee_user_id, workspace_id
  ON public.byok_delegations
  FOR EACH ROW EXECUTE FUNCTION public.byok_delegations_check_same_workspace();

-- =====================================================================
-- 4. WORM trigger — three legitimate UPDATE shapes + DELETE rejection
-- =====================================================================
--
-- v3 shapes (Research Reconciliation row 5):
--   Shape 1 (revoke flip): revoked_at + revoked_by_user_id +
--     revocation_reason all NULL → non-NULL together; everything else
--     unchanged. Attribution constraint (DIG F1): revoked_by_user_id
--     IN (grantor, grantee, created_by).
--   Shape 2 (Art. 17 anonymise): identity cols + workspace_id +
--     revoked_by_user_id NULLed together; cap / timestamps / reason /
--     cap_updated_* preserved.
--   Shape 3 (cap-update flip, Arch A6): daily and/or hourly change
--     accompanied by cap_updated_at + cap_updated_by_user_id non-NULL;
--     everything else unchanged.
--
-- Structural-diff per learning 2026-05-18 (WORM-trigger-bypass-role-
-- check-fails-under-postgrest-routing): the trigger enumerates every
-- column explicitly. Future column additions MUST update this trigger
-- (column-enum smoke test enforces).

CREATE OR REPLACE FUNCTION public.byok_delegations_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'byok_delegations is append-only; use anonymise_byok_delegations for Art. 17'
      USING ERRCODE = 'P0001';
  END IF;

  -- Shape 2 (Art. 17 anonymise): identity columns transition non-NULL
  -- → NULL together; revoked_by_user_id NULLs only if it was set
  -- (must NULL when set; allowed to stay NULL if it was always NULL —
  -- e.g., anonymise without a prior revoke); cap_updated_by_user_id
  -- same. Cap values, created_at, expires_at, revoked_at,
  -- revocation_reason, cap_updated_at are preserved.
  IF OLD.grantor_user_id IS NOT NULL AND NEW.grantor_user_id IS NULL
     AND OLD.grantee_user_id IS NOT NULL AND NEW.grantee_user_id IS NULL
     AND OLD.workspace_id IS NOT NULL AND NEW.workspace_id IS NULL
     AND OLD.created_by_user_id IS NOT NULL AND NEW.created_by_user_id IS NULL
     AND NOT (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents)
     AND NOT (OLD.hourly_usd_cap_cents IS DISTINCT FROM NEW.hourly_usd_cap_cents)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
     AND NOT (OLD.revoked_at IS DISTINCT FROM NEW.revoked_at)
     AND NOT (OLD.revocation_reason IS DISTINCT FROM NEW.revocation_reason)
     AND NOT (OLD.cap_updated_at IS DISTINCT FROM NEW.cap_updated_at)
     AND (
       -- revoked_by_user_id: if OLD was set, NEW must be NULL;
       -- if OLD was NULL, NEW must also be NULL.
       (OLD.revoked_by_user_id IS NOT NULL AND NEW.revoked_by_user_id IS NULL)
       OR (OLD.revoked_by_user_id IS NULL AND NEW.revoked_by_user_id IS NULL)
     )
     AND (
       (OLD.cap_updated_by_user_id IS NOT NULL AND NEW.cap_updated_by_user_id IS NULL)
       OR (OLD.cap_updated_by_user_id IS NULL AND NEW.cap_updated_by_user_id IS NULL)
     )
  THEN
    RETURN NEW;
  END IF;

  -- Shape 1 (revoke flip): revocation triplet NULL → non-NULL together.
  -- v3 attribution constraint (DIG F1): revoked_by_user_id ∈ {grantor,
  -- grantee, created_by} of THIS row — closes audit-ledger poison
  -- vector.
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL
     AND OLD.revoked_by_user_id IS NULL AND NEW.revoked_by_user_id IS NOT NULL
     AND OLD.revocation_reason IS NULL AND NEW.revocation_reason IS NOT NULL
     AND NEW.revoked_by_user_id IN (
       NEW.grantor_user_id, NEW.grantee_user_id, NEW.created_by_user_id
     )
     AND NOT (OLD.grantor_user_id IS DISTINCT FROM NEW.grantor_user_id)
     AND NOT (OLD.grantee_user_id IS DISTINCT FROM NEW.grantee_user_id)
     AND NOT (OLD.workspace_id IS DISTINCT FROM NEW.workspace_id)
     AND NOT (OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents)
     AND NOT (OLD.hourly_usd_cap_cents IS DISTINCT FROM NEW.hourly_usd_cap_cents)
     AND NOT (OLD.created_by_user_id IS DISTINCT FROM NEW.created_by_user_id)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
     AND NOT (OLD.cap_updated_at IS DISTINCT FROM NEW.cap_updated_at)
     AND NOT (OLD.cap_updated_by_user_id IS DISTINCT FROM NEW.cap_updated_by_user_id)
  THEN
    RETURN NEW;
  END IF;

  -- Shape 3 (cap-update flip, Arch A6): daily and/or hourly cap change
  -- accompanied by cap_updated_at + cap_updated_by_user_id non-NULL;
  -- every other column unchanged. Enables "raise Harry's budget" UX
  -- without breaking audit continuity.
  IF NEW.cap_updated_at IS NOT NULL
     AND NEW.cap_updated_by_user_id IS NOT NULL
     AND (
       OLD.daily_usd_cap_cents IS DISTINCT FROM NEW.daily_usd_cap_cents
       OR OLD.hourly_usd_cap_cents IS DISTINCT FROM NEW.hourly_usd_cap_cents
     )
     AND NOT (OLD.grantor_user_id IS DISTINCT FROM NEW.grantor_user_id)
     AND NOT (OLD.grantee_user_id IS DISTINCT FROM NEW.grantee_user_id)
     AND NOT (OLD.workspace_id IS DISTINCT FROM NEW.workspace_id)
     AND NOT (OLD.created_by_user_id IS DISTINCT FROM NEW.created_by_user_id)
     AND NOT (OLD.created_at IS DISTINCT FROM NEW.created_at)
     AND NOT (OLD.expires_at IS DISTINCT FROM NEW.expires_at)
     AND NOT (OLD.revoked_at IS DISTINCT FROM NEW.revoked_at)
     AND NOT (OLD.revoked_by_user_id IS DISTINCT FROM NEW.revoked_by_user_id)
     AND NOT (OLD.revocation_reason IS DISTINCT FROM NEW.revocation_reason)
  THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'byok_delegations: only revoke flip, Art. 17 anonymise, or cap-update flip shapes are permitted'
    USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.byok_delegations_no_mutate()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS byok_delegations_no_update ON public.byok_delegations;
CREATE TRIGGER byok_delegations_no_update
  BEFORE UPDATE ON public.byok_delegations
  FOR EACH ROW EXECUTE FUNCTION public.byok_delegations_no_mutate();

DROP TRIGGER IF EXISTS byok_delegations_no_delete ON public.byok_delegations;
CREATE TRIGGER byok_delegations_no_delete
  BEFORE DELETE ON public.byok_delegations
  FOR EACH ROW EXECUTE FUNCTION public.byok_delegations_no_mutate();

-- =====================================================================
-- 5. RLS
-- =====================================================================

ALTER TABLE public.byok_delegations ENABLE ROW LEVEL SECURITY;

-- Workspace members may SELECT their own delegations (either side).
CREATE POLICY byok_delegations_select_for_parties ON public.byok_delegations
  FOR SELECT TO authenticated
  USING (
    workspace_id IS NOT NULL
    AND public.is_workspace_member(workspace_id, auth.uid())
    AND (
      grantor_user_id = auth.uid()
      OR grantee_user_id = auth.uid()
    )
  );

-- All writes are gated through SECURITY DEFINER RPCs; no INSERT/UPDATE/
-- DELETE policy exists, and explicit REVOKE keeps grant-flagged
-- callers out.
REVOKE INSERT, UPDATE, DELETE ON TABLE public.byok_delegations
  FROM PUBLIC, anon, authenticated;

-- =====================================================================
-- 6. RPC: grant_byok_delegation — admin + self consolidated (Arch A3)
-- =====================================================================
--
-- Branches on auth.uid() IS NULL:
--   Service-role (auth.uid() NULL): admin path. p_grantor_user_id and
--     p_actor_user_id both required.
--   Authenticated (auth.uid() set): self path. p_grantor_user_id /
--     p_actor_user_id must be NULL or match auth.uid().
--
-- The cross-tenant + WORM triggers fire on INSERT and enforce the rest.

CREATE OR REPLACE FUNCTION public.grant_byok_delegation(
  p_grantor_user_id      uuid,
  p_grantee_user_id      uuid,
  p_workspace_id         uuid,
  p_daily_usd_cap_cents  int,
  p_hourly_usd_cap_cents int,
  p_expires_at           timestamptz,
  p_actor_user_id        uuid
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_jwt uuid := auth.uid();
  v_grantor    uuid;
  v_actor      uuid;
  v_id         uuid;
BEGIN
  IF v_caller_jwt IS NULL THEN
    -- Service-role path (auth.uid() not set).
    IF p_grantor_user_id IS NULL OR p_actor_user_id IS NULL THEN
      RAISE EXCEPTION 'grant_byok_delegation: service-role caller MUST supply p_grantor_user_id and p_actor_user_id'
        USING ERRCODE = '22023';
    END IF;
    v_grantor := p_grantor_user_id;
    v_actor   := p_actor_user_id;
  ELSE
    -- Authenticated path: grantor + actor MUST be NULL or equal auth.uid().
    IF p_grantor_user_id IS NOT NULL AND p_grantor_user_id <> v_caller_jwt THEN
      RAISE EXCEPTION 'grant_byok_delegation: authenticated caller MAY NOT grant on behalf of another user'
        USING ERRCODE = '42501';
    END IF;
    IF p_actor_user_id IS NOT NULL AND p_actor_user_id <> v_caller_jwt THEN
      RAISE EXCEPTION 'grant_byok_delegation: authenticated caller MAY NOT impersonate another actor'
        USING ERRCODE = '42501';
    END IF;
    v_grantor := v_caller_jwt;
    v_actor   := v_caller_jwt;
  END IF;

  -- Cap bound checks: distinct SQLSTATEs for clean CLI / UI mapping.
  IF p_daily_usd_cap_cents IS NULL
     OR p_daily_usd_cap_cents < 1
     OR p_daily_usd_cap_cents > 1000000 THEN
    RAISE EXCEPTION 'grant_byok_delegation: daily_usd_cap_cents out of range [1, 1000000]; got %',
      p_daily_usd_cap_cents
      USING ERRCODE = '22003';
  END IF;
  IF p_hourly_usd_cap_cents IS NULL
     OR p_hourly_usd_cap_cents < 1
     OR p_hourly_usd_cap_cents > p_daily_usd_cap_cents THEN
    RAISE EXCEPTION 'grant_byok_delegation: hourly_usd_cap_cents out of range [1, daily=%]; got %',
      p_daily_usd_cap_cents, p_hourly_usd_cap_cents
      USING ERRCODE = '22003';
  END IF;

  INSERT INTO public.byok_delegations (
    grantor_user_id, grantee_user_id, workspace_id,
    daily_usd_cap_cents, hourly_usd_cap_cents,
    created_by_user_id, expires_at
  ) VALUES (
    v_grantor, p_grantee_user_id, p_workspace_id,
    p_daily_usd_cap_cents, p_hourly_usd_cap_cents,
    v_actor, p_expires_at
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.grant_byok_delegation(uuid, uuid, uuid, int, int, timestamptz, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_byok_delegation(uuid, uuid, uuid, int, int, timestamptz, uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.grant_byok_delegation(uuid, uuid, uuid, int, int, timestamptz, uuid) IS
  'Create a byok_delegations row. Branches on auth.uid() IS NULL: '
  'service-role admin path requires p_grantor_user_id + p_actor_user_id; '
  'authenticated self path forces grantor=actor=auth.uid(). Cross-tenant '
  '+ WORM triggers gate the INSERT.';

-- =====================================================================
-- 7. RPC: revoke_byok_delegation — admin + self consolidated
-- =====================================================================

CREATE OR REPLACE FUNCTION public.revoke_byok_delegation(
  p_delegation_id  uuid,
  p_actor_user_id  uuid,
  p_reason         text
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_jwt uuid := auth.uid();
  v_actor      uuid;
  v_row        public.byok_delegations%ROWTYPE;
BEGIN
  -- SS F9: callers may only emit grantor_revoke / grantee_decline /
  -- admin_revoke. member_departed + art_17_anonymise are reserved for
  -- the trigger / cascade paths.
  IF p_reason NOT IN ('grantor_revoke','grantee_decline','admin_revoke') THEN
    RAISE EXCEPTION 'revoke_byok_delegation: reason % is reserved for trigger/cascade paths', p_reason
      USING ERRCODE = '22023';
  END IF;

  IF v_caller_jwt IS NULL THEN
    IF p_actor_user_id IS NULL THEN
      RAISE EXCEPTION 'revoke_byok_delegation: service-role caller MUST supply p_actor_user_id'
        USING ERRCODE = '22023';
    END IF;
    v_actor := p_actor_user_id;
  ELSE
    IF p_actor_user_id IS NOT NULL AND p_actor_user_id <> v_caller_jwt THEN
      RAISE EXCEPTION 'revoke_byok_delegation: authenticated caller MAY NOT impersonate another actor'
        USING ERRCODE = '42501';
    END IF;
    v_actor := v_caller_jwt;
  END IF;

  -- Row-lock + load the OLD shape so we can validate attribution and
  -- idempotency without leaking write attempts past the WORM trigger
  -- for already-revoked rows.
  SELECT * INTO v_row
    FROM public.byok_delegations
   WHERE id = p_delegation_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'revoke_byok_delegation: delegation % not found', p_delegation_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.revoked_at IS NOT NULL THEN
    -- Idempotent: nothing to do. Surface a recognisable SQLSTATE so
    -- callers can swallow it.
    RAISE EXCEPTION 'revoke_byok_delegation: delegation % already revoked at %',
      p_delegation_id, v_row.revoked_at
      USING ERRCODE = 'P0001', DETAIL = 'byok_delegations:already_revoked';
  END IF;

  -- Attribution: actor MUST be grantor, grantee, or created_by of THIS
  -- row (matches WORM Shape 1 constraint).
  IF v_actor NOT IN (
    v_row.grantor_user_id, v_row.grantee_user_id, v_row.created_by_user_id
  ) THEN
    RAISE EXCEPTION 'revoke_byok_delegation: actor % is not grantor/grantee/created_by of delegation %',
      v_actor, p_delegation_id
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.byok_delegations
     SET revoked_at         = clock_timestamp(),
         revoked_by_user_id = v_actor,
         revocation_reason  = p_reason
   WHERE id = p_delegation_id;
END;
$$;

REVOKE ALL ON FUNCTION public.revoke_byok_delegation(uuid, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_byok_delegation(uuid, uuid, text)
  TO authenticated, service_role;

-- =====================================================================
-- 8. RPC: resolve_byok_key_owner — service-role only
-- =====================================================================
--
-- v3 signature: p_workspace_id is explicit (DIG F3 — closes wrong-
-- workspace inference for multi-workspace grantees). The TS layer
-- derives workspace_id via getDefaultWorkspaceForUser before invoking.

CREATE OR REPLACE FUNCTION public.resolve_byok_key_owner(
  p_caller_user_id uuid,
  p_workspace_id   uuid
) RETURNS TABLE (
  key_owner_user_id uuid,
  delegation_id     uuid
)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'resolve_byok_key_owner: p_caller_user_id is NULL'
      USING ERRCODE = '22023';
  END IF;

  -- Own-key precedence: if caller has their own api_keys row, return
  -- (caller, NULL) — solo behavior preserved bit-for-bit.
  IF EXISTS (
    SELECT 1 FROM public.api_keys WHERE user_id = p_caller_user_id
  ) THEN
    key_owner_user_id := p_caller_user_id;
    delegation_id     := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  -- Look for an active delegation in the supplied workspace. Use
  -- clock_timestamp() (not now()) for expires comparison so a long-
  -- running transaction that opened pre-expiry cannot keep using a
  -- stale "not yet expired" view (SS F1).
  RETURN QUERY
    SELECT bd.grantor_user_id, bd.id
      FROM public.byok_delegations bd
     WHERE bd.grantee_user_id = p_caller_user_id
       AND bd.workspace_id    = p_workspace_id
       AND bd.revoked_at IS NULL
       AND (bd.expires_at IS NULL OR bd.expires_at > clock_timestamp())
     ORDER BY bd.created_at DESC
     LIMIT 1;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_byok_key_owner(uuid, uuid)
  TO service_role;

-- =====================================================================
-- 9. RPC: check_and_record_byok_delegation_use — v3 merged atomic RPC
-- =====================================================================
--
-- Closes DIG F4 (cap-check concurrency hole). Single transaction under
-- one FOR UPDATE row lock:
--   1. SELECT FOR UPDATE on the delegation row.
--   2. Grace check (clock_timestamp() > revoked_at + 60s) → audit row
--      with attribution_shift_reason='revoked_post_grace' + raise.
--   3. Expired check (clock_timestamp() > expires_at) → audit row with
--      attribution_shift_reason='expired' + raise.
--   4. Hourly cap SUM (rolling 1h) → raise on exceed (no audit row).
--   5. Daily cap SUM (rolling 24h) → raise on exceed (no audit row).
--   6. Pass → INSERT audit row with normal attribution (founder_id =
--      grantor_user_id).

CREATE OR REPLACE FUNCTION public.check_and_record_byok_delegation_use(
  p_delegation_id    uuid,
  p_invocation_id    uuid,
  p_token_count      int,
  p_unit_cost_cents  int,
  p_caller_user_id   uuid,
  p_agent_role       text
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_row             public.byok_delegations%ROWTYPE;
  v_this_cost       int := p_token_count * p_unit_cost_cents;
  v_hourly_spent    int;
  v_daily_spent     int;
BEGIN
  IF p_delegation_id IS NULL OR p_caller_user_id IS NULL THEN
    RAISE EXCEPTION 'check_and_record_byok_delegation_use: p_delegation_id and p_caller_user_id are required'
      USING ERRCODE = '22023';
  END IF;

  -- Row lock. Serializes concurrent callers against the same
  -- delegation; both the grace/expiry checks and the cap SUM run
  -- under this lock, closing the SUM-then-INSERT race.
  SELECT * INTO v_row
    FROM public.byok_delegations
   WHERE id = p_delegation_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'check_and_record_byok_delegation_use: delegation % not found', p_delegation_id
      USING ERRCODE = 'P0002';
  END IF;

  IF v_row.grantor_user_id IS NULL OR v_row.workspace_id IS NULL THEN
    -- Anonymised delegation cannot fund new runs.
    RAISE EXCEPTION 'byok_delegations:anonymised'
      USING ERRCODE = 'P0001';
  END IF;

  -- Grace check (clock_timestamp() not now()): if revoked > 60s ago,
  -- write the audit row with the shift reason then raise.
  IF v_row.revoked_at IS NOT NULL
     AND clock_timestamp() > v_row.revoked_at + interval '60 seconds' THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'revoked_post_grace'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:revoked_post_grace'
      USING ERRCODE = 'P0001';
  END IF;

  -- Expired check.
  IF v_row.expires_at IS NOT NULL
     AND clock_timestamp() > v_row.expires_at THEN
    INSERT INTO public.audit_byok_use (
      invocation_id, founder_id, workspace_id, agent_role,
      token_count, unit_cost_cents, delegation_id, attribution_shift_reason
    ) VALUES (
      p_invocation_id, p_caller_user_id, v_row.workspace_id, p_agent_role,
      p_token_count, p_unit_cost_cents, p_delegation_id, 'expired'
    )
    ON CONFLICT (invocation_id) DO NOTHING;
    RAISE EXCEPTION 'byok_delegations:expired'
      USING ERRCODE = 'P0001';
  END IF;

  -- Hourly cap SUM (rolling 1h via clock_timestamp() so long txns
  -- don't see a stale window). Includes prior charges only — current
  -- charge has not been recorded yet.
  SELECT COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
    INTO v_hourly_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '1 hour';

  IF v_hourly_spent + v_this_cost > v_row.hourly_usd_cap_cents THEN
    RAISE EXCEPTION 'byok_delegations:hourly_cap_exceeded'
      USING ERRCODE = 'P0001',
            DETAIL = format('hourly cap %s cents, spent %s, attempted +%s',
                            v_row.hourly_usd_cap_cents, v_hourly_spent, v_this_cost);
  END IF;

  -- Daily cap SUM (rolling 24h).
  SELECT COALESCE(SUM(au.token_count * au.unit_cost_cents), 0)::int
    INTO v_daily_spent
    FROM public.audit_byok_use au
   WHERE au.delegation_id = p_delegation_id
     AND au.ts > clock_timestamp() - interval '24 hours';

  IF v_daily_spent + v_this_cost > v_row.daily_usd_cap_cents THEN
    RAISE EXCEPTION 'byok_delegations:daily_cap_exceeded'
      USING ERRCODE = 'P0001',
            DETAIL = format('daily cap %s cents, spent %s, attempted +%s',
                            v_row.daily_usd_cap_cents, v_daily_spent, v_this_cost);
  END IF;

  -- Pass: write audit row with grantor attribution (the cost-shift
  -- reason is NULL — normal accounting).
  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, workspace_id, agent_role,
    token_count, unit_cost_cents, delegation_id, attribution_shift_reason
  ) VALUES (
    p_invocation_id, v_row.grantor_user_id, v_row.workspace_id, p_agent_role,
    p_token_count, p_unit_cost_cents, p_delegation_id, NULL
  )
  ON CONFLICT (invocation_id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text)
  TO service_role;

COMMENT ON FUNCTION public.check_and_record_byok_delegation_use(uuid, uuid, int, int, uuid, text) IS
  'Atomic per-delegation cap + audit RPC. Single txn under FOR UPDATE '
  'row lock: grace/expiry checks (clock_timestamp), hourly + daily cap '
  'SUMs, audit INSERT with attribution_shift_reason on post-grace/'
  'expired paths. Cap-exceeded raises WITHOUT writing audit row.';

-- =====================================================================
-- 10. RPC: anonymise_byok_delegations — Art. 17 cascade
-- =====================================================================
--
-- v3: also nulls workspace_id (Shape 2 expansion per DIG F6). Active-
-- row guard (SS F7): rows with revoked_at IS NULL must transition via
-- Shape 1 first (revocation_reason='art_17_anonymise', revoked_by =
-- p_user_id which satisfies the attribution constraint because
-- p_user_id IS one of grantor/grantee by the WHERE clause), then
-- Shape 2 anonymise.

CREATE OR REPLACE FUNCTION public.anonymise_byok_delegations(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- Phase 1: revoke any active rows for p_user_id with
  -- 'art_17_anonymise' reason. p_user_id is grantor or grantee by the
  -- WHERE clause, so the Shape 1 attribution constraint is satisfied.
  UPDATE public.byok_delegations
     SET revoked_at         = clock_timestamp(),
         revoked_by_user_id = p_user_id,
         revocation_reason  = 'art_17_anonymise'
   WHERE (grantor_user_id = p_user_id OR grantee_user_id = p_user_id)
     AND revoked_at IS NULL;

  -- Phase 2: anonymise (Shape 2). NULLs identity + workspace + actor
  -- columns. Cap columns and timestamps preserved for the 7y audit
  -- retention.
  UPDATE public.byok_delegations
     SET grantor_user_id        = NULL,
         grantee_user_id        = NULL,
         workspace_id           = NULL,
         created_by_user_id     = NULL,
         revoked_by_user_id     = NULL,
         cap_updated_by_user_id = NULL
   WHERE grantor_user_id = p_user_id
      OR grantee_user_id = p_user_id
      OR created_by_user_id = p_user_id
      OR revoked_by_user_id = p_user_id
      OR cap_updated_by_user_id = p_user_id;

  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_byok_delegations(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_byok_delegations(uuid)
  TO service_role;

-- =====================================================================
-- 11. Member-departure auto-revoke trigger
-- =====================================================================

CREATE OR REPLACE FUNCTION public.byok_delegations_on_member_delete()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.byok_delegations
     SET revoked_at         = clock_timestamp(),
         revoked_by_user_id = OLD.user_id,
         revocation_reason  = 'member_departed'
   WHERE (grantor_user_id = OLD.user_id OR grantee_user_id = OLD.user_id)
     AND workspace_id      = OLD.workspace_id
     AND revoked_at IS NULL;
  RETURN OLD;
END;
$$;

REVOKE ALL ON FUNCTION public.byok_delegations_on_member_delete()
  FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS workspace_members_byok_delegations_revoke ON public.workspace_members;
CREATE TRIGGER workspace_members_byok_delegations_revoke
  AFTER DELETE ON public.workspace_members
  FOR EACH ROW EXECUTE FUNCTION public.byok_delegations_on_member_delete();

-- =====================================================================
-- 12. Table comment
-- =====================================================================

COMMENT ON TABLE public.byok_delegations IS
  'WORM ledger of grantor->grantee BYOK funding within a workspace. '
  'PR-A (#4232). Three legitimate UPDATE shapes: revoke flip, Art. 17 '
  'anonymise, cap-update flip. RLS self+counterparty SELECT only. '
  'Writes via SECURITY DEFINER RPCs only. Cost attribution shifts to '
  'caller with attribution_shift_reason set when revoke-grace or '
  'expiry is breached mid-turn (Arch A2 reconciliation substrate).';

COMMIT;

-- Tracking row written in the same transaction by run-migrations.sh
-- (canonical) or by the Doppler+pg fallback applier (per AGENTS.md
-- §"Tracking row in the SAME transaction as the migration body").
