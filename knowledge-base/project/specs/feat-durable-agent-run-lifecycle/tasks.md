---
feature: feat-durable-agent-run-lifecycle
issue: 5766
plan: knowledge-base/project/plans/2026-07-01-feat-durable-agent-run-lifecycle-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks: Durable agent-run lifecycle (#5766)

Derived from the finalized (post-review) plan. Writer model: `spawnClaudeEval` owns upsert+heartbeat;
`run-log.ts transformOutput` owns the terminal-triggered delete. Minimal table; no `pg_cron`; no `isHeavyCron`.

## Phase 0 — Preconditions (verify before code)

- [ ] 0.1 F1 build-vs-join gate: confirm the Inngest run-state API (`lib/inngest/list-runs.ts`) does NOT already expose per-routine in-flight liveness with SIGKILL-fast detection. If it does → collapse to a read-path join and stop.
- [ ] 0.2 Confirm migration `120` free; grep BOTH `ADR-075-*` filename AND `adr:` frontmatter (duplicate-number hazard).
- [ ] 0.3 Read `spawnClaudeEval` (`_cron-claude-eval-substrate.ts:732`): confirm it can host `upsertProgress` + a periodic tick; callers close over `ctx.runId`+`attempt`.
- [ ] 0.4 Confirm the two heavy bypass crons (`cron-daily-triage.ts:149`, `cron-follow-through-monitor.ts:246`) are the only heavy non-`spawnClaudeEval` crons → NG9 (out of v1).
- [ ] 0.5 Confirm `run-log.ts transformOutput` early returns (`:148`, `:166`).

## Phase 1 — Schema

- [ ] 1.1 Write `120_routine_run_progress.sql`: cols `id, routine_id, run_id UNIQUE, attempt, started_at, last_heartbeat_at`; index on `last_heartbeat_at`; `-- LAWFUL_BASIS:` + `-- RETENTION:` annotations; RLS (service-role write, founder SELECT). No `CONCURRENTLY`.
- [ ] 1.2 Write `.down.sql` (drop table).
- [ ] 1.3 Migration test (RED→GREEN). AC1.

## Phase 2 — Live-state helper + heartbeat (writer model)

- [ ] 2.1 `routine-run-progress.ts`: `upsertProgress(fnId, runId, attempt)` (ON CONFLICT(run_id) DO UPDATE + delete-stale-same-routine), `heartbeat(runId)`, `finishProgress(runId)`; all fail-soft. AC3.
- [ ] 2.2 `spawnClaudeEval`: on entry `upsertProgress`; periodic `heartbeat(runId)` tick (~30s) while child runs. AC2.
- [ ] 2.3 Thread `runId`+`attempt` through the ~16 `spawnClaudeEval` callers (explicit bound closure — NOT ALS).
- [ ] 2.4 `run-log.ts transformOutput`: `finishProgress(runId)` after terminal write + after both early returns. AC6.
- [ ] 2.5 Billing-invariant behavioral test (twice same key ⇒ one metered row). AC7.

## Phase 3 — API + UI

- [ ] 3.1 `runs/route.ts`: merge live rows (terminal row wins on `run_id` collision); reader-computed `stuck`; ignore rows older than max-run-duration; enumerate `running`/`stuck`/`resumed` in `STATUS_VALUES`. AC4.
- [ ] 3.2 `routines-surface.tsx`: distinct `STATUS_COLOR` for `stuck`/`never`; `resumed` badge from `attempt>1`; pill precedence `stuck > running`; elapsed/"Resumed" per wireframes 13–16 (elapsed framing, not "step N"). Reuse `leader-loop-status.tsx` Realtime + poll fallback. AC5.

## Phase 4 — Contract + ADR

- [ ] 4.1 Author ADR-075 (Decision + 3 rejected alternatives; `brand_survival_threshold` frontmatter; AP-014 xref; general clause review-gated). AC8.
- [ ] 4.2 Document NG9 (heavy bypass crons deferred); `log()` coverage = `spawnClaudeEval`-routed only.

## Phase 5 — Verify

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. AC9.
- [ ] 5.2 `./node_modules/.bin/vitest run test/server/routine-run-progress.test.ts`.
- [ ] 5.3 PR body: `Ref #5766` (not `Closes`). AC10.

## Post-merge (automatable)

- [ ] P.1 Apply migration 120 (Supabase MCP or `web-platform-release.yml#migrate`). AC11.
- [ ] P.2 Close #5766 after apply. AC12.
- [ ] P.3 (monitoring, not a gate) calibrate stale threshold over 48h with ≥1 representative long run.
