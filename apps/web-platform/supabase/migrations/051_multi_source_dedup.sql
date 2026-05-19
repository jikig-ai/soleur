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
  'Examples: GitHub pr-<repo>-<number>, ci-<workflow_run_id>, '
  'issue-<repo>-<number>, cve-<advisory_id>; KB-drift '
  'link-<sha256[:16]> / anchor-<sha256[:16]>. NULL for legacy and '
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
