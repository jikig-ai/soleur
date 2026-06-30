---
title: "perf(db): prune + throttle pg_cron cron.job_run_details to cut prod WAL"
date: 2026-06-30
type: chore
issue: 5738
branch: feat-one-shot-5738-prune-cron-job-run-details
lane: single-domain
brand_survival_threshold: none
status: planned
---

# perf(db): prune + throttle pg_cron `cron.job_run_details` — ~5% of prod WAL 🔧

## Overview

Follow-up from the 2026-06-30 Supabase Disk-IO-budget depletion investigation
(`knowledge-base/project/learnings/2026-06-30-supabase-disk-io-budget-diagnosis-and-management-api-config.md`).
On prod `soleur-web-platform` (`ifsccnjhymdmidffkzhl`, Micro, 1 GB RAM) the 46 MB DB
is 100% cached, so Disk-IO is **write-dominated (~12 GB/day WAL)**. The #1 source
(63%, GitHub-webhook dedup) shipped in **PR #5736 (merged)**. This issue targets a
residual: `INSERT INTO cron.job_run_details` = **4.7% of WAL** (55 MB, 6,670 calls,
10,584 FPIs over the pg_stat_statements window).

`pg_cron` logs one row to `cron.job_run_details` for **every** scheduled run and
**never auto-prunes**. Two facts shape the fix:

1. **The WAL is the INSERTs, not the table size.** A retention prune bounds the
   (currently unbounded) table but does **not** retroactively reduce per-INSERT
   WAL. The lever that measurably cuts WAL going forward is **fewer runs**.
2. **The run population is dominated by one job.** The `user_concurrency_slots_sweep`
   at `*/15 * * * *` is **96 runs/day ≈ 75%** of all cron runs (full enumeration
   below). Throttling it is the single biggest WAL lever for this table.

**Chosen approach — combine the issue's option 2 (primary) + option 1 (secondary)
in one migration:**

- **Throttle** `user_concurrency_slots_sweep` `*/15 → 0 * * * *` (hourly): 96 → 24
  runs/day. **Verified user-safe** — see Research Reconciliation R1.
- **Prune** `cron.job_run_details`: add a daily `0 4 * * *` sweep deleting rows
  older than **7 days** (satisfies the ≥7-day observability AC), plus a one-time
  purge so relief lands at deploy. Closes the unbounded-growth gap.

Net effect: total cron runs ~128/day → ~56/day (**~56% fewer** `job_run_details`
INSERTs), and the table stops growing forever.

**Option 3 (disable run logging) rejected:** pg_cron's `cron.log_run` is a
database-wide GUC requiring superuser / the Supabase Management API (the
investigation learning documents `ALTER DATABASE … SET …` → `42501 permission
denied` on the managed `postgres` role), AND disabling logging conflicts with the
AC "no loss of cron observability." Documented, not pursued.

### Cron job population (enumerated from `apps/web-platform/supabase/migrations/`)

| Job | Schedule | Runs/day | After change |
|---|---|---|---|
| `user_concurrency_slots_sweep` (038) | `*/15 * * * *` | **96** | **24** (`0 * * * *`) |
| dsar export processor (041) | `0 * * * *` | 24 | 24 (out of scope — GDPR SLA) |
| dsar daily (041) | `0 3 * * *` | 1 | 1 |
| tenant_deploy_audit (043), 062, 063 | `0 4 * * *` | 3 | 3 |
| workspace_activity_purge (076) | `0 3 * * *` | 1 | 1 |
| processed_github_events_retention (094→103) | `0 4 * * *` | 1 | 1 |
| processed_stripe_events_retention (094) | `0 4 * * *` | 1 | 1 |
| processed_resend_events_retention (102) | `0 4 * * *` | 1 | 1 |
| **cron_job_run_details_retention (NEW, 114)** | `0 4 * * *` | — | +1 |
| **Total** | | **~128** | **~56** |

## Research Reconciliation — Spec vs. Codebase

| Claim (issue/premise) | Reality (verified) | Plan response |
|---|---|---|
| PR #5736 fixes the dominant source | **Merged** (commit `3ac94bd25`) | Premise holds; this issue is the residual. |
| `*/15` sweep could move to `*/30`/hourly; "check 038's rationale" | 038's rationale = cut writes; 120s freshness threshold is **independent** of cadence | Loosen to **hourly**; keep 120s threshold untouched. |
| **R1: loosening the sweep is safe** | `acquire_concurrency_slot` RPC (`093_acquire_slot_workspace_id.sql:79-81`) **self-reaps the caller's own stale slots inline** (`last_heartbeat_at < now()-120s`) *before* the count; comment 093:77 explicitly calls cron a backup "so a crashed WS can reclaim a slot on reconnect even before cron runs." `find_stuck_active_conversations` (037:59) is freshness-filtered too. | **No user-facing concurrency impact** from a slower sweep — it only delays physical reap of *other* users' dead rows, which they reclaim on their own next acquire. Brand threshold `none`. |
| Prune via `DELETE … WHERE end_time < now()-7d` | `cron.job_run_details` rows for in-flight jobs have `end_time = NULL`; a literal `end_time <` predicate never reaps crash-orphaned NULL rows | Use `COALESCE(end_time, start_time) < now()-interval '7 days'` for robustness. |
| Migration apply is atomic | `scripts/run-migrations.sh:343` runs each file under `psql --single-transaction --set ON_ERROR_STOP=1` | Reschedule + one-time purge commit/rollback as one unit. |
| Pattern precedent exists | `094`, `103`, `076`, `102` all use the idempotent `DO … cron.unschedule guard → cron.schedule … EXCEPTION WHEN duplicate_object` block | Copy that shape verbatim; cite 103 as closest precedent. |
| No prior prune of `cron.job_run_details` | grep of all migrations: **none** — table has grown unbounded since project inception | Prune closes a genuine gap, justified independently of WAL. |

## User-Brand Impact

**If this lands broken, the user experiences:** if the throttle were wrong (it is
not — R1), a user could be falsely blocked from starting a session by a stale
concurrency slot. Mitigated: the acquire RPC self-reaps inline, so cadence cannot
gate acquisition. If the prune DELETE lacked permission, the migration fails
loudly at deploy (single-transaction rollback) — no partial/broken state.

**If this leaks, the user's data is exposed via:** N/A. `cron.job_run_details`
holds job command text + status (no PII); `user_concurrency_slots` schema and
retention semantics are unchanged (only physical reap cadence).

**Brand-survival threshold:** `none` — internal infra maintenance (p3-low). No
personal-data table schema/column/retention-semantics change; no new processing
activity. (Scope-out for the sensitive-path `.sql` gate: `threshold: none, reason:
cron-maintenance DDL only — reschedules an existing sweep and adds a system-log
retention prune; touches no personal-data column, schema, or retention semantic.`)

## Implementation Phases

### Phase 1 — New migration `114_prune_cron_job_run_details.sql`

Single file, single transaction. Three statements:

1. **Throttle the slots sweep** (idempotent reschedule, body unchanged):
   ```sql
   DO $cron_block$
   BEGIN
     IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'user_concurrency_slots_sweep') THEN
       PERFORM cron.unschedule('user_concurrency_slots_sweep');
     END IF;
     PERFORM cron.schedule(
       'user_concurrency_slots_sweep',
       '0 * * * *',  -- was */15 (mig 038); hourly. 120s freshness threshold unchanged.
       $sweep$delete from public.user_concurrency_slots where last_heartbeat_at < now() - interval '120 seconds';$sweep$
     );
   EXCEPTION WHEN duplicate_object THEN NULL;
   END $cron_block$;
   ```

2. **Add the retention prune** (new job):
   ```sql
   DO $cron_block$
   BEGIN
     IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cron_job_run_details_retention') THEN
       PERFORM cron.unschedule('cron_job_run_details_retention');
     END IF;
     PERFORM cron.schedule(
       'cron_job_run_details_retention',
       '0 4 * * *',
       $$DELETE FROM cron.job_run_details WHERE COALESCE(end_time, start_time) < now() - interval '7 days'$$
     );
   EXCEPTION WHEN duplicate_object THEN NULL;
   END $cron_block$;
   ```

3. **One-time purge** so relief lands at deploy, not on the next 04:00 run:
   ```sql
   DELETE FROM cron.job_run_details WHERE COALESCE(end_time, start_time) < now() - interval '7 days';
   ```

Header comment must: cite the investigation learning + issue #5738; record the
96→24 run/day delta; note the 120s threshold is unchanged and why throttling is
safe (R1); cite 103 as the prune-pattern precedent; note `COALESCE` rationale.

### Phase 2 — Down migration `114_prune_cron_job_run_details.down.sql`

Restore the immediately-prior state: reschedule `user_concurrency_slots_sweep`
back to `*/15 * * * *` (its state from migration 038), and
`PERFORM cron.unschedule('cron_job_run_details_retention')` (guarded by the
`IF EXISTS` check). Do not attempt to restore deleted `job_run_details` rows
(irrecoverable, observability-only — acceptable).

## Files to Create

- `apps/web-platform/supabase/migrations/114_prune_cron_job_run_details.sql`
- `apps/web-platform/supabase/migrations/114_prune_cron_job_run_details.down.sql`

## Files to Edit

- None. (No app code touched. No edit to 038/093 — the sweep is rescheduled by a
  new forward migration, consistent with how 103 superseded 094's window.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `114_prune_cron_job_run_details.sql` exists with all three statements; the
  throttle uses `0 * * * *`, the slots DELETE body and the `120 seconds` interval
  are byte-identical to migration 038's body.
- [ ] Both prune statements use `COALESCE(end_time, start_time) < now() - interval '7 days'`
  (≥7-day retention preserved per AC).
- [ ] Idempotent `DO … unschedule guard → schedule … EXCEPTION WHEN duplicate_object`
  shape matches migration 103 (closest precedent).
- [ ] `114_…down.sql` restores `*/15 * * * *` for the slots sweep and unschedules
  `cron_job_run_details_retention`.
- [ ] Header comment cites issue #5738, the investigation learning, the 96→24
  delta, and the R1 safety rationale (acquire self-reap).
- [ ] `apps/web-platform` typecheck/tests unaffected: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is green (no app code changed).

### Post-merge (operator/automated — via Supabase MCP `execute_sql`, read-only verify; no SSH)

- [ ] Migration applied by the release pipeline (`web-platform-release.yml#migrate`
  runs `run-migrations.sh` on merge to main touching `apps/web-platform/**`). No
  operator step.
- [ ] `SELECT schedule FROM cron.job WHERE jobname='user_concurrency_slots_sweep'`
  returns `0 * * * *`.
- [ ] `SELECT 1 FROM cron.job WHERE jobname='cron_job_run_details_retention'`
  returns one row.
- [ ] Run-rate dropped: `SELECT count(*) FROM cron.job_run_details WHERE start_time > now() - interval '24 hours'` trends from ~128 toward ~56 over the first day post-deploy (direct proxy for INSERT WAL — count of runs == count of INSERTs).
- [ ] WAL re-measure: `SELECT calls, wal_bytes FROM pg_stat_statements WHERE query LIKE 'INSERT INTO cron.job_run_details%'` — the `calls`/day rate is ~56% lower than the pre-change baseline. (Note: cumulative `wal_bytes` does not drop retroactively; measure the *rate* over a window, or compare after a pg_stat_statements reset.)
- [ ] `Ref #5738` in the PR body (NOT `Closes` — verification completes post-merge); close #5738 after the run-rate verify holds.

## Observability

```yaml
liveness_signal:
  what: the throttled slots sweep + new retention prune appear in cron.job_run_details with status='succeeded'
  cadence: hourly (slots sweep) / daily 04:00 UTC (retention prune)
  alert_target: existing Disk-IO pressure monitor (migration 095 RPC + Sentry, per 2026-06-02 plan)
  configured_in: apps/web-platform/supabase/migrations/095_disk_io_pressure_signal.sql
error_reporting:
  destination: cron.job_run_details (status='failed', return_message) — queryable via Supabase MCP execute_sql
  fail_loud: migration apply fails the release pipeline under --single-transaction (ON_ERROR_STOP=1) if the prune lacks permission
failure_modes:
  - mode: prune DELETE lacks permission on cron.job_run_details
    detection: migration aborts at deploy; release pipeline red
    alert_route: GitHub Actions failure on web-platform-release.yml#migrate
  - mode: retention job silently DELETE 0 every run (predicate wrong)
    detection: cron.job_run_details row count keeps growing post-deploy
    alert_route: Disk-IO pressure monitor (mig 095) + manual run-count query
  - mode: throttle accidentally blocks slot acquisition
    detection: ruled out by R1 (acquire self-reaps); would surface as user "concurrency limit" Sentry errors
    alert_route: Sentry (existing start_session error path)
logs:
  where: cron.job_run_details (Postgres); release pipeline logs (GitHub Actions)
  retention: 7 days (this migration's own prune); GH Actions default
discoverability_test:
  command: "Supabase MCP execute_sql: SELECT jobname, schedule FROM cron.job ORDER BY jobname"
  expected_output: "user_concurrency_slots_sweep -> 0 * * * *; cron_job_run_details_retention present"
```

## Infrastructure (IaC)

This is DB-internal infrastructure (pg_cron schedules) declared as a Supabase
migration — the repo's established mechanism (mirrors 094/103/076/102). It is
**not** operator SSH and **not** a dashboard action.

### Apply path
Migration runner (`apps/web-platform/scripts/run-migrations.sh`) invoked by
`web-platform-release.yml#migrate` on merge to main touching `apps/web-platform/**`.
Each file runs under `psql --single-transaction`. Zero downtime, blast-radius =
one DB transaction. No operator action.

### Distinctness / drift safeguards
Idempotent `cron.unschedule` guard + `EXCEPTION WHEN duplicate_object` make
re-application safe on dev and prd. Migration ledger (run-migrations.sh) prevents
double-apply. No Terraform / secrets / vendor surface involved.

### Vendor-tier reality check
pg_cron + `cron.job_run_details` DELETE is the canonical Supabase-documented
retention pattern; available on the managed Micro tier (the `postgres` role owns
the `cron` schema). **Live-probe at /work** (per the live-probe Sharp Edge): before
finalizing, confirm via Supabase MCP `execute_sql` on dev that
`DELETE FROM cron.job_run_details WHERE COALESCE(end_time,start_time) < now() - interval '7 days'`
executes without a permission error.

## Architecture Decision (ADR/C4)

**No ADR / C4 change.** This reschedules an existing pg_cron job and adds a
retention sweep following 4 sibling precedents (094/103/076/102). No new substrate,
no ownership/tenancy boundary, no resolver/trust-boundary change, no reversal of an
existing ADR. The "Inngest > GH Actions cron" precedent (ADR-030/033) governs
**app-level** Claude-invoking scheduled jobs; **DB-internal maintenance** has
always been pg_cron in SQL migrations — this plan is consistent with that, not a
new decision. C4 actors/systems checked: no new external actor, external system,
data store, or access relationship — `cron.job_run_details` and
`user_concurrency_slots` are existing internal containers, unchanged in topology.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** reviewed (inline — planning agent, CTO lens; deepen-plan adds parallel agents)
**Assessment:** Low-risk infra chore on a well-trodden pattern (4 sibling
retention migrations). Two CTO checks were load-bearing and are **resolved**:
(1) throttle safety — verified the acquire RPC self-reaps inline (R1), so cadence
has no concurrency impact; (2) atomicity — confirmed `--single-transaction`. One
check deferred to /work: live-probe the `cron.job_run_details` DELETE permission on
dev (Infrastructure §Vendor-tier reality check). No Product/UX surface (no files
under `components/**` or `app/**`), so the Product/UX Gate is skipped.

### Product/UX Gate
Skipped — NONE. No user-facing surface; no UI-surface file in Files to Create/Edit.

## GDPR / Compliance Gate
**Assessment: skip (documented).** The `.sql` trigger fires, but no regulated-data
surface is materially touched: `cron.job_run_details` is a system job log (command
text + status, no PII); `user_concurrency_slots` schema and retention semantics are
unchanged (only physical reap cadence). No new processing activity, no LLM/external
data movement, no DSAR/Article-30 impact. No critical findings to record.

## Test Scenarios

1. **Idempotency:** apply 114 twice on dev → second apply no-ops (guard + EXCEPTION),
   leaves exactly one `user_concurrency_slots_sweep` (hourly) and one
   `cron_job_run_details_retention`.
2. **Throttle takes effect:** after apply, `cron.job` shows `0 * * * *` for the
   slots sweep; over 24h the `job_run_details` insert rate drops ~56%.
3. **Prune correctness:** seed a synthetic old row (or wait) → the 04:00 job and
   the one-time purge delete rows with `COALESCE(end_time,start_time) < now()-7d`
   and leave newer rows + in-flight (NULL end_time, recent start_time) rows.
4. **Down migration:** apply `.down.sql` → slots sweep back to `*/15`, retention
   job gone.
5. **No functional regression:** `acquire_concurrency_slot` still gates at the cap
   (self-reap path unchanged); start a session normally on dev.

## Open Code-Review Overlap
None — checked the 63 open `code-review` issues against `job_run_details`,
`user_concurrency_slots_sweep`, `038_slow`, `093_acquire`, `cron.job_run_details`;
zero matches.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
  (This plan's threshold is `none` with the required sensitive-path scope-out
  reason — see above.)
- **Live-probe before relying on cron-schema DELETE perms** (`cron.job_run_details`
  is in the `cron` schema). The canonical Supabase doc supports this DELETE, but
  confirm on dev via MCP `execute_sql` at /work before merge.
- **Do not lower retention below 7 days** — the AC requires ≥7 days of cron
  observability for incident triage.
- **Do not touch the dsar hourly job (041)** — it is the second-largest
  `job_run_details` source (24/day) but is a functional GDPR DSAR-export processor
  with fulfillment-SLA implications; out of scope.
- **`wal_bytes` is cumulative** in `pg_stat_statements` — it will not drop
  retroactively after the change. Verify via the per-day *run count* (deterministic)
  or a wal_bytes *rate* over a window; do not expect the historical total to shrink.
- Precedent-diff gate (deepen-plan Phase 4.4): diff the new migration against
  `103_github_events_retention_7day.sql` (closest precedent) before freezing.
