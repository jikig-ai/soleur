---
type: ops-remediation
classification: ops-only-prod-write
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: procedural
issue: 5225
migration: 103
---

# fix: Supabase prod Disk-IO depletion — shorten processed_github_events retention 90d → 7d

## Enhancement Summary

**Deepened on:** 2026-06-14
**Agents:** repo-research-analyst, learnings-researcher, verify-the-negative pass, data-integrity-guardian, user-impact-reviewer (threshold-mandated)

### Key improvements from deepen-plan
1. **Migration runs as one transaction.** `run-migrations.sh:343` invokes `psql --single-transaction` per file — so the cron re-schedule + the ~91k-row one-time DELETE commit/rollback atomically. This is the real atomicity guarantee (the `EXCEPTION WHEN duplicate_object` is belt-and-suspenders). Re-running 103 after a partial failure is safe by file-level transaction, not just by idempotent guard.
2. **Add a `COMMENT ON TABLE` correction in 103** — the existing `052_multi_source_dedup.sql:145-146` comment claims retention is *"Postgres autovacuum + 30-day partition rotation (natural cleanup; no TTL daemon)"* — factually wrong (the table is NOT partitioned; 094 added a pg_cron sweep). This stale comment is what misled 094 into copying the 90-day window. Correct it so the next retention change doesn't re-derive the wrong window.
3. **`.down.sql` re-arms the bloat** — restoring the 90-day schedule re-creates issue #5225. Down is for migration-framework reversibility only; it must NEVER be applied to prod as an incident rollback. Header warning added to the spec.
4. **GHES scope-out** (user-impact-reviewer FINDING 2) — 7d clears github.com's 3-day ceiling with >2× margin, but would *tie* a GitHub Enterprise Server 7-day horizon (zero margin). Verified: Soleur has NO GHES/enterprise base-URL code path (`grep` of webhook route + lib/github + server/github returns empty). Scoped out explicitly so a future GHES onboarding doesn't inherit a zero-margin window unflagged.
5. **Monitor test edit dropped from scope** — `cron-supabase-disk-io.test.ts` asserts on `/processed_github_events/` regex, NOT the literal "retention sweep may have stopped" string. Widening the alert message breaks no test (the table name stays interpolated in the reason). Removed from Files to Edit.

### New safety margin discovered
`releaseDedupRow` (`route.ts:175-189`) DELETEs the dedup row on a 5xx and the GitHub redelivery re-INSERTs with a fresh `received_at = now()`. So a row's `received_at` always reflects the most recent claim — the 7-day purge can NEVER delete a row inside an active redelivery cycle. This is stronger than the original framing.

🐛 **Recurrence of the 2026-06-02 Disk-IO fix.** Issue **#5225** (`[disk-io] Supabase Disk-IO pressure detected`, p1-high, action-required, infra-drift) is OPEN; the vendor warning was re-sent 2026-06-14. The 2026-06-02 remediation (migration 094 retention sweep + migration 095 monitor) is in place and the monitor fired *correctly* — but the retention sweep cannot do its job because its window is set to a horizon the table never reaches.

## Overview

`public.processed_github_events` is a GitHub-webhook **dedup** table written by `app/api/webhooks/github/route.ts`. Migration 094 scheduled a daily `processed_github_events_retention` pg_cron sweep (`0 4 * * *`) with a **90-day** window — copied from the `processed_stripe_events` sibling where 90d = Stripe's replay horizon. But GitHub's dedup replay need is **hours-to-3-days**, not 90 days. So the 90-day sweep runs successfully every night yet always reports **DELETE 0** (the table's oldest row is only ~24 days old). The table bloats to a ~450k-row steady state (~5k inserts/day × 90d) before the first deletion can ever fire, and the resulting INSERT + index write IO is what depletes the prod Disk-IO budget.

This is a **WRITE-driven** burn (cache_hit_pct = 100% — re-confirms `2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md`: no missing-index work needed). The monitor's row-count tripwire (`DEDUP_TABLE_ROW_CEIL = 100_000`) fired correctly at **123,416 rows on 2026-06-12** — it did its job; the lever it pointed at (retention window) is the real defect.

**The fix is small and surgical:**
1. **Migration 103** re-schedules `processed_github_events_retention` with `interval '7 days'` (replacing 90), mirroring 094's exact idempotent `DO $cron_block$ … cron.unschedule … cron.schedule … EXCEPTION WHEN duplicate_object` shape; `.down.sql` restores the 90-day schedule.
2. **Same migration:** a one-time `DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days'` so relief lands at deploy (purges ~91k stale rows; index-backed by `processed_github_events_received_at_idx`).
3. **Migration shape-test** mirroring `094-dedup-retention.test.ts`.
4. **Monitor alert-message clarity (small):** the dedup-over-ceiling reason text says *"retention sweep may have stopped — check cron.job"*, which was misleading for THIS incident (the sweep ran fine). Widen it to name both failure modes. No threshold change needed (7-day steady state ≈ 35k ≪ 100k ceiling).

**Do NOT touch** `processed_stripe_events` (1 row; 90d correctly = Stripe's replay window) or `processed_resend_events` (no evidence of the same pathology).

## Premise Validation

Checked against live state, origin/main, and GitHub's documented platform limits:

- **Issue #5225 is OPEN** (`gh issue view 5225` — labels p1-high, action-required, infra-drift, type/bug, domain/operations). Premise holds.
- **GitHub webhook redelivery horizon = 3 days on github.com** (hard platform limit — delivery logs are *deleted* after 3 days, so no redelivery is even possible past 3 days; Enterprise Server = 7 days). GitHub does **not** auto-redeliver failed deliveries (it is a manual/scripted operation, itself bounded by the same 3-day retention). Sources: [GitHub Changelog — webhook delivery logs retained 3 days](https://github.blog/changelog/2023-10-17-webhook-delivery-logs-will-only-be-retained-for-3-days/), [Redelivering webhooks docs](https://docs.github.com/en/webhooks/testing-and-troubleshooting-webhooks/viewing-webhook-deliveries). **This validates the 7-day choice with >2× margin over the 3-day ceiling.** A second independent layer (the Inngest 24h `event.id` dedup window, `app/api/webhooks/github/route.ts` Step 7 comment) backs it. **Never go below 3 days** — that is the documented replay window and the load-bearing user-impact lever.
- **Migration 103 is FREE on origin/main** — canonical check `git ls-tree origin/main --name-only apps/web-platform/supabase/migrations/ | grep -oE '10[0-9]_' | sort -u` returns `100_ 101_ 102_` (sanity: known migrations present, so the grep is not silently broken per `2026-05-30-migration-number-collision-and-stale-plan-current-state.md`); `103_` absent.
- **No WORM/append-only trigger on `processed_github_events`.** The 052 WORM trigger (`audit_github_token_use_no_mutate`) is on a *different* table. This rules out the `2026-05-15-worm-trigger-blocks-pg-cron-retention-sweep.md` false-negative class — the 094 sweep already runs as `postgres` and reports `DELETE 0` (not `P0001`/rollback), proving DELETEs execute. The one-time purge will commit.
- **Column + index exist:** `received_at timestamptz NOT NULL DEFAULT now()` and `processed_github_events_received_at_idx ON (received_at DESC)` — both `052_multi_source_dedup.sql:128,136`. The one-time DELETE is index-backed.
- **`created_at` does NOT exist** on this table — DELETE must use `received_at` (094 test already asserts this negative).

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue / prompt) | Reality (verified) | Plan response |
|---|---|---|
| Current max migration ~102; next free is 103 | 102 is max on origin/main; 103 free | Use 103. |
| 90-day window copied from Stripe sibling | 094 comment confirms verbatim copy + cites `route.ts:347` "GitHub's redelivery limit" | Re-scope to 7d; correct the cited rationale (GitHub = 3d, not 90d). |
| GitHub replay need is "hours" | Documented: 3-day log retention on github.com; 24h Inngest layer | 7d gives >2× margin; double-processing risk eliminated. |
| Monitor false-tripped at 123,416 rows | Confirmed: ceiling 100k, fired 2026-06-12 | No threshold change; 7d steady-state ~35k ≪ 100k. Only widen the alert *message*. |
| One-time DELETE is transaction-safe, no CONCURRENTLY/VACUUM | Confirmed: plain index-backed DELETE; runner per-file idempotency (runbook `supabase-migrations.md`) | Single DELETE statement, no DDL hazards. |

## User-Brand Impact

**If this lands broken, the user experiences:** prod Supabase Disk-IO budget continues depleting → degraded/failed DB IO on the single prod project that backs **every authenticated session** (login, chat, KB, billing reads). A fully-depleted budget throttles all writes.

**If the window is set too short (< GitHub's 3-day replay horizon), the user's workflow is exposed via:** a GitHub webhook redelivered after the dedup row was purged would be **double-processed** — duplicate Inngest dispatch → duplicate agent runs / duplicate side-effects on the founder's repo. The 24h Inngest `event.id` layer mitigates the first 24h but not days 1–3. **The 7-day window is the chosen value precisely because it clears the 3-day ceiling with margin.** This is the load-bearing lever — the `user-impact-reviewer` agent must confirm the window never drops below 3 days. Additional margin (verified, not assumed): `releaseDedupRow` (`route.ts:175-189`) refreshes `received_at = now()` on every re-claim, so the 7-day purge can never delete a row inside an active redelivery cycle.

**GHES scope-out (verified):** The 3-day ceiling is the *github.com* webhook log-retention limit. GitHub Enterprise Server has a 7-day horizon, which a 7-day window would *tie* (zero margin). Soleur is a **github.com** GitHub App only — there is NO GHES/enterprise base-URL code path (`grep -rniE "enterprise|baseUrl" apps/web-platform/app/api/webhooks/github/ lib/github* server/github*` returns empty). So the operative bound is github.com's 3 days, not GHES's 7. A future GHES onboarding would need to revisit this window (it is NOT safe at zero margin for GHES).

**Brand-survival threshold:** `single-user incident` (prod Supabase is the single shared substrate; one depletion or one double-processing event is a brand-survival event). → `requires_cpo_signoff: true`. CPO sign-off required at plan time; `user-impact-reviewer` runs at review-time (review/SKILL.md conditional-agent block).

## Files to Create

- `apps/web-platform/supabase/migrations/103_github_events_retention_7day.sql`
  - Idempotent `DO $cron_block$` re-schedule of `processed_github_events_retention` → `'0 4 * * *'`, `$$DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days'$$`. Mirror 094 dollar-quoting exactly (`$cron_block$` outer, `$$` inner; `EXCEPTION WHEN duplicate_object THEN NULL`).
  - One-time `DELETE FROM public.processed_github_events WHERE received_at < now() - interval '7 days';` (after the cron re-schedule, same file). Header comment cites the 3-day GitHub horizon + 24h Inngest layer + this plan path. NOTE: the runner wraps each file in `--single-transaction` (`run-migrations.sh:343`), so the re-schedule + DELETE are atomic.
  - **`COMMENT ON TABLE public.processed_github_events IS …`** — correct the stale `052:145-146` claim (*"Postgres autovacuum + 30-day partition rotation"* — never existed) to state the actual mechanism: daily pg_cron `processed_github_events_retention` 7-day sweep (094 re-scoped by 103); 3-day github.com redelivery horizon; service-role-only. This prevents the next retention change from re-deriving the wrong window.
- `apps/web-platform/supabase/migrations/103_github_events_retention_7day.down.sql`
  - Restore the 094 90-day schedule (same idempotent shape, `interval '90 days'`). Down does NOT restore purged rows (a retention sweep is lossy by design — mirror 094.down's note).
  - **Header warning:** down is for migration-framework reversibility ONLY. It re-arms the 90-day pathology (table re-bloats → Disk-IO depletion → recreates issue #5225). NEVER apply down to prod as an incident rollback.
- `apps/web-platform/test/supabase-migrations/103-github-events-retention-7day.test.ts`
  - Mirror `094-dedup-retention.test.ts` (stripComments + regex). Assert: (1) `cron.unschedule('processed_github_events_retention')` guard present; (2) `cron.schedule('processed_github_events_retention', '0 4 * * *', …)`; (3) the scheduled DELETE uses `received_at` + `interval '7 days'` (NOT 90); (4) a one-time top-level `DELETE FROM public.processed_github_events WHERE received_at < … interval '7 days'` present; (5) does NOT reference `created_at`; (6) down restores `interval '90 days'`; (7) the up migration contains a `COMMENT ON TABLE public.processed_github_events` that does NOT mention "partition rotation" (asserts the stale-comment correction landed).

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts`
  - Widen the dedup-over-ceiling reason string (currently `… (retention sweep may have stopped — check cron.job)`) to name both modes, e.g. `… (retention sweep stopped OR its window exceeds the table's replay horizon — check cron.job AND the interval)`. Pure string change; no threshold change.
  - **No test edit required** (verified): `cron-supabase-disk-io.test.ts:65` asserts `reasons.some((r) => /processed_github_events/.test(r))` — it matches on the interpolated table name, NOT the literal "retention sweep may have stopped" phrase (which appears only at `cron-supabase-disk-io.ts:110`, nowhere in tests). Widening the message keeps `processed_github_events` interpolated, so the assertion still passes.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` bodies do not reference `094_dedup_tables_retention`, `processed_github_events`, `cron-supabase-disk-io`, or `supabase-migrations`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `103_github_events_retention_7day.sql` exists; cron re-schedule uses `interval '7 days'` and `'0 4 * * *'`; one-time DELETE uses `received_at` and `interval '7 days'`; idempotent `DO $cron_block$` + `EXCEPTION WHEN duplicate_object` shape matches 094 verbatim.
- [ ] `103_…down.sql` restores `interval '90 days'` with the same idempotent guard.
- [ ] `103-github-events-retention-7day.test.ts` passes: `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/103-github-events-retention-7day.test.ts` (vitest unit project collects `test/**/*.test.ts` per `vitest.config.ts`).
- [ ] Monitor alert string in `cron-supabase-disk-io.ts` names both "sweep stopped" and "window too long"; its unit test still passes (`./node_modules/.bin/vitest run test/server/inngest/cron-supabase-disk-io.test.ts`).
- [ ] Typecheck clean: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- [ ] Migration number 103 confirmed free via the canonical `git ls-tree origin/main` check (output shows 100/101/102, not 103).
- [ ] PR body uses **`Ref #5225`** (NOT `Closes`) — `classification: ops-only-prod-write`; the issue closes post-merge only after budget recovery is verified. (Per `2026-05-11-plan-r6-closes-after-apply-deferral-pattern.md` and `wg-use-closes-n-in-pr-body-not-title-to` ops-remediation corollary.)

### Post-merge (operator — automated; no dashboard eyeballing per `hr-no-dashboard-eyeball-pull-data-yourself`)

- [ ] **Migration applies automatically** via `web-platform-release.yml` `migrate` job (`run-migrations.sh` under Doppler `prd`) on merge to main — no manual SSH/apply step. **Automation:** baked into existing release pipeline.
- [ ] **Immediately after deploy:** confirm the purge ran and the cron interval is 7d. Read-only via the Management API (per `2026-05-06-supabase-management-api-bypasses-mcp-oauth.md`; NOT MCP, NOT psql):
  `SUPA_TOKEN=$(doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain); REF=ifsccnjhymdmidffkzhl;` then POST `https://api.supabase.com/v1/projects/$REF/database/query` with:
  - `SELECT count(*) FROM public.processed_github_events;` — **deterministic verdict: PASS if ≤ 40,000** (7-day steady-state ~35k, well under the 100k ceiling). FAIL if still > 100k (purge did not run).
  - `SELECT schedule, command FROM cron.job WHERE jobname = 'processed_github_events_retention';` — **verdict: PASS if `command` contains `interval '7 days'`** and `schedule = '0 4 * * *'`.
- [ ] **~3 days later:** re-query `disk_io_pressure_signal()` RPC via the same API path — **verdict: PASS if `cache_hit_pct ≥ 98` AND `processed_github_events` row count is stable/declining and < 100k** (monitor no longer trips). The `[disk-io]` monitor cron auto-closes #5225 on recovery; if it has not, close manually: `gh issue close 5225 --comment "<API verdict output / recovery evidence>"`. Do NOT close before this verification (matches the 2026-06-02 plan's post-merge AC).
- [ ] Note: the Supabase Disk-IO **budget gauge** itself has no stable Management-API metric endpoint (probed 2026-06-02: `infra-monitoring/metrics`, `daily-stats`, `usage` all 404 — see 2026-06-02 plan). Recovery is therefore inferred from the row-count + `disk_io_pressure_signal()` proxies above (the same signals the monitor uses), not from the gauge.

## Domain Review

**Domains relevant:** Operations (COO), Product (CPO — single-user-incident threshold)

### Operations

**Status:** reviewed (carry-forward from issue triage + prior 2026-06-02 plan)
**Assessment:** Pure ops-remediation on the prod Supabase substrate. No new vendor, no new cost (re-uses the existing pg_cron job + existing index; net Disk-IO *reduction*). The shorter window slightly increases rows-deleted-per-run, improving each sweep's signal-to-noise (per `2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale.md`); the cron is daily (`0 4 * * *`), not per-minute, so it does not re-introduce the cron-plumbing churn migration 038 removed.

### Product/UX Gate

**Tier:** none (no UI surface — no file under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`; the only edits are SQL migrations + a server cron string + tests)
**Decision:** N/A — no Product/UX gate artifacts. CPO sign-off is required by the single-user-incident threshold (frontmatter `requires_cpo_signoff: true`), separate from the UX gate. CPO confirms the 7-day window is the right product-risk trade-off (double-processing vs Disk-IO bloat).
**Pencil available:** N/A (no UI surface)

## Infrastructure (IaC)

Skipped — no new infrastructure. The pg_cron job already exists (migration 094); this re-schedules its interval via a standard Supabase migration applied by the existing `web-platform-release.yml` pipeline. No server, secret, vendor, DNS, or persistent process is introduced.

## Observability

```yaml
liveness_signal:
  what: disk_io_pressure_signal() RPC dedup_table_rows[processed_github_events] + cache_hit_pct
  cadence: 6-hourly (scheduled-supabase-disk-io Inngest cron, migration 095)
  alert_target: GitHub [disk-io] issue (auto-file/auto-close) + Sentry Crons heartbeat (scheduled-supabase-disk-io)
  configured_in: apps/web-platform/server/inngest/functions/cron-supabase-disk-io.ts
error_reporting:
  destination: Sentry via reportSilentFallback (feature "cron-supabase-disk-io")
  fail_loud: true  # a failed signal read trips a verdict (monitor that can't read its own signal is itself a failure)
failure_modes:
  - mode: 7-day sweep stops firing (cron.unschedule without re-schedule)
    detection: row count climbs past 100k → DEDUP_TABLE_ROW_CEIL breach
    alert_route: [disk-io] GitHub issue (the existing monitor)
  - mode: one-time purge did not run at deploy
    detection: post-merge Management-API count query returns > 100k
    alert_route: post-merge AC verdict (manual gh issue stays open)
  - mode: window mis-set below 3 days (double-processing risk)
    detection: migration shape-test asserts interval '7 days'; cron.job command query post-merge
    alert_route: CI test failure (pre-merge) + post-merge cron.job query
logs:
  where: cron.job_run_details (pg_cron run log) + Sentry breadcrumbs for the monitor cron
  retention: cron.job_run_details is itself bounded; monitor cron is stateless per-fire
discoverability_test:
  command: "POST https://api.supabase.com/v1/projects/$REF/database/query {\"query\":\"SELECT schedule, command FROM cron.job WHERE jobname='processed_github_events_retention'\"} (token from doppler secrets get SUPABASE_ACCESS_TOKEN -p soleur -c prd --plain)"
  expected_output: "command contains interval '7 days'; schedule = '0 4 * * *'"
```

## Test Scenarios

1. **Shape-test (file-parse, no live DB):** all six assertions in `103-…test.ts` pass against the written migration; deliberately confirm the 90-day regex would FAIL (sanity that the test discriminates 7d from 90d).
2. **Monitor message regression:** `cron-supabase-disk-io.test.ts` still green after the reason-string widening.
3. **Idempotency (reasoned, not live):** re-running 103 unschedules-then-reschedules; `EXCEPTION WHEN duplicate_object` swallows the race — identical to 094's proven shape.

## Risks & Mitigations

- **Window too short → double-processing.** Mitigated: 7d > 3d GitHub ceiling (>2× margin) + 24h Inngest layer. Shape-test pins `interval '7 days'`; `user-impact-reviewer` gates the value at review.
- **One-time DELETE locks the table during the ~91k-row purge.** Mitigated: index-backed (`received_at` idx); the runner wraps the whole file in **`--single-transaction`** (`run-migrations.sh:343`), so the re-schedule + DELETE are one atomic transaction (this is the real atomicity guarantee, not the `EXCEPTION` guard). The DELETE takes `ROW EXCLUSIVE` on `processed_github_events`; a concurrent live webhook INSERT uses a different `delivery_id` (PK) so does not conflict. No CONCURRENTLY/VACUUM. ~91k rows is a sub-second-to-low-seconds index-range delete — no chunking needed at this scale. Crash-safe: a mid-file `psql` death rolls back the whole file; re-running 103 is safe by file-level transaction.
- **Monitor false-trip during the deploy window** (count briefly between query and purge). Mitigated: monitor is 6-hourly; the purge is synchronous within the migration, so the next monitor fire sees the post-purge count.
- **Precedent diff (pg_cron idempotent re-schedule):** precedent is `094_dedup_tables_retention.sql` (and 076 `workspace_activity_purge`) — same `DO $cron_block$` shape; this plan copies it verbatim. No novel pattern. (Deepen-plan Phase 4.4 to confirm the diff.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is filled; threshold = single-user incident.)
- The one-time DELETE must sit in the SAME migration file as the re-schedule (not a separate operator step) so relief lands at deploy — an automatable step must not be punted to the operator (`hr-no-dashboard-eyeball-pull-data-yourself`, automation-feasibility gate).
- PR body: `Ref #5225`, never `Closes` — `Closes` auto-resolves at merge, before the post-merge budget-recovery verification.
- Do NOT widen the shape-test to also cover `processed_stripe_events` — that table's 90-day window is correct and unchanged; asserting 7d on it would be wrong.

## Non-Goals

- No change to `processed_stripe_events` or `processed_resend_events` (90d Stripe window is correct; no Resend pathology evidenced).
- No change to `DEDUP_TABLE_ROW_CEIL` (7-day steady-state ~35k ≪ 100k; the ceiling stays a valid tripwire).
- No compute/disk add-on purchase (#3360 deferred lever from the 2026-06-02 plan; not needed — the baseline burn is bounded by this fix).
- No index work (cache_hit_pct = 100%; read-side is already optimal at this scale).
