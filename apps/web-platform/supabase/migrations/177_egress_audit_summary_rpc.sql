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
--     in-body denial can be told apart. A bad p_decision (22023) is only raised AFTER
--     the check.
--   * Every aggregate carries `workspace_id = p_workspace_id`: a definer bypasses RLS,
--     so that predicate is the tenant boundary once the gate passes.
--   * Fixed 30-day window on last_seen (the daily purge keys on last_seen), bounded
--     above by now() so a bucket ingest accepted from the near future never yields a
--     negative "X ago". bucket_start is a PK-led range-scan aid only.
--   * p_limit = 0 is the card's last-request probe: one backward PK probe of the newest
--     non-empty bucket (the seen_window CHECK keeps last_seen inside its bucket), not an
--     O(window) MAX(last_seen).
--   * p_limit > 0: ONE aggregation (CTE) feeds summary, rows and overflow.
--   * No statement_timeout clause: a function-level SET does not re-arm the running outer
--     statement (proved on Postgres 17); the bound is the role timeout plus p_limit <= 500
--     and the PK-led scan.
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
           sum(w.request_count)::bigint AS request_count,
           max(w.last_seen) AS last_seen
      FROM w
     GROUP BY w.requested_host, w.decision
  ),
  s AS (
    SELECT coalesce(sum(g.request_count), 0)::bigint AS total,
           coalesce(sum(g.request_count) FILTER (WHERE g.decision = 'denied'), 0)::bigint AS blocked,
           max(g.last_seen) AS last_at
      FROM g
  ),
  r AS (
    SELECT g.host, g.decision, g.request_count, g.last_seen,
           row_number() OVER (ORDER BY g.last_seen DESC, g.host, g.decision) AS rn
      FROM g
     WHERE g.host <> '(other)'
       AND (p_decision IS NULL OR g.decision = p_decision)
  ),
  o AS (
    SELECT g.decision, g.request_count, g.last_seen
      FROM g
     WHERE g.host = '(other)'
       AND (p_decision IS NULL OR g.decision = p_decision)
  )
  SELECT jsonb_build_object(
           'window', jsonb_build_object('start', v_lo, 'end', v_now),
           'truncated', (SELECT count(*) FROM r) > v_limit,
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
                        'host', r.host,
                        'decision', r.decision,
                        'request_count', r.request_count,
                        'last_seen', r.last_seen)
                      ORDER BY r.last_seen DESC, r.host, r.decision)
               FROM r
              WHERE r.rn <= v_limit
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
  'summary, real-host rows and typed overflow. Raises 42501 for non-members. '
  'Best-effort minimum counts; no per-member or session data. p_limit = 0 returns '
  'only the last-request probe.';
