-- 051_multi_source_dedup.sql
-- PR-H (#3244) — Daily Priorities multi-source. Adds:
--   1. messages.source_ref (nullable text) for upstream-event dedup.
--   2. Partial-unique index on (user_id, source, source_ref) WHERE
--      status='draft' AND source_ref IS NOT NULL — the load-bearing
--      dedup primitive for GitHub webhook + KB-drift ingest replay.
--      Per ADR-032: webhook handler INSERTs without ON CONFLICT and
--      catches PG_UNIQUE_VIOLATION (23505) — mirrors Stripe's
--      processed_stripe_events pattern (#2772).
--   3. audit_github_token_use append-only ledger + record_github_token_use
--      SECURITY DEFINER RPC (Art. 5(2) accountability for the GitHub App
--      installation-token use surface).
--   4. processed_github_events(delivery_id PRIMARY KEY) — webhook-event
--      dedup mirror of processed_stripe_events. Retention via Postgres
--      autovacuum + 30-day partition rotation; no explicit TTL daemon.
--
-- Per cq-pg-security-definer-search-path-pin-pg-temp: every SECURITY
-- DEFINER fn pins SET search_path = public, pg_temp (public FIRST).
-- Precedent: 046_runtime_cost_state.sql + 048_scope_grants.sql.
--
-- Per 2026-05-06-supabase-default-privileges-defeat-revoke-from-public.md:
-- explicit REVOKE from PUBLIC + anon + authenticated; explicit GRANT to
-- service_role on each caller-facing RPC.

------------------------------------------------------------------------
-- 1. messages.source_ref (nullable; backfill-safe)
------------------------------------------------------------------------

ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS source_ref text;

COMMENT ON COLUMN public.messages.source_ref IS
  'Upstream-event reference for multi-source dedup (PR-H #3244). '
  'Examples: GitHub pr-<org>:<repo>:<number>, ci-<workflow_run_id>, '
  'issue-<org>:<repo>:<number>, cve-<advisory_id>, '
  'secret-scan-<org>:<repo>:<alert_number>; KB-drift '
  'link-<sha256[:16]> / anchor-<sha256[:16]>. The ":" separator is '
  'invalid in GitHub repo names so cannot collide. NULL for legacy and '
  'Stripe-sourced rows. The (user_id, source, source_ref) partial-'
  'unique index gates webhook replay at the DB level.';

------------------------------------------------------------------------
-- 2. Partial-unique index gating draft-row dedup across sources
------------------------------------------------------------------------
--
-- WHERE clause limits the constraint to the rows the dedup logic
-- actually cares about: open drafts with a non-NULL source_ref.
-- Sent / archived / null-source-ref rows are intentionally excluded
-- so the constraint cannot block legitimate re-drafts after a send.

CREATE UNIQUE INDEX IF NOT EXISTS messages_active_draft_dedup_idx
  ON public.messages (user_id, source, source_ref)
  WHERE status = 'draft' AND source_ref IS NOT NULL;

COMMENT ON INDEX public.messages_active_draft_dedup_idx IS
  'Partial-unique dedup gate for multi-source autonomous drafts. '
  'PR-H (#3244). Catches PG_UNIQUE_VIOLATION (23505) at the webhook '
  'INSERT site; ON CONFLICT DO NOTHING is avoided because supabase-js '
  '.insert() returns data:null (not [], not affected-row-count) on '
  'conflict-do-nothing, making the empty-result check unreliable.';

------------------------------------------------------------------------
-- 3. audit_github_token_use — append-only ledger
------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.audit_github_token_use (
  id                uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  founder_id        uuid         REFERENCES public.users(id) ON DELETE RESTRICT,
  installation_id   bigint       NOT NULL,
  repo_full_name    text         NULL CHECK (repo_full_name IS NULL OR length(repo_full_name) BETWEEN 1 AND 255),
  endpoint          text         NOT NULL CHECK (length(endpoint) BETWEEN 1 AND 256),
  ts                timestamptz  NOT NULL DEFAULT now(),
  response_status   int          NULL CHECK (response_status IS NULL OR (response_status BETWEEN 100 AND 599))
);

ALTER TABLE public.audit_github_token_use ENABLE ROW LEVEL SECURITY;

-- Founder may read their own audit trail (Art. 15 right-of-access).
CREATE POLICY audit_github_token_use_owner_select ON public.audit_github_token_use
  FOR SELECT USING (auth.uid() = founder_id);

CREATE INDEX IF NOT EXISTS audit_github_token_use_founder_ts_idx
  ON public.audit_github_token_use (founder_id, ts DESC);

COMMENT ON TABLE public.audit_github_token_use IS
  'Append-only ledger of GitHub App installation-token use. PR-H '
  '(#3244). Mirrors 037_byok_use_audit. Read via RLS SELECT; INSERTs '
  'routed exclusively through record_github_token_use SECURITY DEFINER '
  'RPC (service_role only). No founder INSERT/UPDATE/DELETE policies.';

------------------------------------------------------------------------
-- record_github_token_use — service-role-only INSERT RPC
------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.record_github_token_use(
  p_founder_id       uuid,
  p_installation_id  bigint,
  p_repo_full_name   text,
  p_endpoint         text,
  p_response_status  int
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid;
BEGIN
  INSERT INTO public.audit_github_token_use
    (founder_id, installation_id, repo_full_name, endpoint, response_status)
       VALUES (p_founder_id, p_installation_id, p_repo_full_name, p_endpoint, p_response_status)
       RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_github_token_use(uuid, bigint, text, text, int)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_github_token_use(uuid, bigint, text, text, int)
  TO service_role;

------------------------------------------------------------------------
-- 4. processed_github_events — webhook delivery dedup
------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.processed_github_events (
  delivery_id   text         PRIMARY KEY CHECK (length(delivery_id) BETWEEN 1 AND 128),
  received_at   timestamptz  NOT NULL DEFAULT now()
);

ALTER TABLE public.processed_github_events ENABLE ROW LEVEL SECURITY;

-- No founder-facing policies: service-role only, mirrors
-- processed_stripe_events. Webhook handler uses createServiceClient().

CREATE INDEX IF NOT EXISTS processed_github_events_received_at_idx
  ON public.processed_github_events (received_at DESC);

COMMENT ON TABLE public.processed_github_events IS
  'Webhook delivery_id dedup for GitHub App webhook. PR-H (#3244). '
  'Mirror of processed_stripe_events (#2772). Service-role-only via '
  'createServiceClient(). Plain .insert() at webhook entry; catch '
  'PG_UNIQUE_VIOLATION (23505) → 200 duplicate. On any 5xx after '
  'INSERT succeeds, DELETE the row (releaseDedupRow pattern) so the '
  'GitHub redelivery can re-process. Retention: Postgres autovacuum '
  '+ 30-day partition rotation (natural cleanup; no TTL daemon).';

------------------------------------------------------------------------
-- 5. Partial-UNIQUE on users.github_installation_id (cross-tenant guard)
------------------------------------------------------------------------
--
-- Migration 011 added users.github_installation_id without a uniqueness
-- constraint. The webhook resolves founder at route.ts via .maybeSingle()
-- which silently returns ONE of N matching rows on collision — a 1:N
-- mapping would cause cross-tenant attribution (founder A's PRs land on
-- founder B's dashboard). Partial-unique (WHERE NOT NULL) keeps multi-
-- founder onboarding viable (most rows are NULL pre-install).

CREATE UNIQUE INDEX IF NOT EXISTS users_github_installation_id_unique_idx
  ON public.users (github_installation_id)
  WHERE github_installation_id IS NOT NULL;

COMMENT ON INDEX public.users_github_installation_id_unique_idx IS
  'PR-H (#3244) — Cross-tenant attribution guard. The GitHub webhook '
  'resolves founder via .maybeSingle() on github_installation_id; '
  'without this index a 1:N mapping (two founders, same installation) '
  'would silently route to one of them. WHERE NOT NULL keeps the '
  'constraint compatible with pre-install rows.';

------------------------------------------------------------------------
-- 6. anonymise_audit_github_token_use — Art. 17 cascade hook
------------------------------------------------------------------------
--
-- audit_github_token_use.founder_id has ON DELETE RESTRICT (matches
-- 037_byok_use_audit precedent). account-delete.ts must call this RPC
-- BEFORE auth.admin.deleteUser() or the cascade aborts mid-flight. The
-- RPC NULLs founder_id (keeping the row for accountability) and zeros
-- repo_full_name (the only narrow-PII column). Idempotent.

CREATE OR REPLACE FUNCTION public.anonymise_audit_github_token_use(p_founder_id uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.audit_github_token_use
     SET founder_id = NULL,
         repo_full_name = NULL
   WHERE founder_id = p_founder_id;
END;
$$;

REVOKE ALL ON FUNCTION public.anonymise_audit_github_token_use(uuid)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.anonymise_audit_github_token_use(uuid)
  TO service_role;

COMMENT ON FUNCTION public.anonymise_audit_github_token_use(uuid) IS
  'PR-H (#3244) — Art. 17 cascade for audit_github_token_use. Called by '
  'server/account-delete.ts BEFORE auth.admin.deleteUser(); the FK is '
  'ON DELETE RESTRICT and the auth-delete would abort without this. '
  'Idempotent: re-running on already-anonymised rows is a no-op '
  '(UPDATE ... WHERE founder_id = p_founder_id matches zero rows). '
  'Bypasses the audit_github_token_use_no_mutate WORM trigger via '
  'SET LOCAL session_replication_role=replica (mig 037 + 044 pattern).';

------------------------------------------------------------------------
-- 7. WORM trigger on audit_github_token_use (defensive)
------------------------------------------------------------------------
--
-- Pure-reject trigger on UPDATE/DELETE. No role-check bypass (per
-- learning 2026-05-18-pure-reject-worm-no-role-bypass). The only path
-- that mutates rows is anonymise_audit_github_token_use, which sets
-- session_replication_role = 'replica' for the duration of the call so
-- the trigger fires under the replica role and short-circuits to
-- NULL-return (the standard "ignore replica" idiom is to skip the
-- trigger body entirely when triggered as replica).

CREATE OR REPLACE FUNCTION public.audit_github_token_use_no_mutate()
  RETURNS trigger
  LANGUAGE plpgsql
  SET search_path = public, pg_temp
AS $$
BEGIN
  -- Reject every UPDATE/DELETE on the audit ledger; the SECURITY DEFINER
  -- anonymise RPC sets session_replication_role='replica' so the trigger
  -- short-circuits there (Postgres skips triggers fired as 'replica' by
  -- default, but we add an explicit check for clarity in PRJ-PG-DBA
  -- forensics — same idiom as 044_consent_log_no_mutate).
  IF current_setting('session_replication_role') = 'replica' THEN
    RETURN NULL;
  END IF;
  RAISE EXCEPTION 'audit_github_token_use is append-only (PR-H #3244)'
    USING ERRCODE = 'P0001';
END;
$$;

CREATE TRIGGER audit_github_token_use_no_mutate
  BEFORE UPDATE OR DELETE ON public.audit_github_token_use
  FOR EACH ROW EXECUTE FUNCTION public.audit_github_token_use_no_mutate();

COMMENT ON FUNCTION public.audit_github_token_use_no_mutate() IS
  'PR-H (#3244) — WORM trigger for audit_github_token_use. Fires '
  'BEFORE UPDATE/DELETE; raises P0001 unless the caller has set '
  'session_replication_role=replica (the documented bypass for the '
  'anonymise_audit_github_token_use RPC). Mirrors mig 037 + 044 '
  'pattern; no role-check bypass (learning 2026-05-18).';

-- The anonymise RPC needs the replica-mode bypass; patch it to set the
-- GUC for the duration of its body. Per learning, SET LOCAL keeps the
-- bypass scoped to this transaction.
CREATE OR REPLACE FUNCTION public.anonymise_audit_github_token_use(p_founder_id uuid)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public, pg_temp
AS $$
BEGIN
  SET LOCAL session_replication_role = 'replica';
  UPDATE public.audit_github_token_use
     SET founder_id = NULL,
         repo_full_name = NULL
   WHERE founder_id = p_founder_id;
END;
$$;
