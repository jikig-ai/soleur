-- 124_prune_auth_flow_state.sql
--
-- Bound the unbounded auth.flow_state GoTrue table + purge its stale-OAuth-token
-- backlog with a daily pg_cron retention prune (issue #5739).
--
-- Why (2026-06-30 Supabase Disk-IO-budget investigation, see
--   knowledge-base/project/learnings/2026-06-30-supabase-disk-io-budget-diagnosis-and-management-api-config.md;
--   post-soak re-measured 2026-07-07 on prod ifsccnjhymdmidffkzhl):
--   #5739 tracked "~18% of prod WAL from Supabase Auth". The honest, live-measured
--   finding is that the BULK of Auth WAL (refresh_tokens/sessions/mfa INSERTs) is
--   legitimate, irreducible login volume — no loop, no short-JWT-TTL churn — so no
--   WAL lever ships here (JWT-TTL deferred; see the PR body / plan Non-Goal NG1).
--   What IS actionable is a different problem this surfaced: auth.flow_state grows
--   UNBOUNDED and GoTrue NEVER prunes it. Live on prod 2026-07-07: 4,303 rows,
--   3,796 older than 7 days, oldest 2026-03-17 (~3.7 months), and 99.6% are
--   ABANDONED flows (auth_code_issued_at IS NULL — the auth code was never issued
--   or exchanged). Abandoned rows retain provider_access_token /
--   provider_refresh_token columns, so this is ALSO a security / GDPR
--   data-minimization improvement (stale third-party OAuth credentials sitting in
--   the DB for months), not only bloat / dead-tuple control.
--
--   Framing discipline (load-bearing), per learning
--   2026-06-30-pgcron-cadence-is-wal-lever-retention-prune-is-disk-play.md:
--   a retention prune reduces TABLE SIZE / dead-tuple churn / disk pressure, it
--   does NOT reduce per-INSERT WAL — and the prune's own DELETE is itself
--   WAL-logged. flow_state INSERTs are only ~4.5 MB/7d vs refresh_tokens ~20 MB/7d
--   (live pgss 2026-07-07). So this migration is framed as a BLOAT + stale-secret
--   minimization play, NOT a WAL reduction. The auth-schema WAL share is unchanged
--   by design.
--
-- 7-day window (matches siblings 103 github_events + 115 cron_job_run_details):
--   The unexchangeable floor is ~10 minutes — GoTrue's PKCE FlowStateExpiryDuration
--   is 5 min and the live mailer_otp_exp is 600 s / 10 min (configure-auth.sh:52,
--   NOT the 1-day GoTrue default), so a row older than 7 days is unexchangeable by
--   construction (~1000x margin). A pruned row can never break an in-flight
--   magic-link / OAuth / SSO login.
--   FLOOR-INVARIANT: the window MUST exceed the highest configured OTP/link expiry.
--   If mailer_otp_exp (or any flow TTL) is ever raised toward days, re-derive this
--   window. Do NOT lower below 1 day.
--   NOTE on the predicate column: auth.flow_state has NO expires_at column (live-
--   verified) — GoTrue computes expiry lazily at exchange time from created_at, and
--   its own IsExpired() reads created_at. So the predicate uses created_at.
--   NOTE on scope: this touches flow_state (PKCE/OAuth/magic-link/SSO web flows)
--   only. MFA/AAL2 challenges live in a different table (auth.mfa_challenges) that
--   this prune does not touch.
--
-- Permissioning: runs as `postgres`, which holds an explicit DELETE grant on
--   auth.flow_state AND rolbypassrls (both live-verified 2026-07-07) — like the
--   sibling pg_cron retention jobs (103/115/094/076/038), which all run as
--   `postgres`. No SECURITY DEFINER function is needed or introduced. This is the
--   first in-repo cron to own retention on a vendor-auth (GoTrue-managed) `auth`
--   schema table — every prior retention cron targets public.* EXCEPT 115, which
--   prunes the pg_cron-owned `cron` schema; none touch a vendor-owned auth schema.
--   The DELETE grant is revocable by a future platform upgrade — on revocation the cron
--   simply errors (visible in cron.job_run_details) with NO data risk, failing OPEN
--   (stale-token minimization lapses; it does not fail closed). Accepted in writing
--   at p3 (see plan Observability §Fails-open + ADR-098).
--
-- Atomicity: run-migrations.sh runs each file under `psql --single-transaction`, so
--   the cron schedule AND the one-time purge commit/rollback as one unit. Do NOT add
--   a top-level BEGIN;/COMMIT; here — a self-issued COMMIT breaks ledger idempotency
--   (knowledge-base/project/learnings/build-errors/2026-05-25-migration-body-no-top-level-begin-commit.md). The
--   `EXCEPTION WHEN duplicate_object` guard is belt-and-suspenders on top of the
--   cron.unschedule guard.
--
-- Idempotent: cron.unschedule guard before cron.schedule, EXCEPTION WHEN
--   duplicate_object — same shape as 103/115 (and 094/076/102). Like 103/115, omits
--   102's `WHEN undefined_table` guard because the apply target
--   (web-platform-release.yml#migrate -> run-migrations.sh) always has pg_cron.
--
-- See: knowledge-base/project/plans/2026-07-07-perf-prune-auth-flow-state-bloat-plan.md
-- ADR: knowledge-base/engineering/architecture/decisions/ADR-098-*.md
-- Issue: #5739

-- =====================================================================
-- 1. Schedule the daily retention prune (NEW job)
-- =====================================================================

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'auth_flow_state_retention') THEN
    PERFORM cron.unschedule('auth_flow_state_retention');
  END IF;
  PERFORM cron.schedule(
    'auth_flow_state_retention',
    '0 4 * * *',
    $$DELETE FROM auth.flow_state WHERE created_at < now() - interval '7 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;

-- =====================================================================
-- 2. One-time backlog purge so relief lands at deploy (not on the next 04:00 run)
-- =====================================================================
-- ~3.8k rows are already older than 7 days (oldest ~3.7 months). The table is tiny
-- (~4.3k rows total) so a single in-transaction row-level DELETE completes in well
-- under a second — unlike 115's 28k rows, which deferred its drain to the first cron
-- run to avoid a non-sargable seq scan under --single-transaction. The DELETE takes
-- ROW EXCLUSIVE only (never ACCESS EXCLUSIVE) and matches only stale rows
-- (created_at < now() - 7d), so it cannot lock or block a concurrent live sign-in
-- (GoTrue touches rows < ~5 min old on exchange). The one referential dependent,
-- auth.saml_relay_states.flow_state_id, is FK'd ON DELETE CASCADE (live-verified
-- 2026-07-07) and is currently empty (Soleur has no SAML SSO wiring). So even if a
-- future SAML onboarding populated it, deleting an aged-out parent flow_state would
-- cascade-delete its ephemeral relay-state child — never block, never orphan, never
-- error. The prune reaches into saml_relay_states via that cascade by design.

DELETE FROM auth.flow_state WHERE created_at < now() - interval '7 days';
