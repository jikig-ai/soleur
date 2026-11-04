-- 183_egress_audit_window_summary.sql
-- #11238 (epic #9601) — member read path for the workspace egress audit rollup, with a window.
--
-- Adds ONE function, get_egress_audit_window_summary(p_workspace_id, p_limit, p_decision,
-- p_window), callable by CURRENT workspace members only. p_window is one of '24h', '7d',
-- '30d' (no argument defaults). It is a SECOND function beside get_egress_audit_summary
-- (migration 177), which is untouched: it keeps serving the Scope Grants card hint and the
-- previous app image during a deploy. A distinct name rather than a 4-argument overload keeps
-- the RLS fuzz coverage gates (no overloaded definer function) and PostgREST named-argument
-- resolution unambiguous. See the ADR-288 amendment of 2026-11-03.
--
-- This file's function body is the 177 body, copied unchanged, except for the window
-- derivation: the 30-day constant in the declaration is replaced by v_span / v_lo, assigned
-- after the p_decision check from the allowlist map below. The text-parity guard in
-- test/supabase-migrations/183-egress-audit-window-summary.test.ts compares the two bodies
-- and names exactly that difference. Read the 177 header for the shared contract: authz is
-- the FIRST statement (membership, 42501, constant message), the jti denylist is the SECOND
-- (42501), a bad p_decision is 22023, the p_limit = 0 probe runs only after those, every
-- read carries `workspace_id = p_workspace_id` (a definer bypasses RLS, so that predicate is
-- the tenant boundary), counts are best-effort minimums clamped to 9007199254740991, and
-- there is no function-level statement timeout (plan_cache_mode = force_custom_plan is
-- pinned instead). Every denial message starts with 'egress audit: '.
--
-- LAWFUL_BASIS: legitimate interests (Art. 6(1)(f)) — workspace members see which
-- external hosts their workspace's agents contacted; nine aggregate fields, no
-- per-person field, ~30 days retention (see the DPIA addendum t6 re-screen). A shorter
-- window is a narrower read of the same stored aggregates: no column, table, policy,
-- vendor or retention change; the daily purge still keys on last_seen at 30 days.
--
-- Window semantics:
--   * last_seen >= now() - <window> and last_seen <= now() (bounded above by now()).
--   * bucket_start >= v_lo - 15 minutes is a PK-led range-scan aid only; the last_seen
--     predicate decides inclusion. A stored 15-minute bucket that began before the window
--     start but whose last_seen falls inside it is counted whole, so the period is
--     "about the last N", never exact.
--   * 'window' in the payload reports start = now() - span and end = now().
--
-- Rollout: apply this migration before the app image that calls it. Until PostgREST
-- reloads its schema cache a call can fail with PGRST202; the 177 function keeps working.

CREATE OR REPLACE FUNCTION public.get_egress_audit_window_summary(
  p_workspace_id uuid,
  p_limit        integer,
  p_decision     text,
  p_window       text
)
  RETURNS jsonb
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
  SET plan_cache_mode = force_custom_plan
AS $$
DECLARE
  v_limit  integer;
  v_now    timestamptz := now();
  v_span   interval;
  v_lo     timestamptz;
  v_last   timestamptz;
  v_result jsonb;
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_workspace_member(p_workspace_id, auth.uid()) THEN
    RAISE EXCEPTION 'egress audit: workspace membership required' USING ERRCODE = '42501';
  END IF;

  IF public.is_jti_denied_from_jwt() THEN
    RAISE EXCEPTION 'egress audit: token denied' USING ERRCODE = '42501';
  END IF;

  IF p_decision IS NOT NULL AND p_decision NOT IN ('allowed', 'denied', 'other') THEN
    RAISE EXCEPTION 'egress audit: invalid decision filter' USING ERRCODE = '22023';
  END IF;

  -- The window is derived from an allowlist map, never cast from caller text. NULL and any
  -- unknown value fall through the CASE (no ELSE) and are refused with 22023. This runs only
  -- AFTER the membership, jti and decision checks above.
  v_span := CASE p_window
              WHEN '24h' THEN interval '24 hours'
              WHEN '7d'  THEN interval '7 days'
              WHEN '30d' THEN interval '30 days'
            END;

  IF v_span IS NULL THEN
    RAISE EXCEPTION 'egress audit: invalid window' USING ERRCODE = '22023';
  END IF;

  v_lo := v_now - v_span;

  v_limit := LEAST(GREATEST(COALESCE(p_limit, 200), 0), 500);

  IF v_limit = 0 THEN
    SELECT max(t.last_seen)
      INTO v_last
      FROM public.workspace_egress_audit_rollup t
     WHERE t.workspace_id = p_workspace_id
       AND t.last_seen >= v_lo
       AND t.last_seen <= v_now
       AND t.bucket_start = (
             SELECT max(b.bucket_start)
               FROM public.workspace_egress_audit_rollup b
              WHERE b.workspace_id = p_workspace_id
                AND b.bucket_start <= v_now
                AND b.bucket_start >= v_lo - interval '15 minutes'
                AND b.last_seen >= v_lo
                AND b.last_seen <= v_now
           );

    RETURN jsonb_build_object(
      'window', jsonb_build_object('start', v_lo, 'end', v_now),
      'truncated', false,
      'summary', jsonb_build_object(
        'request_count_min', NULL,
        'blocked_request_count_min', NULL,
        'last_request_at', v_last
      ),
      'rows', '[]'::jsonb,
      'overflow', '[]'::jsonb
    );
  END IF;

  WITH w AS (
    SELECT t.requested_host, t.decision, t.request_count, t.last_seen
      FROM public.workspace_egress_audit_rollup t
     WHERE t.workspace_id = p_workspace_id
       AND t.bucket_start >= v_lo - interval '15 minutes'
       AND t.last_seen >= v_lo
       AND t.last_seen <= v_now
  ),
  g AS (
    SELECT w.requested_host AS host,
           w.decision,
           least(sum(w.request_count), 9007199254740991)::bigint AS request_count,
           max(w.last_seen) AS last_seen
      FROM w
     GROUP BY w.requested_host, w.decision
  ),
  s AS (
    SELECT least(coalesce(sum(w.request_count), 0), 9007199254740991)::bigint AS total,
           least(coalesce(sum(w.request_count) FILTER (WHERE w.decision = 'denied'), 0), 9007199254740991)::bigint AS blocked,
           max(w.last_seen) AS last_at
      FROM w
  ),
  r AS (
    SELECT g.host, g.decision, g.request_count, g.last_seen
      FROM g
     WHERE g.host <> '(other)'
       AND (p_decision IS NULL OR g.decision = p_decision)
     ORDER BY g.last_seen DESC, g.host, g.decision
     LIMIT v_limit + 1
  ),
  o AS (
    SELECT g.decision, g.request_count, g.last_seen
      FROM g
     WHERE g.host = '(other)'
       AND (p_decision IS NULL OR g.decision = p_decision)
  )
  SELECT jsonb_build_object(
           'window', jsonb_build_object('start', v_lo, 'end', v_now),
           'truncated', EXISTS (
             SELECT 1 FROM r ORDER BY r.last_seen DESC, r.host, r.decision OFFSET v_limit
           ),
           'summary', (
             SELECT jsonb_build_object(
                      'request_count_min', s.total,
                      'blocked_request_count_min', s.blocked,
                      'last_request_at', s.last_at)
               FROM s
           ),
           'rows', COALESCE((
             SELECT jsonb_agg(
                      jsonb_build_object(
                        'host', x.host,
                        'decision', x.decision,
                        'request_count', x.request_count,
                        'last_seen', x.last_seen)
                      ORDER BY x.last_seen DESC, x.host, x.decision)
               FROM (
                 SELECT r.host, r.decision, r.request_count, r.last_seen
                   FROM r
                  ORDER BY r.last_seen DESC, r.host, r.decision
                  LIMIT v_limit
               ) x
           ), '[]'::jsonb),
           'overflow', COALESCE((
             SELECT jsonb_agg(
                      jsonb_build_object(
                        'decision', o.decision,
                        'request_count', o.request_count,
                        'last_seen', o.last_seen)
                      ORDER BY o.decision)
               FROM o
           ), '[]'::jsonb)
         )
    INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_egress_audit_window_summary(uuid, integer, text, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_egress_audit_window_summary(uuid, integer, text, text)
  TO authenticated;

COMMENT ON FUNCTION public.get_egress_audit_window_summary(uuid, integer, text, text) IS
  'Member-only, windowed (24h/7d/30d) summary of the workspace egress audit rollup (#11238): '
  'summary, real-host rows (top-N by last_seen) and typed overflow. Raises 42501 for '
  'non-members and for a denied jti (messages start with "egress audit: "), then 22023 for a '
  'bad decision filter or window. Best-effort minimum counts clamped to 9007199254740991; '
  'a bucket straddling the window start is counted whole; no per-member or session data. '
  'p_limit = 0 returns only the last-request probe. No function-level timeout: the bound '
  'is the role timeout (8 s) + p_limit <= 500 clamp + PK-led scan + custom plan '
  '(plan_cache_mode = force_custom_plan avoids the generic-plan flip after 5 calls).';
