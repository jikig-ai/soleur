-- 046_runtime_cost_state.sql
-- PR-F (#3244, this slice): per-tenant cost attribution + atomic kill-switch
-- + drafts-everywhere CHECK constraint on public.messages.
--
-- Plan:      knowledge-base/project/plans/2026-05-17-feat-pr-f-inngest-trigger-layer-plan.md
-- ADR:       knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md
-- Brainstorm: knowledge-base/project/brainstorms/2026-05-17-pr-f-inngest-trigger-layer-brainstorm.md
--
-- Design notes:
--
--   * RV1 (Kieran P1.1 / DHH): rewrote `record_byok_use_and_check_cap`
--     as LANGUAGE plpgsql with leading `SELECT ... FROM public.users
--     WHERE id = p_founder_id FOR UPDATE` to close the TOCTOU race the
--     v1 CTE form left open. Two concurrent calls at cap-boundary
--     previously both passed the predicate; FOR UPDATE serializes
--     concurrent callers on the same founder row. Supersedes parent
--     plan §3.5 single-statement CTE shape.
--
--   * RV5 (DHH): adds `messages_external_tier_status_check` CHECK
--     constraint enforcing "drafts everywhere, sends nowhere" at the
--     DB level for external_* tiers. ADR-030 I5 records this as a
--     load-bearing brand-survival invariant. Future auto-send
--     capability requires explicit DROP + replacement of this
--     constraint AND Art. 22(3) right-to-human-review notice + DPD
--     update.
--
--   * Per cq-pg-security-definer-search-path-pin-pg-temp: every
--     SECURITY DEFINER fn pins SET search_path = public, pg_temp
--     (in that order, public first) and qualifies relations as
--     public.<table>.
--
--   * Per 2026-04-18-supabase-migration-concurrently-forbidden: NO
--     CREATE INDEX CONCURRENTLY (Supabase wraps each migration in a
--     transaction). Existing index from migration 037:
--       audit_byok_use_founder_ts_idx
--         ON public.audit_byok_use (founder_id, ts DESC)
--         INCLUDE (token_count, unit_cost_cents)
--     covers the 1-hour sliding-window SUM hot path — NO new index
--     required in this migration.
--
--   * Per 037 precedent: explicit `REVOKE ALL FROM PUBLIC, anon,
--     authenticated` is required because Supabase's
--     `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON
--     FUNCTIONS TO anon, authenticated, service_role` auto-grants
--     every new fn to all three roles. `REVOKE ALL FROM PUBLIC` does
--     NOT undo the explicit-role grants — the named-role revoke is
--     required.

-- ============================================================================
-- 1. Cost-state columns on public.users.
-- ============================================================================

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS runtime_paused_at    timestamptz,
  ADD COLUMN IF NOT EXISTS runtime_cost_cap_cents int NOT NULL DEFAULT 2000;

COMMENT ON COLUMN public.users.runtime_paused_at IS
  'Set by record_byok_use_and_check_cap() when the per-founder 1-hour '
  'cumulative cost exceeds runtime_cost_cap_cents. NULL = runtime active. '
  'Reset path lives outside PR-F (operator-driven for alpha). PR-F (#3244).';

COMMENT ON COLUMN public.users.runtime_cost_cap_cents IS
  'Per-tenant hourly cost cap in cents. Default 2000 = $20/hr per '
  'data-integrity P2-5 (200% headroom over realistic Sonnet 4.6 burn). '
  'PR-F (#3244).';

-- ============================================================================
-- 2. record_byok_use_and_check_cap — atomic plpgsql kill-switch.
--
-- RV1 (Kieran P1.1 / DHH): LANGUAGE plpgsql with leading FOR UPDATE
-- on public.users serializes concurrent callers on the same founder
-- row. The SUM that follows reads the post-INSERT snapshot (plpgsql
-- statements within a single function call share the surrounding
-- transaction, so the SUM sees the row this call just inserted).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_byok_use_and_check_cap(
  p_invocation_id   uuid,
  p_founder_id      uuid,
  p_agent_role      text,
  p_token_count     int,
  p_unit_cost_cents int
) RETURNS TABLE(cumulative_cents int, kill_tripped boolean)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_cap        int;
  v_paused_at  timestamptz;
  v_total      int;
  v_tripped    boolean := false;
BEGIN
  -- RV1 (Kieran P1.1): serialize concurrent callers on the same founder
  -- row BEFORE the prior-hour SUM. Without this lock, two concurrent
  -- calls at cap-boundary both pass the predicate (snapshot isolation
  -- reads each one's pre-INSERT state).
  SELECT runtime_cost_cap_cents, runtime_paused_at
    INTO v_cap, v_paused_at
    FROM public.users
   WHERE id = p_founder_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'record_byok_use_and_check_cap: founder % not found', p_founder_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Append the audit row first (accounting is sacred — even on
  -- already-paused tenants we record the call so cost-attribution
  -- stays accurate).
  INSERT INTO public.audit_byok_use (
    invocation_id, founder_id, agent_role, token_count, unit_cost_cents
  ) VALUES (
    p_invocation_id, p_founder_id, p_agent_role, p_token_count, p_unit_cost_cents
  );

  -- Sum prior-hour cents AFTER the INSERT. The lock above ensures no
  -- concurrent INSERT can race between this SUM and the UPDATE below.
  -- The SUM includes the row just inserted because plpgsql statements
  -- within a single function call share the surrounding transaction's
  -- view of the table.
  SELECT COALESCE(SUM(token_count * unit_cost_cents), 0)::int
    INTO v_total
    FROM public.audit_byok_use
   WHERE founder_id = p_founder_id
     AND ts > now() - interval '1 hour';

  -- Flip runtime_paused_at on cap breach (idempotent: only when
  -- previously NULL — a second cap-breach does not re-stamp).
  IF v_paused_at IS NULL AND v_total > v_cap THEN
    UPDATE public.users
       SET runtime_paused_at = now()
     WHERE id = p_founder_id
       AND runtime_paused_at IS NULL;
    v_tripped := true;
  END IF;

  cumulative_cents := v_total;
  kill_tripped     := v_tripped;
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int)
  TO service_role;

COMMENT ON FUNCTION public.record_byok_use_and_check_cap(uuid, uuid, text, int, int) IS
  'Atomic per-founder kill-switch: row-locks public.users, appends '
  'audit_byok_use row, SUMs 1-hour cumulative, flips runtime_paused_at '
  'on cap breach. Service-role-only. LANGUAGE plpgsql + FOR UPDATE per '
  'Kieran P1.1 plan-review (closes TOCTOU race the v1 CTE form left '
  'open). PR-F (#3244).';

-- ============================================================================
-- 3. messages_external_tier_status_check — "drafts everywhere, sends nowhere".
--
-- RV5 (DHH): promotes the ADR invariant to a DB-level CHECK constraint.
-- Future code attempting INSERT/UPDATE that lands `status='sent'` on a
-- row with `tier IN ('external_brand_critical', 'external_low_stakes')`
-- is rejected with SQLSTATE 23514. ADR-030 I5 records the amendment
-- contract: widening to permit auto-send requires explicit DROP +
-- replacement of this constraint AND Art. 22(3) notice + DPD update.
-- ============================================================================

ALTER TABLE public.messages
  ADD CONSTRAINT messages_external_tier_status_check
  CHECK (
    tier NOT IN ('external_brand_critical', 'external_low_stakes')
    OR status IN ('draft', 'archived')
  );

COMMENT ON CONSTRAINT messages_external_tier_status_check ON public.messages IS
  'PR-F (#3244) RV5: enforces "drafts everywhere, sends nowhere" for '
  'external_* tiers at the DB level. Widening to permit auto-send '
  'requires explicit DROP + replacement of this constraint AND Art. '
  '22(3) right-to-human-review notice + DPD update (see ADR-030 I5).';
