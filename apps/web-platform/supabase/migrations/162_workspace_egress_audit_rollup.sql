-- 162_workspace_egress_audit_rollup.sql
-- #9545 (PR1, dark ingest pipeline) — workspace-keyed 15-minute rollup of the
-- egress gateway's CONNECT decisions. Vector rolls the gateway log up per
-- workspace x host x decision x source host and posts closed buckets to the app
-- (POST /api/internal/egress-audit-ingest), which writes ONLY through
-- ingest_egress_audit_rollup below. Nothing reads this table in PR1: RLS is
-- enabled, NO member policy exists and every table privilege is revoked from
-- anon/authenticated. The member SELECT policy and read route land in PR2.
--
-- LAWFUL_BASIS: legitimate-interest (Art. 6(1)(f)) — accountability for what a
-- workspace's agents contacted on the open web; see the DPIA screening addendum
-- knowledge-base/legal/audits/2026-10-15-dpia-screening-addendum-egress-audit-rollup.md.
-- Retention is bounded to 30 days (purge_egress_audit_rollup, daily pg_cron) and
-- rows are deleted with the workspace (ON DELETE CASCADE) and on solo-account
-- erasure (erase_egress_audit_rollup, called by the account-delete saga because
-- the saga keeps the orphan workspace row, migration 065).
--
-- Not stored (DPIA trigger t7): resolved_ip, client address, duration, any user,
-- session or path value. Counts are best-effort LOWER BOUNDS: a Vector restart
-- loses partial buckets, and GREATEST (not SUM) keeps a journald-cursor replay
-- from overstating. The set of hosts and the decision are exact below the
-- per-workspace throttle cap (ADR-288).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp every SECURITY DEFINER
-- function pins `public, pg_temp`. No CREATE INDEX CONCURRENTLY (the migration
-- runs inside a transaction).

CREATE TABLE IF NOT EXISTS public.workspace_egress_audit_rollup (
  workspace_id   uuid        NOT NULL REFERENCES public.workspaces(id) ON DELETE CASCADE,
  bucket_start   timestamptz NOT NULL,
  -- The character set Vector's rollup allows (lower-case host name or address, an IPv6 literal in
  -- brackets) or the overflow row. No control characters, quotes, spaces or markup can be stored,
  -- so a later read surface never renders attacker-shaped text.
  requested_host text        NOT NULL CHECK (
                               char_length(requested_host) BETWEEN 1 AND 253
                               AND requested_host ~ '^([a-z0-9._:\[\]-]+|\(other\))$'),
  -- Normalised in Vector to allowed | denied | other (the gateway emits many %Ss values; the
  -- rollup maps them down), so the column is closed to those three.
  decision       text        NOT NULL CHECK (decision IN ('allowed', 'denied', 'other')),
  source_host    text        NOT NULL CHECK (source_host ~ '^[a-z0-9][a-z0-9-]{0,62}$'),
  request_count  bigint      NOT NULL CHECK (request_count >= 0),
  bytes_out      bigint      NOT NULL CHECK (bytes_out >= 0),
  first_seen     timestamptz NOT NULL,
  last_seen      timestamptz NOT NULL,
  PRIMARY KEY (workspace_id, bucket_start, requested_host, decision, source_host),
  -- Vector floors the event time to the 15-minute bucket and derives first_seen/last_seen from the
  -- same timestamps, so a legitimate row always satisfies these. They keep a forged or skewed value
  -- from landing outside its bucket (purge and the retention probe both key on last_seen).
  CONSTRAINT workspace_egress_audit_rollup_bucket_aligned
    CHECK (extract(epoch FROM bucket_start)::numeric % 900 = 0),
  CONSTRAINT workspace_egress_audit_rollup_seen_window
    CHECK (first_seen <= last_seen
           AND first_seen >= bucket_start
           AND last_seen < bucket_start + interval '15 minutes')
);

-- The retention sweep deletes by last_seen; the primary key serves per-workspace
-- reads by (workspace_id, bucket_start) in PR2.
CREATE INDEX IF NOT EXISTS workspace_egress_audit_rollup_last_seen_idx
  ON public.workspace_egress_audit_rollup (last_seen);

ALTER TABLE public.workspace_egress_audit_rollup ENABLE ROW LEVEL SECURITY;

-- Migration 058 revokes only INSERT/UPDATE/DELETE from tenants; this table also
-- revokes SELECT because no member policy exists yet (PR1 ships dark).
REVOKE ALL ON public.workspace_egress_audit_rollup FROM PUBLIC, anon, authenticated;

COMMENT ON TABLE public.workspace_egress_audit_rollup IS
  '#9545: 15-minute per-workspace rollup of egress gateway CONNECT decisions '
  '(host, allowed/denied, best-effort counts). Written only by '
  'ingest_egress_audit_rollup; RLS on with no member policy until PR2. '
  'Retention: 30 days, hard-deleted daily by purge_egress_audit_rollup (pg_cron '
  'egress-audit-rollup-retention); deleted with the workspace and on solo-account '
  'erasure via erase_egress_audit_rollup. Lawful basis: legitimate interest '
  '(Art. 6(1)(f)).';

-- ---------------------------------------------------------------------------
-- ingest_egress_audit_rollup(rows jsonb) -> jsonb counts
--
-- Batch upsert for the Vector sink. NEVER raises on row content: unknown, orphaned or
-- toggle-off workspaces and malformed or out-of-bounds rows are skipped and
-- counted, because raising would make the sink retry the same batch forever. A system fault
-- (lock, I/O, permission, schema drift) does raise, so it is retried and mirrored.
-- The toggle is read at ingest time (workspaces.web_egress), so buffered events
-- from before a toggle-off are dropped (errs toward minimization; ADR-288).
-- Merge is per column: GREATEST for request_count, bytes_out, last_seen and
-- LEAST for first_seen — never SUM (a journald-cursor replay must not overstate).
-- Distinct (host, decision) rows per workspace and bucket are capped; the overflow
-- folds into one '(other)' row so a flood of unique hosts cannot grow the table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ingest_egress_audit_rollup(p_rows jsonb)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  c_max_rows       CONSTANT int := 1000;
  c_max_host_rows  CONSTANT int := 500;
  c_retention      CONSTANT interval := interval '30 days';
  c_skew           CONSTANT interval := interval '30 minutes';
  v_el             jsonb;
  v_ws             uuid;
  v_bucket         timestamptz;
  v_host           text;
  v_decision       text;
  v_source         text;
  v_count          bigint;
  v_bytes          bigint;
  v_first          timestamptz;
  v_last           timestamptz;
  v_toggle         boolean;
  v_host_rows      int;
  v_accepted       int := 0;
  v_unknown        int := 0;
  v_off            int := 0;
  v_invalid        int := 0;
BEGIN
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RETURN jsonb_build_object('accepted', 0, 'skipped_unknown', 0,
                              'skipped_toggle_off', 0, 'skipped_invalid', 0);
  END IF;
  IF jsonb_array_length(p_rows) > c_max_rows THEN
    RETURN jsonb_build_object('accepted', 0, 'skipped_unknown', 0,
                              'skipped_toggle_off', 0,
                              'skipped_invalid', jsonb_array_length(p_rows));
  END IF;

  FOR v_el IN SELECT value FROM jsonb_array_elements(p_rows) LOOP
    BEGIN
      IF jsonb_typeof(v_el) <> 'object' THEN
        v_invalid := v_invalid + 1;
        CONTINUE;
      END IF;

      v_ws       := (v_el ->> 'workspace_id')::uuid;
      v_bucket   := (v_el ->> 'bucket_start')::timestamptz;
      v_host     := v_el ->> 'requested_host';
      v_decision := v_el ->> 'decision';
      v_source   := v_el ->> 'source_host';
      v_count    := (v_el ->> 'request_count')::bigint;
      v_bytes    := (v_el ->> 'bytes_out')::bigint;
      v_first    := (v_el ->> 'first_seen')::timestamptz;
      v_last     := (v_el ->> 'last_seen')::timestamptz;

      IF v_ws IS NULL OR v_bucket IS NULL OR v_host IS NULL OR v_decision IS NULL
         OR v_source IS NULL OR v_count IS NULL OR v_bytes IS NULL
         OR v_first IS NULL OR v_last IS NULL
         OR v_count < 0 OR v_bytes < 0
         OR char_length(v_host) NOT BETWEEN 1 AND 253
         OR char_length(v_decision) NOT BETWEEN 1 AND 32
         OR v_source !~ '^[a-z0-9][a-z0-9-]{0,62}$'
         OR v_bucket < now() - c_retention
         OR v_bucket > now() + c_skew THEN
        v_invalid := v_invalid + 1;
        CONTINUE;
      END IF;

      SELECT w.web_egress INTO v_toggle FROM public.workspaces w WHERE w.id = v_ws;
      IF NOT FOUND THEN
        v_unknown := v_unknown + 1;
        CONTINUE;
      END IF;
      -- A workspace with no member left is an orphan (account erasure keeps the workspace row,
      -- migration 065, but deletes its members first). Late buckets from Vector's reduce or disk
      -- buffer must not re-create rows that erase_egress_audit_rollup just removed.
      -- FOR SHARE takes a row lock on the member rows until this transaction commits: the saga's
      -- DELETE of the member row waits for the insert below, so erase (which runs after it) sees
      -- and removes this row; and if the delete committed first, no row is found here. Without the
      -- lock a delete + erase landing between this check and the insert would leave an orphan row.
      PERFORM 1 FROM public.workspace_members m WHERE m.workspace_id = v_ws FOR SHARE;
      IF NOT FOUND THEN
        v_unknown := v_unknown + 1;
        CONTINUE;
      END IF;
      IF v_toggle IS NOT TRUE THEN
        v_off := v_off + 1;
        CONTINUE;
      END IF;

      -- Cap distinct rows per workspace and bucket; fold the overflow.
      IF v_host <> '(other)'
         AND NOT EXISTS (
           SELECT 1 FROM public.workspace_egress_audit_rollup r
            WHERE r.workspace_id = v_ws AND r.bucket_start = v_bucket
              AND r.requested_host = v_host AND r.decision = v_decision
              AND r.source_host = v_source) THEN
        SELECT count(*)::int INTO v_host_rows
          FROM public.workspace_egress_audit_rollup r
         WHERE r.workspace_id = v_ws AND r.bucket_start = v_bucket;
        IF v_host_rows >= c_max_host_rows THEN
          v_host := '(other)';
        END IF;
      END IF;

      INSERT INTO public.workspace_egress_audit_rollup
        (workspace_id, bucket_start, requested_host, decision, source_host,
         request_count, bytes_out, first_seen, last_seen)
      VALUES
        (v_ws, v_bucket, v_host, v_decision, v_source, v_count, v_bytes, v_first, v_last)
      ON CONFLICT (workspace_id, bucket_start, requested_host, decision, source_host)
      DO UPDATE SET
        request_count = GREATEST(workspace_egress_audit_rollup.request_count, EXCLUDED.request_count),
        bytes_out     = GREATEST(workspace_egress_audit_rollup.bytes_out,     EXCLUDED.bytes_out),
        first_seen    = LEAST(workspace_egress_audit_rollup.first_seen,       EXCLUDED.first_seen),
        last_seen     = GREATEST(workspace_egress_audit_rollup.last_seen,     EXCLUDED.last_seen)
      -- A replay that changes nothing must not rewrite the tuple (WAL and dead tuples).
      WHERE workspace_egress_audit_rollup.request_count < EXCLUDED.request_count
         OR workspace_egress_audit_rollup.bytes_out     < EXCLUDED.bytes_out
         OR workspace_egress_audit_rollup.first_seen    > EXCLUDED.first_seen
         OR workspace_egress_audit_rollup.last_seen     < EXCLUDED.last_seen;
      v_accepted := v_accepted + 1;
    EXCEPTION WHEN data_exception OR integrity_constraint_violation THEN
      -- Bad CONTENT (a cast, range or CHECK failure) in one row must not lose the batch. Anything
      -- else (a lock, I/O or permission error, schema drift) is a SYSTEM fault: let it raise so the
      -- route answers 5xx, mirrors it and Vector retries, instead of counting it as invalid.
      v_invalid := v_invalid + 1;
    END;
  END LOOP;

  RETURN jsonb_build_object('accepted', v_accepted, 'skipped_unknown', v_unknown,
                            'skipped_toggle_off', v_off, 'skipped_invalid', v_invalid);
END;
$$;

REVOKE ALL ON FUNCTION public.ingest_egress_audit_rollup(jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ingest_egress_audit_rollup(jsonb) TO service_role;

COMMENT ON FUNCTION public.ingest_egress_audit_rollup(jsonb) IS
  '#9545: service-role batch upsert for the egress rollup. Skips and counts '
  'unknown/toggle-off workspaces and malformed rows; never raises on row content.';

-- ---------------------------------------------------------------------------
-- purge_egress_audit_rollup(retention) -> rows deleted
--
-- Bounded batched delete on last_seen. Refuses a retention shorter than a day so
-- a bad call cannot wipe the table. Scheduled daily below.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_egress_audit_rollup(
  p_retention interval DEFAULT interval '30 days',
  p_batch int DEFAULT 5000
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_total bigint := 0;
  v_n     bigint;
BEGIN
  IF p_retention IS NULL OR p_retention < interval '1 day' THEN
    RAISE EXCEPTION 'purge_egress_audit_rollup: retention must be at least 1 day';
  END IF;
  IF p_batch IS NULL OR p_batch < 1 THEN
    RAISE EXCEPTION 'purge_egress_audit_rollup: batch must be positive';
  END IF;
  LOOP
    DELETE FROM public.workspace_egress_audit_rollup
     WHERE ctid IN (
       SELECT ctid FROM public.workspace_egress_audit_rollup
        WHERE last_seen < now() - p_retention
        LIMIT p_batch);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    EXIT WHEN v_n = 0;
    v_total := v_total + v_n;
  END LOOP;
  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_egress_audit_rollup(interval, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_egress_audit_rollup(interval, int) TO service_role;

COMMENT ON FUNCTION public.purge_egress_audit_rollup(interval, int) IS
  '#9545: daily retention sweep (30 days on last_seen) for workspace_egress_audit_rollup.';

-- ---------------------------------------------------------------------------
-- erase_egress_audit_rollup(workspace) -> rows deleted
--
-- GDPR Art. 17 for the solo workspace (workspace id = the user's id). The
-- account-delete saga keeps the orphan workspace row (migration 065), so the
-- ON DELETE CASCADE does not fire on account erasure; the saga calls this
-- (step 5.15) before deleting the auth user. Idempotent. Does nothing while the
-- workspace still has a member (see below).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.erase_egress_audit_rollup(p_workspace uuid)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_n bigint := 0;
BEGIN
  IF p_workspace IS NULL THEN
    RETURN 0;
  END IF;
  -- Only an orphaned workspace is erased. The saga deletes the departing member's row first, so a
  -- solo workspace has no member left here; a workspace that gained members (or whose ownership
  -- moved, migration 075) keeps its history for the remaining members.
  IF EXISTS (SELECT 1 FROM public.workspace_members m WHERE m.workspace_id = p_workspace) THEN
    RETURN 0;
  END IF;
  DELETE FROM public.workspace_egress_audit_rollup WHERE workspace_id = p_workspace;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.erase_egress_audit_rollup(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erase_egress_audit_rollup(uuid) TO service_role;

COMMENT ON FUNCTION public.erase_egress_audit_rollup(uuid) IS
  '#9545: Art. 17 erasure of one workspace''s rollup rows; called by account-delete step 5.15.';

-- ---------------------------------------------------------------------------
-- erase_egress_audit_rollup_for_requester(workspace, requester) -> rows deleted
--
-- GDPR Art. 17 / Art. 15 follow-up for an explicit request made while the account stays open
-- (the requester is still the member, so erase_egress_audit_rollup would do nothing). Deletes
-- only when the requester is the SOLE member of the workspace; a team workspace's history belongs
-- to its remaining members. One audited path instead of raw SQL in a runbook. The request record
-- (DSAR ticket) holds the returned count; there is no audit table for this in PR1.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.erase_egress_audit_rollup_for_requester(
  p_workspace uuid,
  p_requester uuid
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_n bigint := 0;
BEGIN
  IF p_workspace IS NULL OR p_requester IS NULL THEN
    RETURN 0;
  END IF;
  -- Lock the member rows so the "sole member" fact holds until the delete commits.
  PERFORM 1 FROM public.workspace_members m WHERE m.workspace_id = p_workspace FOR SHARE;
  IF (SELECT count(*) FROM public.workspace_members m WHERE m.workspace_id = p_workspace) <> 1
     OR NOT EXISTS (
       SELECT 1 FROM public.workspace_members m
        WHERE m.workspace_id = p_workspace AND m.user_id = p_requester) THEN
    RETURN 0;
  END IF;
  DELETE FROM public.workspace_egress_audit_rollup WHERE workspace_id = p_workspace;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.erase_egress_audit_rollup_for_requester(uuid, uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.erase_egress_audit_rollup_for_requester(uuid, uuid) TO service_role;

COMMENT ON FUNCTION public.erase_egress_audit_rollup_for_requester(uuid, uuid) IS
  '#9545: erases one workspace''s rollup rows on an explicit data-subject request, only when the requester is the sole member.';

-- Daily retention sweep. A prior apply of the same job is not an error.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'egress-audit-rollup-retention') THEN
    PERFORM cron.unschedule('egress-audit-rollup-retention');
  END IF;
  PERFORM cron.schedule(
    'egress-audit-rollup-retention',
    '30 4 * * *',
    $cron$ SELECT public.purge_egress_audit_rollup(interval '30 days'); $cron$
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
