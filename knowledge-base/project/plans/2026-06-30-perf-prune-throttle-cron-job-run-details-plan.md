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

## Enhancement Summary

**Deepened on:** 2026-06-30
**Agents:** data-integrity-guardian, code-simplicity-reviewer (+ precedent-diff against 094/103/076/102).

### Key changes from review
1. **Folded in a one-line safety fix to `ws-handler.ts:768-772`** (cap-drift self-evict).
   The data-integrity-guardian found this is the *only* slot-count consumer that
   does NOT freshness-filter (its two siblings at `:522-526` and `:2004-2015` do).
   Without the filter, throttling the sweep `*/15 → hourly` widens a false
   live-session-eviction window ~4x (a downgraded user with crashed-but-unreaped
   slots). Adding `.gte("last_heartbeat_at", liveCutoff)` makes the throttle
   unambiguously safe AND fixes a pre-existing latent over-eviction bug. R1 updated.
2. **Dropped the one-time purge** (former statement 3). BOTH reviewers flagged it:
   `cron.job_run_details` has no index on `start_time`/`end_time` and `COALESCE(...)`
   is non-sargable, so the purge is a full seq-scan bulk delete of an
   unbounded-since-inception table — and coupling it under `--single-transaction`
   with the throttle means a slow/lock-timed-out purge **rolls back the throttle too**
   (losing the actual WAL win). The daily `0 4 * * *` job drains the backlog in
   isolation instead.
3. **Reinforced the WAL model:** the prune's own DELETE is WAL-logged, so the prune
   is strictly a disk/cache-pressure play, never a WAL play — the throttle is the
   only lever that reduces this table's WAL. (Bonus: hourly vs `*/15` also issues
   75% fewer DELETEs against `user_concurrency_slots`, a second WAL saving.)

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
  runs/day. **Made user-safe** by a paired one-line freshness-filter fix to the
  cap-drift evict count in `ws-handler.ts:768-772` — see Research Reconciliation R1.
- **Prune** `cron.job_run_details`: add a daily `0 4 * * *` sweep deleting rows
  older than **7 days** (satisfies the ≥7-day observability AC). The daily job
  drains the unbounded backlog over its first runs; **no one-time purge** is
  coupled into the migration (see Enhancement Summary #2). Closes the
  unbounded-growth gap.

Net effect: total cron runs ~128/day → ~56/day (**~56% fewer** `job_run_details`
INSERTs), and the table stops growing forever. (The prune's own DELETE is
WAL-logged, so it is a disk/cache play, not a WAL play — the throttle is the WAL
lever.)

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
| **R1: loosening the sweep is safe** | **Acquire path CONFIRMED safe:** `acquire_concurrency_slot` RPC (`093_acquire_slot_workspace_id.sql:79-81`) **self-reaps the caller's own stale slots inline** (`last_heartbeat_at < now()-120s`) *before* the per-user count (`093:93-94`); comment 093:77 calls cron a backup. `find_stuck_active_conversations` (037:59), the divergence probe (`ws-handler.ts:522-526`), and the sibling-slot probe (`ws-handler.ts:2004-2015`) are all freshness-filtered. **One gap found (data-integrity-guardian):** the cap-drift self-evict count at `ws-handler.ts:768-772` counts slots with NO freshness filter, so a downgraded user with crashed-but-unreaped slots could be falsely evicted; throttling `*/15→hourly` widens that window ~4x. | **Fold in the fix:** add `.gte("last_heartbeat_at", liveCutoff)` (120s) to the `:768-772` count, mirroring its two siblings. This removes the false-eviction risk entirely (a pre-existing latent bug) and makes the throttle unambiguously user-safe. Brand threshold stays `none`. |
| Prune via `DELETE … WHERE end_time < now()-7d` | `cron.job_run_details` rows for in-flight jobs have `end_time = NULL`; a literal `end_time <` predicate never reaps crash-orphaned NULL rows | Use `COALESCE(end_time, start_time) < now()-interval '7 days'` for robustness. |
| Migration apply is atomic | `scripts/run-migrations.sh:343` runs each file under `psql --single-transaction --set ON_ERROR_STOP=1` | Throttle + retention-schedule commit/rollback as one unit; **no** bulk data-delete is coupled into the transaction (one-time purge dropped — Enhancement Summary #2). |
| Pattern precedent exists | `094`, `103`, `076`, `102` all use the idempotent `DO … cron.unschedule guard → cron.schedule … EXCEPTION WHEN duplicate_object` block | Copy that shape verbatim; cite 103 as closest precedent. |
| No prior prune of `cron.job_run_details` | grep of all migrations: **none** — table has grown unbounded since project inception | Prune closes a genuine gap, justified independently of WAL. |

## User-Brand Impact

**If this lands broken, the user experiences:** the only user-facing surface is
slot-based session concurrency. Two paths considered: (1) slot *acquisition* —
cadence cannot gate it (acquire RPC self-reaps inline, R1); (2) cap-drift
*eviction* — the Phase 0 fix freshness-filters the `ws-handler.ts:768-772` count,
so a downgraded user is no longer falsely evicted when stale slots linger longer
under the hourly sweep (this fix removes a pre-existing latent bug). If the prune
DELETE lacked permission, the migration fails loudly at deploy (single-transaction
rollback) — no partial/broken state.

**If this leaks, the user's data is exposed via:** N/A. `cron.job_run_details`
holds job command text + status (no PII); `user_concurrency_slots` schema and
retention semantics are unchanged (only physical reap cadence); the `ws-handler.ts`
edit only narrows a COUNT predicate.

**Brand-survival threshold:** `none` — internal infra maintenance (p3-low). No
personal-data table schema/column/retention-semantics change; no new processing
activity. (Scope-out for the sensitive-path `.sql` + `apps/web-platform/server/`
gate: `threshold: none, reason: cron-maintenance DDL plus a one-line freshness
filter on a concurrency-count predicate — reschedules an existing sweep, adds a
system-log retention prune, and narrows a COUNT to exclude stale rows; touches no
personal-data column, schema, retention semantic, or data-exposure surface.`)

## Implementation Phases

### Phase 0 — Paired safety fix: freshness-filter the cap-drift evict count

In `apps/web-platform/server/ws-handler.ts:768-772`, add a liveness filter to the
slot count so it never counts crashed-but-unreaped rows (mirroring the sibling
probe at `:2004-2015`). This is the prerequisite that makes the Phase 1 throttle
user-safe (R1):

```ts
const liveCutoff = new Date(Date.now() - 120_000).toISOString();
const { count, error: countErr } = await tenant
  .from("user_concurrency_slots")
  .select("*", { count: "exact", head: true })
  .eq("user_id", userId)
  .gte("last_heartbeat_at", liveCutoff);   // NEW — match the 120s freshness threshold
```

Keep the `120_000` ms (= 120 s) cutoff consistent with the acquire RPC threshold.
This is a correctness fix that *reduces* user-facing risk (fewer false
`TIER_CHANGED` evictions); it is in-scope as the safety prerequisite of the throttle.

### Phase 1 — New migration `114_prune_cron_job_run_details.sql`

Single file, single transaction. **Two** statements (no one-time purge — see
Enhancement Summary #2):

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

Header comment must: cite the investigation learning + issue #5738; record the
96→24 run/day delta; note the 120s threshold is unchanged and why throttling is
safe (R1 + the Phase 0 ws-handler fix); cite 103 as the prune-pattern precedent;
note `COALESCE` rationale; note the first daily-job run drains the (unbounded)
backlog in isolation — see the dev-probe row-count note in Infrastructure.

Like the cited precedent (103), the migration omits the `WHEN undefined_table`
guard that 102 carries for pg_cron-less envs — acceptable because the apply target
(`web-platform-release.yml#migrate` → `run-migrations.sh`) always has pg_cron.

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

- `apps/web-platform/server/ws-handler.ts` (Phase 0) — add `.gte("last_heartbeat_at", liveCutoff)`
  to the cap-drift evict count at `:768-772`. One line + the `liveCutoff` const.
- (No edit to 038/093 — the sweep is rescheduled by a new forward migration,
  consistent with how 103 superseded 094's window.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **Phase 0 fix:** `ws-handler.ts:768-772` cap-drift evict count includes
  `.gte("last_heartbeat_at", liveCutoff)` with a 120 s (`120_000` ms) cutoff;
  `git grep -n 'last_heartbeat_at' apps/web-platform/server/ws-handler.ts` shows
  all three slot-count sites (`:522`, `:768-area`, `:2004`) now freshness-filter.
- [x] `114_prune_cron_job_run_details.sql` exists with **two** statements (throttle
  + retention schedule; no one-time purge); the throttle uses `0 * * * *`, and the
  slots DELETE body + `120 seconds` interval are **functionally identical** to
  migration 038's body (038's is a multi-line heredoc — match behavior, not bytes).
- [x] The retention DELETE uses `COALESCE(end_time, start_time) < now() - interval '7 days'`
  (≥7-day retention preserved per AC).
- [x] Idempotent `DO … unschedule guard → schedule … EXCEPTION WHEN duplicate_object`
  shape matches migration 103 (closest precedent).
- [x] `114_…down.sql` restores `*/15 * * * *` for the slots sweep and unschedules
  `cron_job_run_details_retention`. (The Phase 0 ws-handler fix is a strict
  improvement and is not reverted by the down migration.)
- [x] Header comment cites issue #5738, the investigation learning, the 96→24
  delta, and the R1 safety rationale (acquire self-reap + Phase 0 fix).
- [x] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is green (Phase 0
  edits `ws-handler.ts`).

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
finalizing, via Supabase MCP `execute_sql` on dev (and read-only on prd):
1. Confirm `DELETE FROM cron.job_run_details WHERE COALESCE(end_time,start_time) < now() - interval '7 days'`
   executes without a permission error.
2. **Quantify the backlog** — `SELECT count(*) FROM cron.job_run_details` (and the
   count older than 7 days). The table is unbounded-since-inception and was
   per-minute before mig 038, so the first daily-job drain could be large. The
   prune is non-sargable (no index on `start_time`/`end_time`) → a full seq scan.
   This runs in the daily cron job *in isolation* (NOT coupled to the migration
   transaction), so a slow first drain cannot roll back the throttle. If the count
   is very large (e.g. >500k), note a one-off batched manual purge via MCP as an
   option, decoupled from the migration.

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
retention migrations); deepened by data-integrity-guardian + code-simplicity-reviewer.
CTO checks **resolved**: (1) throttle safety — acquire RPC self-reaps inline (R1);
the deepen pass found the cap-drift evict count (`ws-handler.ts:768-772`) was the
only un-freshness-filtered slot consumer, now fixed in Phase 0; (2) atomicity —
`--single-transaction`, and the bulk one-time purge was dropped so no large delete
is coupled to the throttle; (3) WAL model confirmed — throttle is the WAL lever,
prune is disk/cache-pressure only. Deferred to /work: live-probe the
`cron.job_run_details` DELETE permission + backlog row count on dev (Infrastructure
§Vendor-tier reality check). No Product/UX surface (no files under `components/**`
or `app/**`), so the Product/UX Gate is skipped.

### Product/UX Gate
Skipped — NONE. No user-facing surface; no UI-surface file in Files to Create/Edit.

## GDPR / Compliance Gate
**Assessment: skip (documented).** The `.sql` + `apps/web-platform/server/` triggers
fire, but no regulated-data surface is materially touched: `cron.job_run_details`
is a system job log (command text + status, no PII); `user_concurrency_slots`
schema and retention semantics are unchanged (only physical reap cadence); the
`ws-handler.ts` edit narrows a COUNT predicate (no read/write of personal data).
No new processing activity, no LLM/external data movement, no DSAR/Article-30
impact. No critical findings to record.

## Test Scenarios

1. **Idempotency:** apply 114 twice on dev → second apply no-ops (guard + EXCEPTION),
   leaves exactly one `user_concurrency_slots_sweep` (hourly) and one
   `cron_job_run_details_retention`.
2. **Throttle takes effect:** after apply, `cron.job` shows `0 * * * *` for the
   slots sweep; over 24h the `job_run_details` insert rate drops ~56%.
3. **Prune correctness:** run the retention DELETE manually on dev →
   `COALESCE(end_time,start_time) < now()-7d` removes old rows and leaves newer
   rows + in-flight (NULL end_time, recent start_time) rows; a row with both
   columns NULL (`status='starting'`) is NOT deleted (`COALESCE→NULL`, `NULL<…` is
   not true).
4. **Down migration:** apply `.down.sql` → slots sweep back to `*/15`, retention
   job gone.
5. **No functional regression:** `acquire_concurrency_slot` still gates at the cap
   (self-reap path unchanged); start a session normally on dev.
6. **Phase 0 cap-drift fix:** with a live session + a synthetic stale slot
   (`last_heartbeat_at` > 120 s old) for the same user, a downgrade refresh tick
   does NOT evict the live session (the stale slot is excluded from the count);
   before the fix it would. `tsc --noEmit` green.

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
- **All slot-count consumers must freshness-filter** for the throttle to be safe.
  As of this plan there are three: `ws-handler.ts:522` (divergence), `:768`
  (cap-drift — fixed in Phase 0), `:2004` (sibling-slot). Any future code that
  counts `user_concurrency_slots` without `.lt`/`.gte("last_heartbeat_at", …)` will
  silently regress under the slower sweep — grep before adding one.
- **Do not re-introduce the one-time purge inside the migration.** `cron.job_run_details`
  is unindexed on time columns and `COALESCE(...)` is non-sargable, so a bulk delete
  there is a seq scan; coupling it under `--single-transaction` risks rolling back
  the throttle. If immediate backlog relief is needed, run a batched delete via MCP
  *outside* the migration.
- Precedent-diff gate (deepen-plan Phase 4.4): satisfied — the migration shape
  matches `103_github_events_retention_7day.sql` (closest precedent, cited in R1
  and the header-comment instructions); diff again at /work before freezing.
