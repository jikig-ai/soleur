-- 164_git_data_erasure_pending.sql
-- #8211 (PR-B1) — durable pending-erasure ledger for the git-data bare-repo store.
--
-- Why: account deletion calls removeGitDataRepo (server/git-data-replication.ts). Any outcome
-- other than `erased`/`skipped` means the user's bare repo is still on the git-data host, yet
-- today that exists only as a Sentry event and the re-drive is manual. The LUKS cutover runbook
-- (git-data-luks-cutover-5274.md) lists "the per-id re-erasure path for a populated store" as a
-- hard precondition of the real flip. This migration ships the ledger and its RPCs; the account-
-- delete write path and the Inngest re-drive cron land in PR-B2 (this PR is inert on its own).
--
-- LAWFUL_BASIS: pending CLO ruling (re-ruling dated 2026-10-24); the disclosure update (DPD 10.3,
-- privacy policy, GDPR policy, Art. 30 register) must land before the write path is merged.
--
-- Two tables, both service-role-only through SECURITY DEFINER RPCs (RLS on, NO policy, every
-- table privilege revoked from PUBLIC/anon/authenticated/service_role):
--
--   git_data_erasure_pending  one row per workspace id whose repo is not yet confirmed erased.
--     * workspace_id is the ONLY identifier (it equals the id gitDataRepoId already sends to
--       Sentry). No email, name or user_id column.
--     * NO foreign key to auth.users or workspaces: the user row and the workspace are deleted
--       seconds later in the same cascade and the ledger row must outlive both.
--     * requested_at is the Art. 12(3) clock (request time). record_* keeps the ORIGINAL value.
--     * last_outcome is a closed enum (CHECK), never free text, so a host-supplied stderr string
--       (which can carry paths or ids) can never be stored.
--     * A stuck row is NEVER purged on a timer. Escalation is by alerting (PR-B2), not deletion.
--   git_data_erasure_counts   non-identifying monthly counter of confirmed erasures by how long
--     they took. No id, no per-event timestamp. Written in the SAME statement as the ledger
--     delete (resolve_git_data_erasure_pending), so requested_at is not retained after success
--     and no tombstone is left.
--
-- Deleted ledger rows may persist in Supabase backups (unmeasured).
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp every SECURITY DEFINER function pins
-- `public, pg_temp`. No CREATE INDEX CONCURRENTLY (the migration runs inside a transaction).

CREATE TABLE IF NOT EXISTS public.git_data_erasure_pending (
  workspace_id    uuid        PRIMARY KEY,
  requested_at    timestamptz NOT NULL DEFAULT now(),
  attempts        int         NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_attempt_at timestamptz,
  last_outcome    text        CHECK (last_outcome IN (
    'refused', 'unreachable', 'unauthorized', 'unconfigured', 'host_key_mismatch', 'thrown', 'seeded'))
);

-- The claim query filters on last_attempt_at and orders by requested_at.
CREATE INDEX IF NOT EXISTS git_data_erasure_pending_requested_at_idx
  ON public.git_data_erasure_pending (requested_at);

CREATE TABLE IF NOT EXISTS public.git_data_erasure_counts (
  month  date   NOT NULL CHECK (extract(day FROM month) = 1),
  bucket text   NOT NULL CHECK (bucket IN ('lt_1h', 'lt_24h', 'lt_7d', 'lt_20d', 'ge_20d')),
  count  bigint NOT NULL DEFAULT 0 CHECK (count >= 0),
  PRIMARY KEY (month, bucket)
);

ALTER TABLE public.git_data_erasure_pending ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.git_data_erasure_counts  ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.git_data_erasure_pending FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.git_data_erasure_counts  FROM PUBLIC, anon, authenticated, service_role;

COMMENT ON TABLE public.git_data_erasure_pending IS
  '#8211: durable ledger of workspace ids whose git-data bare repo is not yet confirmed erased '
  '(account-delete outcome other than erased/skipped). Only identifier is workspace_id; no FK. '
  'RLS on, no policy; written only by record/claim/resolve_git_data_erasure_pending. Rows are '
  'deleted on confirmed erasure and are never purged on a timer.';
COMMENT ON TABLE public.git_data_erasure_counts IS
  '#8211: non-identifying monthly count of confirmed git-data erasures by elapsed-time bucket. '
  'No id, no per-event timestamp. Incremented in the same statement that deletes the ledger row.';

-- ---------------------------------------------------------------------------
-- record_git_data_erasure_pending(workspace, outcome)
-- Idempotent upsert. The ORIGINAL requested_at is kept on conflict; only last_outcome moves.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_git_data_erasure_pending(
  p_workspace_id uuid,
  p_outcome      text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'record_git_data_erasure_pending: workspace id is required';
  END IF;
  INSERT INTO public.git_data_erasure_pending AS g (workspace_id, last_outcome)
  VALUES (p_workspace_id, p_outcome)
  ON CONFLICT (workspace_id) DO UPDATE
    SET last_outcome = EXCLUDED.last_outcome;
END;
$$;

REVOKE ALL ON FUNCTION public.record_git_data_erasure_pending(uuid, text)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_git_data_erasure_pending(uuid, text) TO service_role;

COMMENT ON FUNCTION public.record_git_data_erasure_pending(uuid, text) IS
  '#8211: service-role idempotent upsert into git_data_erasure_pending; keeps the original '
  'requested_at, updates last_outcome (closed enum, CHECK-enforced).';

-- ---------------------------------------------------------------------------
-- claim_git_data_erasure_pending(limit, min_interval)
-- Hands out at most p_limit rows whose last attempt is absent or older than p_min_interval,
-- oldest request first, and stamps last_attempt_at + attempts + 1 in the SAME statement.
-- FOR UPDATE SKIP LOCKED keeps two concurrent runs from taking the same row; the stamp keeps a
-- later run from re-taking it inside the backoff window (hence the 1-minute floor on the interval).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_git_data_erasure_pending(
  p_limit        int,
  p_min_interval interval
)
  RETURNS TABLE (workspace_id uuid, requested_at timestamptz, attempts int, last_outcome text)
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100 THEN
    RAISE EXCEPTION 'claim_git_data_erasure_pending: limit must be between 1 and 100';
  END IF;
  IF p_min_interval IS NULL OR p_min_interval < interval '1 minute' THEN
    RAISE EXCEPTION 'claim_git_data_erasure_pending: min interval must be at least 1 minute';
  END IF;
  RETURN QUERY
  WITH picked AS (
    SELECT p.workspace_id
      FROM public.git_data_erasure_pending p
     WHERE p.last_attempt_at IS NULL
        OR p.last_attempt_at < now() - p_min_interval
     ORDER BY p.requested_at, p.workspace_id
     LIMIT p_limit
       FOR UPDATE SKIP LOCKED
  )
  UPDATE public.git_data_erasure_pending g
     SET last_attempt_at = now(),
         attempts        = g.attempts + 1
    FROM picked
   WHERE g.workspace_id = picked.workspace_id
  RETURNING g.workspace_id, g.requested_at, g.attempts, g.last_outcome;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_git_data_erasure_pending(int, interval)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_git_data_erasure_pending(int, interval) TO service_role;

COMMENT ON FUNCTION public.claim_git_data_erasure_pending(int, interval) IS
  '#8211: service-role claim of at most p_limit due ledger rows (FOR UPDATE SKIP LOCKED), '
  'stamping last_attempt_at and attempts + 1 in the same statement.';

-- ---------------------------------------------------------------------------
-- resolve_git_data_erasure_pending(workspace) -> elapsed bucket, or NULL when no row existed
-- One statement: delete the row, bucket (now - requested_at), bump the non-identifying counter.
-- requested_at is not retained and no tombstone is left.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_git_data_erasure_pending(p_workspace_id uuid)
  RETURNS text
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_bucket text;
BEGIN
  WITH d AS (
    DELETE FROM public.git_data_erasure_pending
     WHERE workspace_id = p_workspace_id
    RETURNING requested_at
  ), b AS (
    SELECT CASE
             WHEN now() - d.requested_at < interval '1 hour'  THEN 'lt_1h'
             WHEN now() - d.requested_at < interval '24 hours' THEN 'lt_24h'
             WHEN now() - d.requested_at < interval '7 days'  THEN 'lt_7d'
             WHEN now() - d.requested_at < interval '20 days' THEN 'lt_20d'
             ELSE 'ge_20d'
           END AS bucket
      FROM d
  ), c AS (
    INSERT INTO public.git_data_erasure_counts AS k (month, bucket, count)
    SELECT date_trunc('month', now())::date, b.bucket, 1 FROM b
    ON CONFLICT (month, bucket) DO UPDATE SET count = k.count + 1
  )
  SELECT b.bucket INTO v_bucket FROM b;
  RETURN v_bucket;
END;
$$;

REVOKE ALL ON FUNCTION public.resolve_git_data_erasure_pending(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.resolve_git_data_erasure_pending(uuid) TO service_role;

COMMENT ON FUNCTION public.resolve_git_data_erasure_pending(uuid) IS
  '#8211: service-role resolve of a confirmed erasure. Deletes the ledger row and increments '
  'git_data_erasure_counts in one statement; returns the elapsed bucket or NULL when absent.';

-- ---------------------------------------------------------------------------
-- oldest_git_data_erasure_pending_age() -> seconds, NULL when the ledger is empty (for the gauge).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.oldest_git_data_erasure_pending_age()
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT floor(extract(epoch FROM (now() - min(requested_at))))::bigint
    FROM public.git_data_erasure_pending;
$$;

REVOKE ALL ON FUNCTION public.oldest_git_data_erasure_pending_age()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.oldest_git_data_erasure_pending_age() TO service_role;

COMMENT ON FUNCTION public.oldest_git_data_erasure_pending_age() IS
  '#8211: service-role age in seconds of the oldest pending git-data erasure (NULL when none).';
