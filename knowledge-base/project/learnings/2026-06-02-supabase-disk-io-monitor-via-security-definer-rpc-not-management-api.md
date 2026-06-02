---
date: 2026-06-02
category: integration-issues
module: observability / supabase
tags: [supabase, disk-io, security-definer-rpc, inngest-cron, sentry, pg_stat, migration-collision]
issue: feat-one-shot-supabase-disk-io-sentry-monitor (PR #4801)
---

# Learning: Monitor Supabase Disk-IO from the app runtime via a SECURITY DEFINER RPC, not the Management API

## Problem

Supabase sent a Disk IO Budget depletion warning for prod. We needed (1) to fix the
recurrence and (2) to add a proactive monitor + Sentry alert that detects high Disk-IO
BEFORE the budget depletes.

Two non-obvious constraints surfaced:

1. **Supabase Disk IO Budget is a vendor metric, not a Sentry event, and the Management
   API exposes no stable `disk_io_budget` metric endpoint** (probed: `infra-monitoring/metrics`,
   `daily-stats`, `usage` all 404). So a `sentry_metric_alert` cannot fire on it — the only
   workable shape is "poll a signal → apply our own verdict → emit a heartbeat".

2. The plan's chosen signal source — the **Management API SQL endpoint** — requires a
   `SUPABASE_ACCESS_TOKEN` (an **account-scoped Personal Access Token**) at runtime. That
   token is NOT in the app-runtime Doppler config (`grep` found it only in a one-off script),
   and provisioning an account-god-mode PAT into the web container is a **security downgrade**.

## Solution

**Read the signal from inside Postgres via a read-only SECURITY DEFINER RPC, called through
the service-role client the runtime already has** — no Management API PAT required.

- `disk_io_pressure_signal()` (migration 095): `LANGUAGE sql STABLE SECURITY DEFINER`,
  `SET search_path = public, pg_temp`, `REVOKE ALL FROM PUBLIC, anon, authenticated,
  service_role` then `GRANT EXECUTE TO service_role`. Body is a single `SELECT
  jsonb_build_object(...)` over `pg_catalog.pg_stat_database` (cache-hit ratio) and
  `pg_catalog.pg_stat_user_tables` (live-row counts + top write-churn). PostgREST cannot
  expose `pg_catalog` views, so the RPC is the only in-container channel.
- The Inngest cron (`cron-supabase-disk-io.ts`) calls it via `createServiceClient().rpc(...)`
  inside `step.run` — the exact posture of `cron-workspace-sync-health.ts` — and is added to
  `.service-role-allowlist`. Mirrors `cron-gh-pages-cert-state.ts` for the issue file/close +
  `postSentryHeartbeat` plumbing.

This is strictly *narrower* privilege than the Management API PAT: one `service_role`-only
EXECUTE grant on one read-only function vs. an account-scoped token in the container.

## Key Insight

When you need Postgres-internal stats (`pg_stat_*`, `pg_catalog.*`) from a Supabase app at
runtime, the canonical path is a **SECURITY DEFINER RPC owned by the migration role** (which
holds `pg_monitor` on Supabase) called via the service-role client — NOT the Management API
and NOT a direct `pg` connection. Use `pg_stat_database` for the cache-hit ratio (no
`pg_stat_statements` extension dependency → reset-tolerant). Keep the verdict **stateless**
(absolute floor/ceiling thresholds) so no cross-run `/var/lib` last-sample file is needed.

Two corroborating details:
- The signal RPC's correctness depends on the OWNER holding `pg_monitor` (a non-member sees
  only its own backend's rows, others NULL-masked). On Supabase migrations run as `postgres`
  (a `pg_monitor` member), so it holds — a non-null `cache_hit_pct` on first manual-trigger
  fire is the runtime confirmation.
- The write-driven diagnosis (cache hit = 100.000%, 1,614 disk reads vs 1.04B hits) means
  read-index work is wasted; the real fixes were poll-cadence widening (60s→300s reaper) and
  a daily pg_cron retention sweep on the unbounded webhook dedup tables.

## Session Errors

1. **Migration-number collision — plan said 093, origin/main advanced to 093 mid-session.**
   A sibling PR merged `093_acquire_slot_workspace_id` after the worktree was created from a
   slightly-older origin/main. Recovery: `git fetch origin main` + the pre-apply collision
   check (`git ls-tree origin/main … | grep -oE '^[0-9]{3}'`) caught it BEFORE any apply;
   rebased onto fresh origin/main and renumbered to 094/095.
   **Prevention:** already covered by the work-skill "Pre-apply collision check (always, even
   on first attempt)" — this session confirms its value. Plan-prescribed migration numbers
   are preconditions to verify at /work-start, never facts.

2. **Validating a migration against dev via python `urllib` returned HTTP 403 (Cloudflare
   error 1010 — UA ban).** Recovery: build the JSON payload in python but POST via `curl`
   (which the Management API accepts).
   **Prevention:** for Supabase Management API calls, use `curl` (or a real browser UA), not
   `urllib`/default-UA HTTP clients — Cloudflare bans the default agent.

3. **`Number(null) === 0` false-trip in the monitor verdict** — a null `cache_hit_pct` (no
   pg_stat rows) would have been coerced to 0 and tripped the `< 98` floor. Caught by a RED
   test fixture with a null signal; fixed with `signal.cache_hit_pct == null ? NaN : Number(...)`.
   **Prevention:** when a numeric threshold gate can receive null/undefined (DB nullable,
   absent JSON key), guard `== null` BEFORE `Number()` — `Number(null)` is 0, not NaN.

4. **Bash CWD persistence friction** — repeated `cd apps/web-platform` failures because the
   Bash tool's CWD persisted from a prior `cd`. Recovery: run commands without the redundant
   `cd`, or chain `cd <abs-path> && cmd` in one call.
   **Prevention:** already a documented work-skill caveat; not novel.

5. **Edit "File has not been read yet"** on files I'd only inspected via Bash grep/sed.
   Recovery: Read-tool the file first.
   **Prevention:** the Edit tool requires a prior Read-tool read (Bash `cat`/`grep`/`sed` does
   not satisfy it) — already a hard rule (`hr-always-read-a-file-before-editing-it`).

## Tags
category: integration-issues
module: observability
