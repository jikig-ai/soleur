-- 177_egress_audit_summary_rpc.sql
-- #9545 PR2 — member read path for the workspace egress audit rollup.
--
-- Adds ONE function, get_egress_audit_summary, callable by CURRENT workspace
-- members only. It is the only read surface over public.workspace_egress_audit_rollup
-- (migration 162): there is deliberately NO member SELECT policy and NO table grant,
-- so a direct `.from(table).select()` stays a permission error. This supersedes the
-- 162 header / ADR-288 wording that a member SELECT policy "lands in PR2" (162 is on
-- main and immutable; the correction lives here and in ADR-288's amendment).
--
-- LAWFUL_BASIS: legitimate interests (Art. 6(1)(f)) — workspace members see which
-- external hosts their workspace's agents contacted; nine aggregate fields, no
-- per-person field, ~30 days retention (see the DPIA addendum t6 re-screen).
--
-- Contract (see knowledge-base/project/plans/2026-10-26-feat-egress-audit-read-path-plan.md D1):
--   * Authz is the FIRST statement: not a current member (pending, removed, other
--     tenant, anon, no uid) => SQLSTATE 42501 with a constant message that differs
--     from the engine's "permission denied for function", so a revoked grant and an
--     in-body denial can be told apart. The SECOND statement is the jti denylist
--     (is_jti_denied_from_jwt(), mirroring migration 127): a revoked-but-unexpired JWT
--     of a current member is refused with 42501 'egress audit: token denied', because a
--     definer bypasses the RESTRICTIVE jti RLS policies. Both denial messages start with
--     'egress audit: ' (the loader discriminates on that prefix). A bad p_decision
--     (22023) and the p_limit = 0 probe only run AFTER both checks.
--   * Every aggregate carries `workspace_id = p_workspace_id`: a definer bypasses RLS,
--     so that predicate is the tenant boundary once the gate passes.
--   * Fixed 30-day window on last_seen (the daily purge keys on last_seen), bounded
--     above by now() so a bucket ingest accepted from the near future never yields a
--     negative "X ago". bucket_start is a PK-led range-scan aid only.
--   * p_limit = 0 is the card's last-request probe: one backward PK probe of the newest
--     bucket that holds an eligible row (the inner max(bucket_start) applies the same
--     last_seen window, so an all-future-dated newest bucket falls back to an older one;
--     the seen_window CHECK keeps last_seen inside its bucket), not an O(window)
--     MAX(last_seen). The tenant predicate is in BOTH the inner and the outer query.
--   * p_limit > 0: ONE aggregation (CTE) feeds summary, rows and overflow. The summary
--     (all outcomes, '(other)' included) is computed from the window rows directly; the
--     host rows are a top-N (ORDER BY last_seen DESC LIMIT p_limit + 1, so
--     truncated = a row exists beyond p_limit) instead of a full ranked scan and count.
--     `w` is referenced twice (groups and summary) and is left MATERIALIZED (the default): it
--     spills to temp files at ~1.4M window rows, but marking it NOT MATERIALIZED was measured
--     3-5x slower at 50k and 250k rows and ~15% slower at 1.44M (two scans, worse plan).
--   * Counts are best-effort minimums, clamped to 9007199254740991 (JS MAX_SAFE_INTEGER)
--     so a huge stored count can neither raise 22003 on the bigint cast nor exceed what
--     the client can represent exactly.
--   * No statement_timeout clause: a function-level SET does not re-arm the running outer
--     statement (proved on Postgres 17). The bound is: role timeout (authenticated, 8 s)
--     + p_limit <= 500 clamp + PK-led scan + custom plan. `plan_cache_mode =
--     force_custom_plan` is pinned because after five executions in one session plpgsql
--     switches to a generic plan that walks workspace_egress_audit_rollup_last_seen_idx
--     across all workspaces (measured 19-34 ms -> 510-600 ms from call 6).
--   * Overflow rows ('(other)' host) are returned in a separate typed field, summed across
--     buckets and source hosts (each stored count is already a lower bound), never as a
--     host row. source_host is never exposed.

CREATE OR REPLACE FUNCTION public.get_egress_audit_summary(
  p_workspace_id uuid,
  p_limit        integer DEFAULT 200,
  p_decision     text    DEFAULT NULL
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
  v_lo     timestamptz := now() - interval '30 days';
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

REVOKE ALL ON FUNCTION public.get_egress_audit_summary(uuid, integer, text)
  FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_egress_audit_summary(uuid, integer, text)
  TO authenticated;

COMMENT ON FUNCTION public.get_egress_audit_summary(uuid, integer, text) IS
  'Member-only 30-day summary of the workspace egress audit rollup (#9545 PR2): '
  'summary, real-host rows (top-N by last_seen) and typed overflow. Raises 42501 for '
  'non-members and for a denied jti (messages start with "egress audit: "). '
  'Best-effort minimum counts clamped to 9007199254740991; no per-member or session data. '
  'p_limit = 0 returns only the last-request probe. No function-level timeout: the bound '
  'is the role timeout (8 s) + p_limit <= 500 clamp + PK-led scan + custom plan '
  '(plan_cache_mode = force_custom_plan avoids the generic-plan flip after 5 calls).';
