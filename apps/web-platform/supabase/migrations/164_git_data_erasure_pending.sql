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
-- LAWFUL_BASIS: legal obligation, Art. 6(1)(c) (completing the Art. 17 erasure the subject requested),
-- as ruled by the CLO on 2026-10-23, who also required the non-identifying counter below and ruled
-- that no tombstone is left. The FINAL CLO re-ruling is dated 2026-10-24 (#9066); the disclosure
-- update (DPD 10.3, privacy policy, GDPR policy, Art. 30 register) must land before the write path
-- (PR-B2) is merged or enabled. Nothing here edits any legal document.
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
--       (which can carry paths or ids) can never be stored. The words are the non-terminal
--       GitDataErasureOutcome statuses (refused, unreachable, unauthorized, unconfigured,
--       host_key_mismatch) plus two deliberate extras: `threw` (account-delete's thrown arm, the
--       same spelling as its erasure_outcome tag) and `seeded` (a row written by the re-drive's
--       manual seed path, which has no host outcome yet; nothing else emits it).
--     * A stuck row is NEVER purged on a timer. Escalation is by alerting (PR-B2), not deletion.
--   git_data_erasure_counts   non-identifying monthly counter of confirmed erasures by how long
--     they took. No id, no per-event timestamp. Written in the SAME statement as the ledger
--     delete (resolve_git_data_erasure_pending), so requested_at is not retained after success
--     and no tombstone is left.
--
-- Deleted ledger rows may persist in Supabase backups (unmeasured).
--
-- record-after-resolve on the same id inserts a FRESH row and so restarts requested_at at now()
-- (the resolved row, and its clock, are gone by design). A caller re-recording an id whose request
-- is older than that (the PR-B2 seed path, for ids swept from Sentry) must pass p_requested_at so
-- the Art. 12(3) clock is not reset to age 0.
--
-- git_data_erasure_owner_gone(workspace) is the re-drive's proof that an account is really gone
-- before it erases anything: the ledger alone is NOT proof (a seeded wrong id, or a deletion that
-- aborts after the ledger write at account-delete step 3.01, would otherwise get a LIVE user's
-- repository erased). It returns TRUE only when ALL of these hold:
--   1. no auth.users row with id = the id       (the account row; deleted last, step 6)
--   2. no public.users row with id = the id     (cascade child of auth.users, mig 001)
--   3. the id is not a TEAM workspace, decided by PROVENANCE of the ledger row, because the schema
--      cannot decide it: every workspaces row has a NOT NULL organization_id, and when a solo owner
--      is deleted anonymise_organization_membership PROMOTES the oldest remaining member to owner
--      (mig 058/065), so an ex-solo workspace that kept a co-member is structurally identical to a
--      team workspace (workspaces.id is the deleted user's id; its organization has a live owner).
--        - a ledger row whose last_outcome is NOT 'seeded' was written by account-delete for that
--          very user id (the only other writer is the manual seed path), so it IS a deleted account's
--          solo workspace id: TRUE once rows 1 and 2 are gone, even though the co-member's
--          workspace_members row remains (otherwise the erasure would be stuck forever);
--        - a 'seeded' row, or an id with no ledger row yet (the seed path asks BEFORE recording),
--          is operator input: TRUE only if no workspace_members row still keys on that workspace id,
--          so a seeded TEAM workspace id (members, zero user rows) stays FALSE.
--      Known limit: a seeded ex-solo id whose workspace kept a co-member also stays FALSE; it is
--      reported as owner_still_exists and needs an operator decision.
-- It deliberately does NOT require public.workspaces / public.organizations rows to be absent: the
-- saga keeps the orphan workspace and organization rows (mig 065 Part 1, "record-of-existence").

DO $$
BEGIN
  IF to_regclass('auth.users') IS NULL
     OR to_regclass('public.users') IS NULL
     OR to_regclass('public.workspace_members') IS NULL THEN
    RAISE EXCEPTION 'Migration 164 precondition failed: auth.users, public.users and public.workspace_members must exist (git_data_erasure_owner_gone reads them).';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.git_data_erasure_pending (
  workspace_id    uuid        PRIMARY KEY,
  requested_at    timestamptz NOT NULL DEFAULT now(),
  attempts        int         NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  last_attempt_at timestamptz,
  last_outcome    text        CHECK (last_outcome IN (
    'refused', 'unreachable', 'unauthorized', 'unconfigured', 'host_key_mismatch', 'threw', 'seeded'))
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
-- record_git_data_erasure_pending(workspace, outcome, requested_at)
-- Idempotent upsert. A NULL outcome is refused (no NULL row, and a known last_outcome is never
-- overwritten with NULL). p_requested_at is for the seed path only: it lets an id swept from
-- Sentry keep its ORIGINAL request time; a future value and one before 2020-01-01 are refused.
-- On conflict the EARLIER requested_at wins (the original is kept; a seed may only move the clock
-- earlier, never reset it to now), a 'seeded' write never overwrites an existing row's known
-- last_outcome (the seed path has no host outcome of its own), and attempts / last_attempt_at are
-- untouched.
--
-- The 2-argument form existed in an earlier edit of this migration: drop it first so a database
-- that ever applied that edit does not keep an ambiguous overload with the old grants.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.record_git_data_erasure_pending(uuid, text);

CREATE OR REPLACE FUNCTION public.record_git_data_erasure_pending(
  p_workspace_id uuid,
  p_outcome      text,
  p_requested_at timestamptz DEFAULT NULL
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
  IF p_outcome IS NULL THEN
    RAISE EXCEPTION 'record_git_data_erasure_pending: outcome is required';
  END IF;
  IF p_requested_at IS NOT NULL AND p_requested_at > now() THEN
    RAISE EXCEPTION 'record_git_data_erasure_pending: requested_at must not be in the future';
  END IF;
  IF p_requested_at IS NOT NULL AND p_requested_at < timestamptz '2020-01-01 00:00:00+00' THEN
    RAISE EXCEPTION 'record_git_data_erasure_pending: requested_at must not be before 2020-01-01';
  END IF;
  INSERT INTO public.git_data_erasure_pending AS g (workspace_id, last_outcome, requested_at)
  VALUES (p_workspace_id, p_outcome, COALESCE(p_requested_at, now()))
  ON CONFLICT (workspace_id) DO UPDATE
    SET last_outcome = CASE WHEN EXCLUDED.last_outcome = 'seeded' THEN g.last_outcome ELSE EXCLUDED.last_outcome END,
        requested_at = LEAST(g.requested_at, EXCLUDED.requested_at);
END;
$$;

REVOKE ALL ON FUNCTION public.record_git_data_erasure_pending(uuid, text, timestamptz)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_git_data_erasure_pending(uuid, text, timestamptz) TO service_role;

COMMENT ON FUNCTION public.record_git_data_erasure_pending(uuid, text, timestamptz) IS
  '#8211: service-role idempotent upsert into git_data_erasure_pending. Refuses NULL outcome and a '
  'requested_at in the future or before 2020; keeps the earlier requested_at on conflict; updates '
  'last_outcome (closed enum, CHECK-enforced) except that a seeded write keeps a known outcome.';

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
  ), stamped AS (
    UPDATE public.git_data_erasure_pending g
       SET last_attempt_at = now(),
           attempts        = g.attempts + 1
      FROM picked
     WHERE g.workspace_id = picked.workspace_id
    RETURNING g.workspace_id, g.requested_at, g.attempts, g.last_outcome
  )
  -- UPDATE ... RETURNING has no defined order; hand the rows back oldest request first.
  SELECT s.workspace_id, s.requested_at, s.attempts, s.last_outcome
    FROM stamped s
   ORDER BY s.requested_at, s.workspace_id;
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
    SELECT date_trunc('month', now() AT TIME ZONE 'UTC')::date, b.bucket, 1 FROM b
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
-- oldest_git_data_erasure_pending_age() -> seconds (never negative), NULL when the ledger is empty
-- (GREATEST ignores NULL, so the empty case needs its own branch). For the gauge.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.oldest_git_data_erasure_pending_age()
  RETURNS bigint
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN count(*) = 0 THEN NULL
              ELSE GREATEST(0, floor(extract(epoch FROM (now() - min(requested_at)))))::bigint
         END
    FROM public.git_data_erasure_pending;
$$;

REVOKE ALL ON FUNCTION public.oldest_git_data_erasure_pending_age()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.oldest_git_data_erasure_pending_age() TO service_role;

COMMENT ON FUNCTION public.oldest_git_data_erasure_pending_age() IS
  '#8211: service-role age in seconds of the oldest pending git-data erasure (NULL when none).';

-- ---------------------------------------------------------------------------
-- git_data_erasure_owner_gone(workspace) -> true only when the account is really gone.
-- See the header for exactly what is checked and why workspaces/organizations are not.
-- A NULL id raises (the caller must treat an error as "not gone", never as gone).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.git_data_erasure_owner_gone(p_workspace_id uuid)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_outcome text;
BEGIN
  IF p_workspace_id IS NULL THEN
    RAISE EXCEPTION 'git_data_erasure_owner_gone: workspace id is required';
  END IF;
  IF EXISTS (SELECT 1 FROM auth.users u WHERE u.id = p_workspace_id)
     OR EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = p_workspace_id) THEN
    RETURN false;
  END IF;
  SELECT g.last_outcome INTO v_outcome
    FROM public.git_data_erasure_pending g
   WHERE g.workspace_id = p_workspace_id;
  IF FOUND AND v_outcome <> 'seeded' THEN
    RETURN true; -- written by account-delete for this very user id: a deleted account's solo workspace
  END IF;
  RETURN NOT EXISTS (SELECT 1 FROM public.workspace_members m WHERE m.workspace_id = p_workspace_id);
END;
$$;

REVOKE ALL ON FUNCTION public.git_data_erasure_owner_gone(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.git_data_erasure_owner_gone(uuid) TO service_role;

COMMENT ON FUNCTION public.git_data_erasure_owner_gone(uuid) IS
  '#8211: service-role proof that an account is gone: no auth.users / public.users row, and the id is '
  'not a team workspace (ledger provenance: an account-delete row is trusted, a seeded or unrecorded '
  'id must have no workspace_members left). Does not read workspaces / organizations (kept as orphans, '
  'mig 065).';

-- ---------------------------------------------------------------------------
-- git_data_erasure_pending_ages() -> (oldest_gone_seconds, oldest_live_seconds)
-- The re-drive's gauge and escalation must consider ONLY rows whose owner is gone: a row whose owner
-- still exists is an aborted deletion (or a wrong seeded id) that must NOT be erased, so it must not
-- page anyone to "erase by hand". Split by git_data_erasure_owner_gone; each side is NULL when empty,
-- never negative.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.git_data_erasure_pending_ages()
  RETURNS TABLE (oldest_gone_seconds bigint, oldest_live_seconds bigint)
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  SELECT
    max(CASE WHEN public.git_data_erasure_owner_gone(g.workspace_id)
             THEN GREATEST(0, floor(extract(epoch FROM (now() - g.requested_at))))::bigint END),
    max(CASE WHEN NOT public.git_data_erasure_owner_gone(g.workspace_id)
             THEN GREATEST(0, floor(extract(epoch FROM (now() - g.requested_at))))::bigint END)
    FROM public.git_data_erasure_pending g;
$$;

REVOKE ALL ON FUNCTION public.git_data_erasure_pending_ages()
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.git_data_erasure_pending_ages() TO service_role;

COMMENT ON FUNCTION public.git_data_erasure_pending_ages() IS
  '#8211: service-role oldest pending age in seconds, split into rows whose owner is gone (erasable, '
  'escalates) and rows whose owner still exists (aborted deletion; never erased, warns separately).';
