<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
date: 2026-06-02
type: fix
issue: TBD
branch: feat-one-shot-supabase-disk-io-sentry-monitor
worktree: .worktrees/feat-one-shot-supabase-disk-io-sentry-monitor
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
classification: ops-only-prod-write
lane: cross-domain
---

# Plan: Resolve recurring Supabase prod Disk IO depletion + add a proactive Sentry monitor

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Premise Validation, Live Diagnostics, Phase 2 (retention SQL), Phase 4
(Sentry allowlist), Acceptance Criteria, Sharp Edges.

### Key Improvements (from deepen pass)
1. **Corrected the retention timestamp column** from `created_at` → **`received_at`** (verified
   against migration 052:128 — the `created_at` example would have failed at deploy). Adopted
   migration 076's exact `DO $cron_block$ … EXCEPTION WHEN duplicate_object` precedent shape and
   noted the existing `received_at` index that backs the DELETE.
2. **Made the `apply-sentry-infra.yml` `-target=` allowlist edit explicit and load-bearing**
   (verified at line ~187): without it the new `sentry_cron_monitor` is never applied. Added a
   dedicated AC + Files-to-Edit entry.
3. **Verify-the-negative pass confirmed:** `messages` has no Realtime consumer (already dropped),
   `action_sends` HAS one (`leader-loop-status.tsx:9` — correctly kept), and the
   `SENTRY_MONITOR_SLUG`-matches-`name` invariant holds against the cert-state precedent.

### New Considerations Discovered
- The three mandatory deepen gates (User-Brand Impact 4.6, Observability 4.7, PAT-shaped 4.8)
  all PASS.
- Diagnosis is empirically **write-driven** (cache hit = 100.000%) — re-confirms the 2026-05-06
  learning that read-index work is wasted at this scale.
- The Supabase Management API has NO disk-IO metric endpoint; `pg_stat_io` via the SQL
  `database/query` endpoint is the deterministic signal the monitor must use.

## Summary

Supabase sent a fresh Disk IO Budget depletion warning for prod `soleur-web-platform`
(`ifsccnjhymdmidffkzhl`). A prior remediation already shipped (issue #3358, migrations
038 + 039, merged 2026-05-06) and **held** — live diagnostics confirm the sweep is at
`*/15` and `public.messages` is out of the Realtime publication. The new warning is
driven by **two NEW write-side cost-centers that emerged AFTER the prior fix**, plus the
structural Realtime baseline that the prior fix could only partially mitigate. The third
deliverable — a **proactive monitor that detects high Disk IO before the budget depletes** —
was never built (the prior PR #3389 shipped two one-shot `--once` recheck workflows that
have since been deleted).

Three deliverables:

1. **Diagnose (done — evidence in this plan).** Live `pg_stat_io` shows **cache hit = 100.000%**
   (460M hits / 34 disk reads), so the budget burn is **WRITE-driven**, not read-driven. The
   write drivers, in order: (a) the application-side **stuck-active reaper polling
   `find_stuck_active_conversations` every 60 s** (#2 query: 760 k ms / 38 009 calls), (b)
   **`public.processed_github_events` growing unbounded** with no retention sweep (#3 query:
   338 k ms / 65 075 inserts; 65 086 live rows, 0 deletes), and (c) the **Realtime WAL parser**
   baseline (#1 query, structural, already mitigated as far as feasible at 2026-05-06).

2. **Fix.** (a) Widen the stuck-active reaper poll cadence from 60 s → 300 s in
   `agent-runner.ts` (the 120 s staleness threshold is independent of poll cadence, exactly
   as the migration-038 cron-cadence change was). (b) Add a `pg_cron` retention sweep on
   `public.processed_github_events` (the migration-030 sibling for `processed_stripe_events`
   explicitly deferred this "to a follow-up issue" — this is that follow-up). The new sweep
   itself runs daily, NOT per-minute, so it does not re-introduce cron-plumbing churn.

3. **Monitor.** Add an **Inngest cron** (`cron-supabase-disk-io`) that polls the Supabase
   Management API SQL endpoint for a deterministic write-pressure signal (`pg_stat_io`
   checkpointer/backend writes delta + top-write-churn tables + Realtime call rate),
   applies a threshold verdict rule, files/auto-closes a GitHub issue on trip/recovery,
   and posts a Sentry heartbeat — mirroring the established `cron-gh-pages-cert-state`
   pattern. A `sentry_cron_monitor` Terraform resource registers its liveness. This is a
   PROACTIVE early-warning monitor (Disk IO is a Supabase metric, not in Sentry's event
   store, so a Sentry metric-alert cannot see it — the cron-polls-then-emits shape is the
   only one that works).

## Context

- **Project ref:** `ifsccnjhymdmidffkzhl` (prod, eu-west-1, Micro compute tier — only
  `custom_domain` add-on, no compute add-on; baseline disk IO budget applies).
- **Prior art (premise validation, see below):** issue #3358 CLOSED by PRs #3389 + #3738;
  plan `knowledge-base/project/plans/2026-05-06-fix-supabase-disk-io-cron-realtime-plan.md`;
  brainstorm `knowledge-base/project/brainstorms/2026-05-06-supabase-disk-io-budget-brainstorm.md`;
  spec `knowledge-base/project/specs/feat-supabase-disk-io-budget/`.
- **Diagnostic learnings (directly load-bearing):**
  - `knowledge-base/project/learnings/2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md`
    (diagnostic ordering: pull `cron.job` + Realtime publication + `pg_stat_statements`
    BEFORE business queries; structural plumbing dominates at low scale).
  - `knowledge-base/project/learnings/2026-05-06-supabase-management-api-bypasses-mcp-oauth.md`
    (use Doppler `SUPABASE_ACCESS_TOKEN` (prd) + `api.supabase.com/v1/projects/<ref>/database/query`
    REST, NOT the MCP OAuth flow, NOT `psql`).
- **Established pattern to mirror for the monitor:**
  `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts` (Inngest cron →
  check → file/close GitHub issue → `postSentryHeartbeat`) plus
  `apps/web-platform/server/inngest/functions/_cron-shared.ts` (`postSentryHeartbeat`,
  `HandlerArgs`) and `apps/web-platform/infra/sentry/cron-monitors.tf` (Terraform
  `sentry_cron_monitor`).

## Premise Validation

Checked the references the task cites or implies. **The premise is partially stale and this
materially reshapes the plan:**

- **Issue #3358** ("feat: Supabase prod Disk IO Budget remediation (cron + Realtime audit)")
  is **CLOSED**, closed by merged PRs **#3389** + **#3738**. So "fix the Disk IO problem" is
  NOT a fresh build — a remediation already shipped.
- **Live verification (2026-06-02)** confirms the prior fix HELD: `user_concurrency_slots_sweep`
  is `*/15` (not the original `* * * * *`), and `public.messages` is OUT of the
  `supabase_realtime` publication. So the recurrence is NOT a regression of the prior fix.
- The recurrence is driven by **NEW cost-centers** (stuck-active reaper poll + unbounded
  `processed_github_events`) that did not dominate in the 2026-05-06 window. The plan targets
  those, not the already-fixed cron/publication levers.
- **The "Sentry monitor + alert" deliverable was never built.** PR #3389 shipped two one-shot
  `--once` recheck GitHub Actions workflows (`scheduled-disk-io-24h-recheck.yml`,
  `scheduled-disk-io-7d-recheck.yml`) which have since been DELETED (not present on main).
  There is no standing proactive Disk-IO monitor today. This deliverable is genuinely new.

## Live Diagnostics (captured 2026-06-02 via Supabase Management API)

`pg_stat_statements` window age: stats last reset **2026-05-06 20:53 UTC** (the prior-fix
reset). So the totals below are cumulative over ~27 days since the fix.

**Top consumers by `total_exec_time`:**

| # | total_ms | calls | mean_ms | blk_read | blk_hit | query (truncated) |
|---|---|---|---|---|---|---|
| 1 | 1 545 816 | 273 250 | 5.66 | 0 | 427 M | Realtime WAL parser (`SELECT wal->>...`) — structural ~100 ms polling |
| 2 | 760 004 | 38 009 | 20.00 | 2 | 25 M | PostgREST RPC w/ `p_threshold_seconds` = **`find_stuck_active_conversations`** |
| 3 | 338 075 | 65 075 | 5.20 | 2 | 1.0 M | **`INSERT INTO public.processed_github_events`** |
| 4 | 174 675 | 220 595 | 0.79 | 0 | 1.2 M | `set_config(...)` PostgREST session setup (per-request overhead) |
| 5 | 135 325 | 492 | 275.05 | 0 | 340 k | publication-tables introspection (Realtime broker) |
| 6 | 108 901 | 150 | 726.01 | 0 | 0 | `SELECT name FROM pg_timezone_names` (Studio dashboard) |

**`pg_stat_io` (the decisive signal):** cache hit rate = **100.000 %** (460 388 773 hits /
**34** disk block reads). The IO budget burn is therefore **almost entirely WRITES**:
checkpointer wrote 117 425 blocks; client/standalone/autovacuum backends are minor. Reads
are not the problem — indexing user queries would again be wasted effort (same conclusion
as the 2026-05-06 learning, re-confirmed empirically).

**Write churn (`pg_stat_user_tables`):**

| table | ins | upd | del | live | dead |
|---|---|---|---|---|---|
| `public.processed_github_events` | **65 089** | 0 | **0** | **65 086** | 3 |
| `public.user_concurrency_slots` | 72 | 1 253 | 72 | 0 | 38 |
| `realtime.subscription` | 426 | 11 | 426 | 0 | 17 |
| `public.messages` | 290 | 332 | 120 | 170 | 0 |
| `public.conversations` | 115 | 562 | 37 | 75 | 2 |

**`cron.job` (live):** 7 jobs, all reasonable cadence — `user_concurrency_slots_sweep` is
`*/15` (prior fix held), DSAR/tenant/workspace retention sweeps are hourly/daily. **No
`processed_github_events` retention job exists.**

**Realtime publication (live):** `public.conversations` + `public.action_sends`. (Note:
`action_sends` was ADDED post-fix by migration 070 — it has real production consumers in
`apps/web-platform/components/dashboard/` + `app/api/dashboard/today/`, so it stays. The
prior-fix removal of `public.messages` held.)

## Research Reconciliation — Spec vs. Codebase

This branch has no spec; the "spec" is the one-shot argument. The relevant reconciliation
is against the PRIOR plan's assumptions, which have drifted:

| Prior-plan / argument claim | Reality (verified 2026-06-02) | Plan response |
|---|---|---|
| Argument: "review and diagnose root cause … (query patterns, missing indexes, …)." | Cache hit = 100 %; ZERO read pressure. Missing indexes are irrelevant. Burn is WRITE-side. | Diagnosis is write-driven; remediation targets write volume, not read indexes. |
| Prior plan: Realtime WAL parser is the #1 cost (mitigated by dropping `messages`). | Still #1 (273 k calls) but `messages` IS out of the publication. The remaining baseline is `conversations`+`action_sends`, both with real consumers. | Do NOT touch the publication. Realtime baseline is irreducible without removing a live feature. Treat as accepted structural floor; the monitor watches it. |
| Prior plan implied cron-plumbing was the #2-#4 write cluster. | At 2026-06-02 the #2/#3 are NEW: the stuck-active reaper RPC + unbounded `processed_github_events`. The cron-plumbing dropped after the `*/15` change. | New cost-centers; new fixes (reaper cadence + GH-events retention). |
| Migration 030 sibling: "`processed_stripe_events` retention … pg_cron-based sweep tracked separately (follow-up issue)." | The GitHub-events dedup table (`processed_github_events`, written by `app/api/webhooks/github/route.ts`) was created with the SAME "prunable, sweep deferred" note and the sweep was NEVER added. 65 086 rows and climbing. | This plan IS that follow-up sweep, for the GitHub table. (Check whether `processed_stripe_events` ALSO lacks a sweep and fold in if so — see Phase 2.) |
| Argument: "add a Sentry monitor + alert." | Sentry has no Disk-IO data; a `sentry_metric_alert` cannot fire on a Supabase metric. The Management API has NO stable `disk_io_budget` metric endpoint (probed: `infra-monitoring/metrics`, `daily-stats`, `usage` all 404). The SQL `database/query` endpoint DOES expose `pg_stat_io` + churn deterministically. | Monitor = Inngest cron polling SQL signal → threshold verdict → Sentry heartbeat + GH issue. NOT a Sentry metric-alert. |

## User-Brand Impact

**If this lands broken, the user experiences:** prod Supabase backs every authenticated
session (chat history, conversation state, billing-tied API keys, dashboard today-cards).
Specific failure modes: (a) if the stuck-active reaper cadence widening is botched and the
reaper stops entirely, stuck "active" conversations linger and block the per-user
concurrency slot → user cannot start a new agent run; (b) if the `processed_github_events`
retention sweep deletes rows INSIDE the replay window, a re-delivered GitHub webhook is
re-processed (double-effect — e.g. a duplicate repo-connect); (b2) [added at review per
user-impact Finding 3] the work-time-folded `processed_stripe_events` sweep touches the
PAYMENT dedup surface — if it deleted a row inside Stripe's replay window a re-delivered
Stripe event could double-process (incorrect/duplicate charge), the highest-severity
artifact class. Scoped out as safe: the 90-day sweep window EQUALS Stripe's documented
replay window (migration 030:12), so the DELETE never crosses the replay boundary; (c) if
the monitor's threshold is mis-tuned it either pages constantly (alert fatigue) or stays
silent through a real depletion (the exact failure this feature exists to prevent).

**If this leaks, the user's data is exposed via:** the monitor queries prod via the
Management API and folds query output into a Sentry event + a public GitHub issue body.
The diagnostic queries return only aggregate counts + normalized query TEXT (parameterized,
no literals) + table names — no row data, no PII. The issue/Sentry payload MUST be
restricted to those shapes (enforced in Phase 3 + AC).

**Brand-survival threshold:** `single-user incident`. CPO sign-off required at plan time
before `/work`. `user-impact-reviewer` runs at review time.

## Implementation Phases

### Phase 1 — Widen the stuck-active reaper poll cadence (60 s → 300 s)

**File to edit:** `apps/web-platform/server/agent-runner.ts`

`STUCK_ACTIVE_CHECK_INTERVAL_MS = 60 * 1_000` (line ~732) drives a `setInterval` that calls
`find_stuck_active_conversations` (migration 037) every 60 s — 38 009 calls / 760 004 ms
cumulative, the #2 IO consumer. The `STUCK_ACTIVE_THRESHOLD_SECONDS = 120` staleness window
(line ~731) is INDEPENDENT of the poll cadence: a conversation that goes stuck is reaped
within `threshold + cadence` worst-case. Widening cadence to 300 s changes worst-case reap
latency from 120-180 s to 120-420 s — still well under any user-visible expectation
(stuck-active is a rare recovery path, not a hot path), and cuts the RPC call volume 5×.

Change:

```ts
// agent-runner.ts (~line 732)
// Was: 60 s. Widened to 300 s to cut find_stuck_active_conversations RPC volume
// 5× (the #2 prod Disk-IO consumer, 2026-06-02). The 120 s STUCK_ACTIVE_
// THRESHOLD_SECONDS staleness window is independent of poll cadence — worst-case
// reap latency rises 180 s → 420 s, still far under any user expectation for this
// rare recovery path. See plan 2026-06-02-fix-supabase-disk-io-recurrence-and-
// sentry-monitor-plan.md Phase 1.
const STUCK_ACTIVE_CHECK_INTERVAL_MS = 300 * 1_000;
```

**Sharp edge / verify at /work:** the comment block at `agent-runner.ts:726` and the
mirror at `ws-handler.ts:457` enumerate FOUR co-locked threshold sources. Confirm this edit
touches ONLY the poll cadence (`STUCK_ACTIVE_CHECK_INTERVAL_MS`), NOT the 120 s threshold
(`STUCK_ACTIVE_THRESHOLD_SECONDS` / migration 037 default / `p_threshold_seconds`). The
threshold must stay 120 s on all four sources. `grep -rn "STUCK_ACTIVE_CHECK_INTERVAL_MS\|STUCK_ACTIVE_THRESHOLD_SECONDS"
apps/web-platform/server` before and after to prove only the interval constant moved.

**Test:** extend/add a unit test asserting `STUCK_ACTIVE_CHECK_INTERVAL_MS === 300_000` and
`STUCK_ACTIVE_THRESHOLD_SECONDS === 120` (regression pin so a future edit cannot silently
re-couple them). Use the existing agent-runner test surface — `grep -rn
"STUCK_ACTIVE" apps/web-platform/test` to find it; if none exists, add a focused constant
test in `apps/web-platform/test/server/`.

### Phase 2 — Add a daily `pg_cron` retention sweep on `public.processed_github_events`

**File to create:** `apps/web-platform/supabase/migrations/093_processed_github_events_retention.sql`
(verify the next free number at /work — `ls apps/web-platform/supabase/migrations/ | tail`;
092 is the current max, so 093 is expected, but re-check for collisions per the migration-
number-collision learning).

Mirror the existing daily-retention cron pattern already in prod (jobids 4-8, e.g.
migration 063's `purge_workspace_member_actions` and migration 076's
`workspace_activity` 90-day purge). The dedup table only needs rows for the webhook replay
window — GitHub re-delivers within a small window (hours), but match the conservative
posture of the Stripe sibling note (90 d) unless the webhook handler documents a shorter
window. Sweep runs ONCE daily (`0 4 * * *`), so it adds 3 cron-plumbing writes/day — net IO
WIN vs. the unbounded table.

```sql
-- 093_processed_github_events_retention.sql
--
-- Add the daily retention sweep that migration 030's processed_stripe_events
-- comment deferred "to a follow-up issue" but for the GitHub dedup table
-- (public.processed_github_events, written by app/api/webhooks/github/route.ts).
-- At 2026-06-02 the table had 65 086 live rows, 0 deletes, and was the #3 prod
-- Disk-IO consumer (INSERT path). Rows older than the webhook replay window are
-- prunable; 90 d matches the Stripe sibling's stated replay horizon.
--
-- The sweep runs ONCE daily (0 4 04:00 UTC), joining the existing 04:00 cohort
-- (jobids 5/6/7). One daily run = 3 cron.job_run_details writes/day — negligible
-- vs. the unbounded INSERT growth it bounds. Idempotent: cron.unschedule guard
-- before cron.schedule, mirroring migration 029/038.
--
-- See: knowledge-base/project/plans/2026-06-02-fix-supabase-disk-io-recurrence-and-sentry-monitor-plan.md
-- Issue: #<TBD>

DO $cron_block$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'processed_github_events_retention') THEN
    PERFORM cron.unschedule('processed_github_events_retention');
  END IF;
  PERFORM cron.schedule(
    'processed_github_events_retention',
    '0 4 * * *',
    $$DELETE FROM public.processed_github_events WHERE received_at < now() - interval '90 days'$$
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $cron_block$;
```

> **[deepen 2026-06-02] Verified against migration 052 `multi_source_dedup.sql:126-137`:** the
> table is `public.processed_github_events (delivery_id text PRIMARY KEY, received_at timestamptz
> NOT NULL DEFAULT now())`. The timestamp column is **`received_at`** (NOT `created_at` — the
> earlier draft was wrong; an example using `created_at` would fail at deploy with `column
> "created_at" does not exist`). A matching index already exists:
> `processed_github_events_received_at_idx ON ... (received_at DESC)` — the DELETE predicate is
> index-backed, no new index needed. The `DO $cron_block$ ... EXCEPTION WHEN duplicate_object
> THEN NULL; END` shape is copied verbatim from migration 076's `workspace_activity_purge`
> (the closest daily-retention-cron precedent).

**Verify at /work, before writing the SQL:**
1. ~~Confirm the timestamp column~~ DONE at deepen: column is `received_at` (mig 052:128).
   Use `received_at`; the index `processed_github_events_received_at_idx` already covers it.
2. Confirm the GitHub webhook **replay window** from `app/api/webhooks/github/route.ts` — if
   the handler documents a window shorter than 90 d, use that (smaller = more IO savings,
   but never shorter than the replay horizon or dedup breaks). Cite the source line in the
   migration comment.
3. **Fold-in check:** `git grep -n "processed_stripe_events" apps/web-platform/supabase/migrations/`
   — if the Stripe dedup table STILL lacks a retention sweep (the 030 comment suggests it
   does), add a sibling DELETE in the SAME migration (it is the same class, same deferred
   follow-up). Confirm `processed_stripe_events` live-row count via the Management API; if
   non-trivial, fold in. If trivial/empty, acknowledge in the migration comment and skip.
4. Per the Supabase-migration-transaction Sharp Edge: this migration is plain
   `DELETE`/`cron.schedule` (transaction-safe). No `CONCURRENTLY`/`VACUUM`. Read migrations
   063 + 076 (the closest sibling retention crons) and mirror their exact `DO $$` shape.

**Test:** add `apps/web-platform/test/supabase-migrations/093-processed-github-events-retention.test.ts`
mirroring `038-039-disk-io-fix.test.ts` (readFileSync + comment-strip + regex): assert the
`cron.unschedule` guard, the `0 4 * * *` cadence, the `DELETE FROM public.processed_github_events`
target, and the `interval '90 days'` (or the chosen window) predicate. Run via the package's
configured runner (`grep "scripts" apps/web-platform/package.json` → vitest; the test path
must satisfy `apps/web-platform/vitest.config.ts` `include:` globs — `test/**/*.test.ts` is
the node project, which `test/supabase-migrations/*.test.ts` already satisfies).

### Phase 3 — Add the proactive Disk-IO monitor (Inngest cron + Sentry heartbeat)

**Files to create:**
- `apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts`
- `apps/web-platform/test/server/inngest/cron-supabase-disk-io.test.ts`

**Files to edit:**
- `apps/web-platform/server/inngest/cron-manifest.ts` (add `"cron-supabase-disk-io"` to
  `EXPECTED_CRON_FUNCTIONS`, alphabetically — between `cron-strategy-review` and
  `cron-terraform-drift`; the `function-registry-count` test asserts the manifest equals the
  `cron-*.ts` file list, so this edit is MANDATORY or CI fails).
- `apps/web-platform/app/api/inngest/route.ts` (import `cronSupabaseDiskIo` and add it to
  the `functions:` array passed to `serve`, mirroring the `cronGhPagesCertState` lines 34 + 92).
- `apps/web-platform/infra/sentry/cron-monitors.tf` (add the `sentry_cron_monitor` resource).

**Monitor design (mirror `cron-gh-pages-cert-state.ts`):**

```ts
// cron-supabase-disk-io.ts — proactive prod Disk-IO early-warning monitor.
//
// Polls the Supabase Management API SQL endpoint (NOT a metric endpoint — none
// exists for disk_io_budget; probed 2026-06-02) for a deterministic write-
// pressure signal, applies a threshold verdict, files/auto-closes a GitHub
// issue, and posts a Sentry heartbeat. Mirrors cron-gh-pages-cert-state.ts.
//
// SIGNAL: two SQL probes via api.supabase.com/v1/projects/<ref>/database/query:
//   (a) cache_hit_pct + total disk block reads from pg_stat_statements (a
//       read-pressure regression would show cache_hit_pct dropping below ~99%);
//   (b) write-churn delta: top public.* tables by (n_tup_ins+n_tup_upd+n_tup_del)
//       from pg_stat_user_tables, and Realtime WAL parser call count from
//       pg_stat_statements. The monitor stores the prior sample's counters in
//       /var/lib/inngest/disk-io/last.json (same dir pattern as postSentryHeartbeat's
//       /var/lib/inngest/cron-fires) and computes a per-interval RATE.
//
// VERDICT (deterministic, no dashboard eyeballing — hr-no-dashboard-eyeball):
//   tripped = (cache_hit_pct < CACHE_HIT_FLOOR_PCT)               // read regression
//          OR (writeChurnRatePerHour > WRITE_CHURN_RATE_CEIL)     // write regression
//          OR (realtimeCallsPerHour  > REALTIME_CALL_RATE_CEIL)   // Realtime regression
//          OR (anyTableLiveRows      > UNBOUNDED_TABLE_ROW_CEIL)  // unbounded-growth guard
//   Thresholds are constants tuned from the 2026-06-02 baseline with headroom
//   (see Phase 3 threshold-calibration note). Each is independently reported in
//   the Sentry extra + issue body so the operator sees WHICH lever tripped.
```

Handler shape (verbatim structural mirror of `cron-gh-pages-cert-state.ts`):
`step.run("read-disk-io-signal")` (the SQL probes via `fetch` to the Management API) →
`step.run("issue-handling")` (file new / comment-on-existing on trip; comment + close on
recovery, keyed on an `[disk-io]` title prefix, same as the `[cert-poll]` pattern) →
`step.run("sentry-heartbeat")` calling `postSentryHeartbeat({ ok: !tripped, sentryMonitorSlug:
"scheduled-supabase-disk-io", cronName: "cron-supabase-disk-io", logger })`.

Registration: `inngest.createFunction({ id: "cron-supabase-disk-io", concurrency: [...],
retries: 1 }, [{ cron: "0 */6 * * *" }, { event: "cron/supabase-disk-io.manual-trigger" }],
handler)` — 6-hourly is frequent enough for early warning on a budget that depletes over
hours-to-days, infrequent enough to add negligible IO itself (4 lightweight read-only SQL
calls/run).

**Secret / env (verify at /work):** the handler needs `SUPABASE_ACCESS_TOKEN` + the project
ref at runtime. `SUPABASE_ACCESS_TOKEN` currently lives ONLY in Doppler `prd` config, NOT
in the app-runtime config (`prd_web_platform` returned absent). **This is a real gap** —
the Inngest cron runs in the web-platform container, which is fed by the app-runtime config.
Resolve via the IaC gate (see Infrastructure (IaC) section): the token must be provisioned
into the app-runtime Doppler config via the existing secret-provisioning Terraform, NOT an
operator CLI write. The project ref (`ifsccnjhymdmidffkzhl`) can be a non-secret env
constant. Confirm the exact app-runtime config name + how secrets reach the container
(`grep -rn "SUPABASE_ACCESS_TOKEN\|doppler" apps/web-platform/infra/*.tf` and the deploy
pipeline) before prescribing the wiring.

**Threshold calibration (deterministic, from baseline):** the 2026-06-02 baseline over a
27-day window: cache_hit_pct = 100.000, processed_github_events = 65 086 live rows (the
unbounded outlier), Realtime ~273 k calls / 27 d ≈ 421/hr. Set constants with headroom:
`CACHE_HIT_FLOOR_PCT = 98.0`, `UNBOUNDED_TABLE_ROW_CEIL = 100_000` (catches a retention
regression on processed_github_events BEFORE it re-depletes IO), `REALTIME_CALL_RATE_CEIL`
and `WRITE_CHURN_RATE_CEIL` = ~3× baseline. Record the exact baseline numbers + the chosen
multipliers in the handler as a comment so the next tuner has the provenance. These are
honest early-warning tripwires, not the budget gauge itself (which the API does not expose).

**Test:** `cron-supabase-disk-io.test.ts` mirrors the cert-state test approach — drive the
verdict function with synthesized signal fixtures (cache_hit below floor → tripped;
unbounded rows above ceil → tripped; all-green baseline → ok) WITHOUT a live DB or live
Sentry. Inject the SQL-fetch + octokit at the boundary (the cert-state test pattern uses an
injectable octokit). Assert the verdict is computed deterministically and the per-lever
detail strings are present.

### Phase 4 — Sentry cron monitor Terraform resource

**File to edit:** `apps/web-platform/infra/sentry/cron-monitors.tf`

Add (mirror the Inngest-fired precedent block, e.g. `scheduled_stale_deferred_scope_outs`):

```hcl
# cron-supabase-disk-io (issue #<TBD>): Inngest-fired via
# apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts.
# Proactive prod Disk-IO early-warning monitor. 6-hourly (0 */6 * * *) —
# 30-min margin per the Inngest <=2-min-jitter precedent. A MISSED check-in
# means the monitor stopped (scheduler dead / function dropped); a ?status=error
# heartbeat means the monitor RAN and a write/read/Realtime tripwire fired.
# Single-miss alert (failure_issue_threshold = 1). 10 min mirrors the small-cron
# cohort (pure-TS, 4 read-only SQL calls, no claude-eval spawn).
resource "sentry_cron_monitor" "scheduled_supabase_disk_io" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-supabase-disk-io"
  schedule                = { crontab = "0 */6 * * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

Per the `target-allowlist-extension-must-sweep-all-guard-suites` Sharp Edge: the Sentry
infra has a `-target=` apply allowlist. **[deepen 2026-06-02 verified]** the allowlist is an
explicit per-resource list at `.github/workflows/apply-sentry-infra.yml:187+` (one
`-target=sentry_cron_monitor.<name> \` line per monitor). Add
`-target=sentry_cron_monitor.scheduled_supabase_disk_io \` to that list — this is the
LOAD-BEARING edit: without it the new monitor's Terraform resource is never applied even
though it exists in `cron-monitors.tf`. At /work also `git grep -ln 'sentry_cron_monitor'
apps/web-platform/infra .github/workflows` to confirm no separate destroy scope-guard
enumerates monitors by name (none found at deepen — `apply-deploy-pipeline-fix.yml` and
`apply-web-platform-infra.yml` matched the grep but are unrelated roots). The slug
`scheduled-supabase-disk-io` MUST match `SENTRY_MONITOR_SLUG` in the handler exactly.

## Files to Create

- `apps/web-platform/supabase/migrations/093_processed_github_events_retention.sql` (+ its `.down.sql`)
- `apps/web-platform/test/supabase-migrations/093-processed-github-events-retention.test.ts`
- `apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts`
- `apps/web-platform/test/server/inngest/cron-supabase-disk-io.test.ts`

## Files to Edit

- `apps/web-platform/server/agent-runner.ts` (reaper poll cadence 60 s → 300 s)
- `apps/web-platform/server/inngest/cron-manifest.ts` (add `cron-supabase-disk-io`)
- `apps/web-platform/app/api/inngest/route.ts` (register `cronSupabaseDiskIo`)
- `apps/web-platform/infra/sentry/cron-monitors.tf` (new `sentry_cron_monitor`)
- `.github/workflows/apply-sentry-infra.yml` (add `-target=sentry_cron_monitor.scheduled_supabase_disk_io` to the allowlist at line ~187 — LOAD-BEARING, verified at deepen)
- Possibly a stuck-active reaper constant test under `apps/web-platform/test/server/`

## Open Code-Review Overlap

To be populated at /work after the file list is final: run
`gh issue list --label code-review --state open --json number,title,body --limit 200`
and `jq` each Files-to-Edit path against the bodies (two-stage form). Record `None` if no
matches. Candidate-adjacent: prior #3372 (120 s threshold tautology — DO NOT re-couple the
threshold; this plan only moves the poll cadence), #3370 (dev `_schema_migrations` drift —
prod clean, verified 2026-06-02). Acknowledge both; neither blocks.

## Work-Time Deviations (2026-06-02)

Two load-bearing deviations from the plan, both validated:

1. **Migration numbering 093 → 094 + 095.** At /work-start `origin/main` had advanced
   and already contained `093_acquire_slot_workspace_id.sql` (a sibling PR merged after the
   worktree was created). Per the migration-number-collision check, the branch was rebased
   onto fresh origin/main and the retention sweep took **094** + the signal RPC took **095**
   (split into two focused migrations). 093 in the plan prose now reads 094/095.

2. **Monitor signal source: SECURITY DEFINER RPC, NOT the Supabase Management API.** The
   plan's Risk 4 flagged that `SUPABASE_ACCESS_TOKEN` is not in the app-runtime Doppler
   config. Verified true (`grep` found it only in a script). Rather than provision a
   high-privilege account-scoped PAT into the web container (a security downgrade), the
   monitor reads `pg_stat_database` + `pg_stat_user_tables` via a read-only
   `disk_io_pressure_signal()` SECURITY DEFINER RPC (migration 095), called through the
   existing service-role client (`createServiceClient`, already in the runtime; same posture
   as `cron-workspace-sync-health`). This eliminates the token-provisioning blocker entirely
   and was verified end-to-end against dev (create + call + rollback; returned cache_hit_pct
   + dedup row counts + top-write-churn). The cache-hit signal uses `pg_stat_database`
   (no `pg_stat_statements` extension dependency → reset-tolerant). The verdict is stateless
   (cache-hit floor + dedup-row ceiling), so no `/var/lib` last-sample file is needed —
   the plan's rate-based write-churn lever was dropped in favour of the two high-signal
   stateless tripwires that directly detect the failure modes this feature fixes.

3. **Stripe dedup sweep folded in.** Per the Phase 2 fold-in check: `processed_stripe_events`
   live-row count confirmed trivial (1 row) but it carries the same migration-030 deferred
   debt, so a sibling 90-day sweep on `processed_at` was folded into migration 094.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `agent-runner.ts` `STUCK_ACTIVE_CHECK_INTERVAL_MS === 300_000` AND
      `STUCK_ACTIVE_THRESHOLD_SECONDS === 120` (regression-pin test `agent-runner-reaper-cadence.test.ts`
      asserts ONLY the interval moved; threshold stays 120 s).
- [x] Migration `094_dedup_tables_retention.sql` exists with a `cron.unschedule` idempotent guard,
      `0 4 * * *` cadence, `DELETE FROM public.processed_github_events` (received_at) + the folded-in
      `processed_stripe_events` (processed_at), 90-day interval; `.down.sql` `cron.unschedule`s both jobs.
      Validated against dev via a rolled-back transaction (HTTP 201).
- [x] Migration tests pass via vitest (094 + 095 shape tests; `migration-rpc-grants` lint green).
- [x] `cron-supabase-disk-io.ts` exists, registered in BOTH `cron-manifest.ts`
      (`EXPECTED_CRON_FUNCTIONS`) and `app/api/inngest/route.ts` (`functions:` array, count 44→45).
- [x] `function-registry-count` test green (manifest == cron-*.ts file list; route count; tf↔workflow lockstep).
- [x] `cron-supabase-disk-io.test.ts` green: verdict trips on cache_hit < floor, on unbounded rows > ceil,
      stays ok on baseline; per-lever reasons present (a null-signal false-trip bug was caught + fixed).
- [x] `sentry_cron_monitor.scheduled_supabase_disk_io` added to `cron-monitors.tf` with slug
      matching the handler's `SENTRY_MONITOR_SLUG` (`scheduled-supabase-disk-io`); no separate
      destroy scope-guard enumerates monitors by name (grep-confirmed).
- [x] `apply-sentry-infra.yml` includes `-target=sentry_cron_monitor.scheduled_supabase_disk_io`
      in its allowlist (registry test (f) enforces lockstep).
- [x] `terraform validate` green in `apps/web-platform/infra/sentry/` (pre-existing sentry_alert
      deprecation warnings only, unrelated to this resource).
- [x] `tsc --noEmit` green; full web-platform vitest suite green (8037 passed).
- [ ] PR body: `Ref #<issue>` (NOT `Closes` — `classification: ops-only-prod-write`; the
      issue closes post-merge after the 7-day budget-recovery verification). — handled at /ship.
- [ ] Diagnostic before-snapshot pasted into PR body. — handled at /ship.
- [ ] CPO sign-off on User-Brand Impact (PR comment). `user-impact-reviewer` passes at review.

### Post-merge (operator — automate where feasible per hr-no-dashboard-eyeball)

- [ ] `web-platform-release.yml#migrate` green; migration 093 applied. Verify via Management
      API (`mcp__plugin_supabase_supabase__*` or REST):
      `SELECT jobname, schedule FROM cron.job WHERE jobname = 'processed_github_events_retention';`
      returns `0 4 * * *`.
- [ ] `apply-sentry-infra.yml` applied the new `sentry_cron_monitor` (auto on push to main);
      `gh api`/Sentry Crons list shows `scheduled-supabase-disk-io`.
- [ ] Fire the monitor once via the manual-trigger path (`/soleur:trigger-cron` →
      `cron/supabase-disk-io.manual-trigger`) and confirm it posts an `ok` heartbeat AND
      files no false-positive issue against the healthy baseline.
- [ ] Reaper cadence verified live: the `find_stuck_active_conversations` call rate drops ~5×
      in `pg_stat_statements` over the following 24 h (re-pull via Management API; do NOT
      eyeball the dashboard).
- [ ] **7 days later:** Disk IO Budget gauge is RECOVERING (climbing toward full), not just
      stable. `gh issue close <issue>` only after the 7-day verification, with a comment
      summarizing the before/after deltas.

## Risks

1. **Reaper cadence widening delays stuck-active recovery.** Worst-case reap latency rises
   180 s → 420 s. Mitigation: stuck-active is a rare recovery path; the slot is still
   reclaimed automatically. If the operator observes user-reported "can't start a run" the
   cadence is a one-line revert. NO change to the 120 s staleness threshold.
2. **Retention sweep deletes inside the webhook replay window → duplicate processing.**
   Mitigation: 90 d window >> GitHub's hours-scale re-delivery horizon; verify the handler's
   documented window at /work and never go below it.
3. **Monitor threshold mis-tuned.** Too tight → alert fatigue; too loose → silent through a
   real depletion. Mitigation: thresholds calibrated from the 2026-06-02 baseline with
   explicit headroom multipliers, each lever independently reported so a noisy lever is
   identifiable and tunable without touching the others.
4. **`SUPABASE_ACCESS_TOKEN` not in app-runtime Doppler config.** The cron runs in the
   container; the token is currently only in `prd`. Mitigation: provision via the IaC gate
   (Infrastructure (IaC) section), NOT an operator CLI write. If wiring is infeasible this
   cycle, the monitor must FAIL LOUD (Sentry warn) on a missing token rather than silently
   no-op — encode that in the handler's env guard (mirror `postSentryHeartbeat`'s "env unset
   → log + skip" but escalate to a WARN since a missing token defeats the monitor's purpose).
5. **Realtime baseline is irreducible.** `conversations` + `action_sends` both have live
   consumers. The monitor watches it; it is not further remediated here. A future compute
   add-on bump (#3360, deferred) is the lever if the baseline alone ever exceeds budget.
6. **`pg_stat_statements` reset resets the monitor's read-pressure baseline.** If an operator
   runs `pg_stat_statements_reset()`, the cumulative-counter probes restart from zero. The
   monitor's rate computation (delta vs. last sample) is reset-tolerant (a negative delta is
   clamped to "treat as fresh window"); encode that guard in the handler.

## Observability

```yaml
liveness_signal:
  what: cron-supabase-disk-io posts a Sentry Crons check-in every run
  cadence: "0 */6 * * * (6-hourly, UTC)"
  alert_target: Sentry cron monitor scheduled-supabase-disk-io (failure_issue_threshold=1)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf
error_reporting:
  destination: Sentry (postSentryHeartbeat status=error) plus a GitHub [disk-io] issue
  fail_loud: yes — missing SUPABASE_ACCESS_TOKEN escalates to a Sentry WARN (Risk 4), not a silent skip
failure_modes:
  - mode: monitor stops running (scheduler dead / function dropped)
    detection: missed Sentry check-in (30-min margin)
    alert_route: Sentry cron monitor opens an issue
  - mode: write/read/Realtime tripwire fires (early-warning of IO pressure)
    detection: deterministic verdict in the handler (cache_hit floor / churn+Realtime+row ceilings)
    alert_route: status=error heartbeat (red monitor) plus GitHub [disk-io] issue with the tripped lever
  - mode: unbounded table regression (retention cron stopped)
    detection: UNBOUNDED_TABLE_ROW_CEIL on pg_stat_user_tables live rows
    alert_route: same as above; issue names the table
logs:
  where: app pino to Better Stack (handler logger.info/warn); Sentry for errors
  retention: Better Stack standard retention
discoverability_test:
  command: "curl -sS -X POST $MGMT_API/database/query -d query=pg_stat_statements-cache-hit-pct (NO ssh) — the same probe the monitor runs"
  expected_output: a cache_hit_pct number (~100.0 healthy)
```

## Infrastructure (IaC)

### Terraform changes
- `apps/web-platform/infra/sentry/cron-monitors.tf` — new `sentry_cron_monitor.scheduled_supabase_disk_io`.
- Provider: `jianyuan/sentry` `0.15.0-beta2` (already pinned). Vars: `var.sentry_org`,
  `data.sentry_project.web_platform.slug` (already declared).
- `SUPABASE_ACCESS_TOKEN` for the app-runtime container: must be wired into the app-runtime
  Doppler config via the existing secret-provisioning IaC (confirm mechanism at /work —
  `grep -rn "SUPABASE\|doppler" apps/web-platform/infra/*.tf` and the deploy pipeline). This
  must go through the IaC secret-provisioning path, NOT an operator CLI write
  (hr-all-infrastructure-provisioning-servers). The deepen-plan pass should invoke
  terraform-architect to confirm whether the existing `doppler_secret`-style resource or the
  container env-injection mechanism is the right carrier.

### Apply path
- Sentry monitor: cloud-init-free; `apply-sentry-infra.yml` auto-applies the `-target=`-scoped
  set on push to main (the established Phase-5.5 path). Add the new resource to that `-target=` set.
- Doppler token reference: applied via the secret-provisioning pipeline on merge; no SSH.

### Distinctness / drift safeguards
- dev (`mlwiodleouzwniehynfz`) != prd (`ifsccnjhymdmidffkzhl`) — the monitor's project ref is
  prd-only; it does NOT run against dev. Confirm the ref is config-scoped, not hardcoded
  across environments.

### Vendor-tier reality check
- `sentry_cron_monitor` is supported on the current Sentry tier (15+ monitors already live in
  `cron-monitors.tf`). No paid-tier gate needed (the import-only beta-provider Sharp Edge
  applies to uptime/metric-alert resources, not cron monitors).

## Domain Review

**Domains relevant:** Engineering, Operations, Product (carried-forward shape from the
2026-05-06 sibling plan; this is an infra/ops + observability change).

### Engineering (CTO)
**Status:** carry-forward + fresh diagnostics. Diagnose-first honored (live `pg_stat_io` +
`pg_stat_statements` evidence). No new SECURITY DEFINER surface. The retention DELETE is a
plain owner-side cron (same shape as 5 existing prod retention crons). The reaper cadence is
a constant change with a regression-pin test. The monitor is read-only against prod.

### Operations (COO)
**Status:** reviewed. $0 incremental (no compute add-on; optimize-only). The monitor adds 4
read-only SQL calls every 6 h — negligible IO. Closes the proactive-detection gap that the
prior fix left open (the one-shot recheck workflows were deleted).

### Product/UX Gate
**Tier:** none. No user-facing pages/components. Infra + observability only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/placeholder, or
  omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled.)
- `classification: ops-only-prod-write` → PR body uses `Ref #<issue>`, NOT `Closes` — issue
  closure is post-merge after the 7-day budget-recovery verification.
- Do NOT touch the Realtime publication or the 120 s stuck-active threshold. The publication
  removal of `messages` already shipped (2026-05-06) and `action_sends`/`conversations` have
  live consumers; the 120 s threshold is co-locked across four sources and is NOT the lever.
- The Management API has NO stable `disk_io_budget` metric endpoint (probed 2026-06-02:
  `infra-monitoring/metrics`, `daily-stats`, `usage` all 404). The monitor MUST use the SQL
  `database/query` endpoint signal, NOT a metric endpoint, and NOT a Sentry `sentry_metric_alert`
  (Sentry has no Disk-IO data).
- Verify the migration number (093 expected) against the live `migrations/` dir at /work —
  parallel feature branches can collide (migration-number-collision learning).
- The `processed_github_events` timestamp column is **`received_at`** (verified at deepen
  against mig 052:128), NOT `created_at`. An index `processed_github_events_received_at_idx`
  already exists. Use `received_at` in the retention DELETE.
- The `apply-sentry-infra.yml` `-target=` allowlist edit (line ~187) is LOAD-BEARING: the new
  `sentry_cron_monitor` is never applied without it, even though it lives in `cron-monitors.tf`.
