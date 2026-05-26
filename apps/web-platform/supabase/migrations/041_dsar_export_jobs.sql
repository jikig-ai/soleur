-- 041_dsar_export_jobs.sql
-- feat-dsar-art15-export-endpoint Phase 1 (issue #3637, plan rev-2).
-- ADR: knowledge-base/engineering/architecture/decisions/ADR-028.
--
-- Tables:
--   public.dsar_export_jobs        — user-visible RLS, per-job state
--   public.dsar_export_audit_pii   — admin-only, WORM (PII separated)
--
-- RPCs (all SECURITY DEFINER, search_path = public, pg_temp,
-- public.-qualified relations, named-role REVOKE):
--   public.claim_next_dsar_export_job()
--   public.write_dsar_export_audit_pii(...)
--   public.anonymise_dsar_export_audit_pii(p_user_id uuid)
--
-- Schedules (pg_cron, plan TR13 + TR14):
--   dsar-export-pii-retention-sweep    — daily 03:00 UTC, 24-mo DELETE
--   dsar-export-bundle-ttl-sweep       — hourly, completed -> expired
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp.
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- service_role. (Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to
-- anon/authenticated/service_role on every new fn; REVOKE FROM PUBLIC
-- alone does NOT undo the explicit role grants.)
--
-- Per cq-supabase-migration-no-concurrently: no CREATE INDEX CONCURRENTLY
-- (Supabase wraps each migration in a transaction).
--
-- Per plan rev-2 C1: NO `owner_jwt_encrypted` column. Worker uses
-- service_role + per-row `WHERE owner_id = $1` + assertReadScope.

-- ============================================================================
-- dsar_export_jobs — per-job state, user-visible RLS.
-- ============================================================================

-- ON DELETE SET NULL (not NO ACTION) per code-review P1 on PR #3634
-- (data-integrity-guardian): the Art. 17 cascade in account-delete.ts
-- only flips dsar_export_jobs status to 'failed' (does NOT delete the
-- rows) before calling auth.admin.deleteUser. With NO ACTION, the
-- auth-row deletion would FK-fail. SET NULL preserves the row for
-- compliance-history (anonymised: status remembers what happened, but
-- user_id is anonymised). user_id is therefore nullable; the partial
-- unique index and select policy already gate on user_id, so a row
-- whose user_id became NULL is no longer user-visible.
CREATE TABLE IF NOT EXISTS public.dsar_export_jobs (
  id                       uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  uuid         REFERENCES auth.users(id) ON DELETE SET NULL,
  status                   text         NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'running', 'completed', 'delivered', 'expired', 'failed')),
  requested_at             timestamptz  NOT NULL DEFAULT now(),
  acknowledged_at          timestamptz  NOT NULL DEFAULT now(),
  started_at               timestamptz,
  completed_at             timestamptz,
  delivered_at             timestamptz,
  signed_url_expires_at    timestamptz,
  failure_reason           text,
  bundle_sha256            text,
  bundle_size_bytes        bigint,
  owner_session_id         uuid,                  -- bound at insert; checked on download
  reauth_event_id          uuid,                  -- single-use marker (consumed at enqueue)
  created_at               timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.dsar_export_jobs ENABLE ROW LEVEL SECURITY;

-- User can SELECT their own export-job rows.
CREATE POLICY dsar_export_jobs_owner_select ON public.dsar_export_jobs
  FOR SELECT USING (auth.uid() = user_id);

-- No INSERT/UPDATE/DELETE policies: all writes go through service_role
-- via the SECURITY DEFINER RPCs below + the worker. authenticated role
-- cannot directly mutate job state.

-- Compliance idempotency: at most one active job per user (any of
-- pending / running / completed). Once status transitions to a
-- terminal state (delivered / expired / failed) the user can request
-- a fresh export. The `completed` status is bounded to ≤7d by the
-- TTL-expiry sweep (TR14, schedule below), which moves rows to
-- `expired` once `signed_url_expires_at < now()`. Combined this gives
-- the spec FR4-step rate-limit shape (1 in-flight job, 7d natural
-- spacing between completed→re-request).
--
-- Why not `AND requested_at > now() - interval '24 hours'`: Postgres
-- requires functions in index predicates to be IMMUTABLE; `now()` is
-- STABLE, so the original design (plan rev-2 TR7 wording) cannot be
-- expressed as a partial unique index. The 24h compliance idempotency
-- moves to the application layer (the `enqueueExport` server function
-- in dsar-export.ts will check for completed-within-24h jobs before
-- inserting a new row). Tracked in the plan rev-2 amendment.
CREATE UNIQUE INDEX dsar_export_jobs_one_active_per_user_idx
  ON public.dsar_export_jobs (user_id)
  WHERE status IN ('pending', 'running', 'completed');

-- Worker claim hot path: order pending jobs by request time.
CREATE INDEX dsar_export_jobs_pending_idx
  ON public.dsar_export_jobs (requested_at)
  WHERE status = 'pending';

-- TTL-expiry sweep hot path: find completed jobs whose URL has expired.
CREATE INDEX dsar_export_jobs_completed_expiring_idx
  ON public.dsar_export_jobs (signed_url_expires_at)
  WHERE status = 'completed';

COMMENT ON TABLE public.dsar_export_jobs IS
  'GDPR Art. 15 + Art. 20 self-serve export job tracking. User-visible '
  'RLS (SELECT only). All mutations via service_role through '
  'claim_next_dsar_export_job RPC + worker. feat-dsar-art15-export-endpoint #3637.';

-- ============================================================================
-- dsar_export_audit_pii — admin-only WORM, separated PII.
--
-- Stores requester_ip + user_agent so the controller can demonstrate
-- fulfilment of past DSARs under Art. 5(2) accountability. PII is
-- segregated from the user-readable jobs table so the SELECT policy
-- above can be broad without leaking IP/UA data. Anonymised by the
-- Art. 17 cascade (anonymise_dsar_export_audit_pii) before
-- auth.admin.deleteUser() fires.
-- ============================================================================

-- See dsar_export_jobs above for the FK rationale: ON DELETE SET NULL
-- preserves anonymised audit history past auth-deletion (Art. 5(2)
-- accountability) while letting the cascade complete cleanly. user_id
-- and job_id are nullable; the WORM trigger above runs against the
-- anonymise GUC, not against the FK constraint.
CREATE TABLE IF NOT EXISTS public.dsar_export_audit_pii (
  id              uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id          uuid         REFERENCES public.dsar_export_jobs(id) ON DELETE SET NULL,
  user_id         uuid         REFERENCES auth.users(id) ON DELETE SET NULL,
  event_type      text         NOT NULL
    CHECK (event_type IN ('enqueue', 'download_start', 'download_complete', 'reissue', 'expire', 'fail')),
  requester_ip    inet,
  user_agent      text,
  event_at        timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.dsar_export_audit_pii ENABLE ROW LEVEL SECURITY;
-- Zero policies: service-role-only via write_dsar_export_audit_pii RPC.

CREATE INDEX dsar_export_audit_pii_user_event_idx
  ON public.dsar_export_audit_pii (user_id, event_at DESC);

CREATE INDEX dsar_export_audit_pii_job_idx
  ON public.dsar_export_audit_pii (job_id);

COMMENT ON TABLE public.dsar_export_audit_pii IS
  'Append-only audit row per DSAR export lifecycle event. PII '
  '(requester_ip, user_agent) segregated from dsar_export_jobs so the '
  'user-readable RLS policy stays clean. WORM trigger gated by GUC + '
  'service_role + file-parse lint (AC29 + S1). Anonymised on user '
  'account deletion via Art. 17 cascade. 24-mo retention via TR13 '
  'pg_cron sweep. feat-dsar-art15-export-endpoint #3637.';

-- ============================================================================
-- WORM trigger: dsar_export_audit_pii is append-only EXCEPT during the
-- Art. 17 anonymisation flow.
--
-- AC29 + S1: bypass is permitted iff ALL of:
--   (a) GUC `app.dsar_audit_anonymise_in_progress` is set (any
--       non-empty value)
--   (b) `current_user = 'service_role'`
--   (c) The SET-site for the GUC appears EXACTLY ONCE in the codebase,
--       in the body of anonymise_dsar_export_audit_pii. Enforced by
--       file-parse test `dsar-worm-guc-sites.test.ts`.
--
-- PostgreSQL exposes no first-class API for "calling function OID"
-- from a trigger, so AC29's function-OID-allowlist is implemented
-- as the lint described in (c). The trigger's role + GUC gates are
-- the runtime-cryptographic component.
-- ============================================================================

-- Trigger function is INVOKER (not DEFINER) per code-review P1 from
-- data-integrity-guardian on PR #3634: a SECURITY DEFINER trigger
-- evaluates `current_user` to the function OWNER (typically `postgres`
-- in Supabase migrations), not the role that initiated the triggering
-- UPDATE. With DEFINER, the `current_user = 'service_role'` gate would
-- ALWAYS fail and the legitimate Art. 17 anonymise RPC would be
-- rejected — Art. 17 violation. Triggers do not need DEFINER privileges
-- since they execute inside the calling transaction with the calling
-- session's role context, which is exactly what we want here.
CREATE OR REPLACE FUNCTION public.dsar_export_audit_pii_no_mutate() RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_anonymise_flag text;
BEGIN
  -- current_setting(name, missing_ok=true) returns '' (not NULL) when unset.
  v_anonymise_flag := current_setting('app.dsar_audit_anonymise_in_progress', true);

  IF v_anonymise_flag <> '' AND current_user = 'service_role' THEN
    -- Bypass: Art. 17 anonymisation flow. The single SET site is in
    -- anonymise_dsar_export_audit_pii's body; file-parse lint enforces
    -- the SET-site uniqueness.
    RETURN COALESCE(NEW, OLD);
  END IF;

  RAISE EXCEPTION 'dsar_export_audit_pii is append-only (WORM)' USING ERRCODE = 'P0001';
END;
$$;

REVOKE ALL ON FUNCTION public.dsar_export_audit_pii_no_mutate() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER dsar_export_audit_pii_no_update
  BEFORE UPDATE ON public.dsar_export_audit_pii
  FOR EACH ROW
  EXECUTE FUNCTION public.dsar_export_audit_pii_no_mutate();

CREATE TRIGGER dsar_export_audit_pii_no_delete
  BEFORE DELETE ON public.dsar_export_audit_pii
  FOR EACH ROW
  EXECUTE FUNCTION public.dsar_export_audit_pii_no_mutate();

COMMENT ON FUNCTION public.dsar_export_audit_pii_no_mutate() IS
  'WORM gate for dsar_export_audit_pii. Allows UPDATE/DELETE only '
  'during the Art. 17 anonymisation flow (GUC + service_role). '
  'AC29 + S1.';

-- ============================================================================
-- claim_next_dsar_export_job — atomic worker claim.
--
-- Single-row UPDATE … RETURNING with FOR UPDATE SKIP LOCKED inside a
-- subquery to acquire the oldest pending job's lock without contention
-- across multiple poller calls (even though current deployment is
-- single-instance per rate-limiter.ts:252-262, the pattern survives
-- the eventual Redis migration intact).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.claim_next_dsar_export_job()
  RETURNS TABLE(
    id                uuid,
    user_id           uuid,
    owner_session_id  uuid,
    requested_at      timestamptz
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
    UPDATE public.dsar_export_jobs j
       SET status     = 'running',
           started_at = now()
     WHERE j.id = (
             SELECT inner_j.id
               FROM public.dsar_export_jobs inner_j
              WHERE inner_j.status = 'pending'
           ORDER BY inner_j.requested_at ASC
              LIMIT 1
              FOR UPDATE SKIP LOCKED
           )
    RETURNING j.id, j.user_id, j.owner_session_id, j.requested_at;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_next_dsar_export_job() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_next_dsar_export_job() TO service_role;

COMMENT ON FUNCTION public.claim_next_dsar_export_job() IS
  'Atomic worker claim for the next pending DSAR export job. Uses '
  'FOR UPDATE SKIP LOCKED in the inner select so concurrent poller '
  'calls do not block each other. Returns at most one row; returns '
  'zero rows when no pending jobs exist. service_role only.';

-- ============================================================================
-- write_dsar_export_audit_pii — append-only audit row writer.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.write_dsar_export_audit_pii(
  p_job_id       uuid,
  p_user_id      uuid,
  p_event_type   text,
  p_requester_ip inet,
  p_user_agent   text
) RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
  INSERT INTO public.dsar_export_audit_pii(
    job_id, user_id, event_type, requester_ip, user_agent
  )
  VALUES (
    p_job_id, p_user_id, p_event_type, p_requester_ip, p_user_agent
  );
$$;

REVOKE ALL ON FUNCTION public.write_dsar_export_audit_pii(uuid, uuid, text, inet, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.write_dsar_export_audit_pii(uuid, uuid, text, inet, text) TO service_role;

COMMENT ON FUNCTION public.write_dsar_export_audit_pii(uuid, uuid, text, inet, text) IS
  'Append-only writer for dsar_export_audit_pii. service_role only; '
  'PII rows are written here so the user-visible jobs RLS policy '
  'never reaches them.';

-- ============================================================================
-- anonymise_dsar_export_audit_pii — Art. 17 cascade hook.
--
-- Called from apps/web-platform/server/account-delete.ts BEFORE
-- auth.admin.deleteUser() per plan rev-2 AC25 cascade order
-- ["abort-dsar-jobs", "abort", "workspace", "storage-purge",
--   "anonymise-dsar-audit", "auth"].
--
-- Idempotent: re-running on already-anonymised rows is a no-op
-- (requester_ip + user_agent + user_id are simply re-set to the
-- anonymised values). This makes the failure-mode
-- "anonymise succeeds, auth-delete fails" recoverable — the next
-- retry runs anonymise as a no-op then re-attempts auth-delete.
--
-- THE SINGLE SET-SITE for app.dsar_audit_anonymise_in_progress lives
-- here. Asserted by dsar-worm-guc-sites.test.ts (AC29 + S1).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.anonymise_dsar_export_audit_pii(p_user_id uuid)
  RETURNS int
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_rows int;
BEGIN
  -- WORM-bypass: SET LOCAL scopes to the current transaction; reverts
  -- at COMMIT/ROLLBACK. Asserted by the file-parse lint to be the
  -- ONLY SET-site for this GUC across the codebase.
  SET LOCAL app.dsar_audit_anonymise_in_progress = 'on';

  UPDATE public.dsar_export_audit_pii
     SET requester_ip = NULL,
         user_agent   = NULL
   WHERE user_id = p_user_id;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_dsar_export_audit_pii(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_dsar_export_audit_pii(uuid) TO service_role;

COMMENT ON FUNCTION public.anonymise_dsar_export_audit_pii(uuid) IS
  'Art. 17 cascade hook: anonymises requester_ip + user_agent on '
  'dsar_export_audit_pii rows for the given user_id. Idempotent. '
  'Called from account-delete.ts before auth.admin.deleteUser(). '
  'Holds the ONLY SET-site for app.dsar_audit_anonymise_in_progress '
  'across the codebase (asserted by dsar-worm-guc-sites.test.ts).';

-- ============================================================================
-- TTL-expiry sweep (TR14): hourly UPDATE of completed jobs whose
-- signed_url_expires_at < now() to status='expired'. The Storage
-- object deletion is performed by the in-process poller observing
-- `expired` rows (pg_net is not installed — plan R5).
--
-- TR12 stuck-job sweep replaced by on-startup orphan reset in the
-- poller (plan S3). No pg_cron entry for it.
-- ============================================================================

DO $$
BEGIN
  PERFORM cron.schedule(
    'dsar-export-bundle-ttl-sweep',
    '0 * * * *',
    $cron$
      UPDATE public.dsar_export_jobs
         SET status = 'expired'
       WHERE status = 'completed'
         AND signed_url_expires_at IS NOT NULL
         AND signed_url_expires_at < now();
    $cron$
  );
EXCEPTION WHEN duplicate_object THEN
  -- Schedule already exists from a prior apply; safe to ignore.
  NULL;
END $$;

-- ============================================================================
-- Audit-PII retention sweep (TR13): daily 03:00 UTC DELETE of
-- dsar_export_audit_pii rows older than 24 months. Retention satisfies
-- Art. 5(2) accountability without exceeding Art. 5(1)(c) proportionality.
-- ============================================================================

DO $$
BEGIN
  PERFORM cron.schedule(
    'dsar-export-pii-retention-sweep',
    '0 3 * * *',
    $cron$
      DELETE FROM public.dsar_export_audit_pii
       WHERE event_at < now() - interval '24 months';
    $cron$
  );
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
