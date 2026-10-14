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

- [x] 0.1 F1 build-vs-join gate: **VERDICT — BUILD.** `list-runs.ts` queries `/v1/events` + `/v1/events/{id}/runs` (event-specific terminal history only; no query-by-fn-name, no in-flight liveness, no heartbeat). Table justified.
- [ ] 0.2 Confirm migration `120` free; grep BOTH `ADR-077-*` filename AND `adr:` frontmatter (duplicate-number hazard).
- [ ] 0.3 Read `spawnClaudeEval` (`_cron-claude-eval-substrate.ts:732`): confirm it can host `upsertProgress` + a periodic tick; callers close over `ctx.runId`+`attempt`.
- [ ] 0.4 Confirm the two heavy bypass crons (`cron-daily-triage.ts:149`, `cron-follow-through-monitor.ts:246`) are the only heavy non-`spawnClaudeEval` crons → NG9 (out of v1).
- [ ] 0.5 Confirm `run-log.ts transformOutput` early returns (`:148`, `:166`).
- [x] 0.6 Same-routine concurrency (DI-P1-A): **VERDICT — NO double-fire.** All 15 heavy crons carry `concurrency: [{scope:"fn",limit:1},{scope:"account",key:"cron-platform",limit:1}]` on both scheduled + manual-trigger paths. Delete-stale is defense-in-depth, not correctness-critical (keep it, guarded).

## Phase 1 — Schema

- [x] 1.1 Write `120_routine_run_progress.sql` (exact DDL in plan Deepen Enhancement): cols `id, routine_id, run_id UNIQUE, attempt, started_at, last_heartbeat_at`; `-- LAWFUL_BASIS:` + `-- RETENTION:` annotations; RLS `SELECT USING (auth.uid() IS NOT NULL)` + `REVOKE INSERT/UPDATE/DELETE FROM anon, authenticated`. No `CONCURRENTLY`.
- [x] 1.2 Write `.down.sql` (drop table).
- [x] 1.3 Migration test (RED→GREEN). AC1.

## Phase 2 — Live-state helper + heartbeat (writer model)

- [x] 2.1 `routine-run-progress.ts`: `upsertProgress` = ON CONFLICT(run_id) DO UPDATE **preserving `started_at`** (DI-P2-D) + **separate staleness-guarded** delete-stale (`last_heartbeat_at < now() - bound` — DI-P1-A); `heartbeat(runId)` = **UPDATE-only** (DI-P2-E); `finishProgress(runId)` = delete. Service-client, fail-soft. AC3.
- [x] 2.2 `spawnClaudeEval`: on entry `upsertProgress`; periodic `heartbeat` tick (~30s); **clear interval on child exit** (`:820-824`). AC2.
- [x] 2.3 Thread `runId`+`attempt` through the ~16 `spawnClaudeEval` callers (explicit bound closure — NOT ALS).
- [x] 2.4 `run-log.ts transformOutput`: `finishProgress(runId)` **inside the try, immediately after** `write_routine_run` resolves (DI-P1-C — not finally/after-catch); own inner try/catch→Sentry; after both early returns. AC6.
- [x] 2.5 Replay-cost test: memoized step not re-executed on replay (NOT cost-writer ON CONFLICT — SEC-2). AC7.

## Phase 3 — API + UI

- [x] 3.1 `runs/route.ts`: merge live rows (terminal wins on `run_id`; NULL-run_id doesn't match — DI-Q3); `stuck` + ignore-filter both key on **`last_heartbeat_at`** (`stuck_threshold < ignore_bound` — DI-P1-B); apply status filter to the **merged** set (DI-P2-F); enumerate `running`/`stuck`/`resumed` in `STATUS_VALUES`. AC4.
- [x] 3.2 `routines-surface.tsx`: distinct `STATUS_COLOR` for `stuck`/`never`; `resumed` badge from `attempt>1`; pill precedence `stuck > running`; elapsed/"Resumed" per wireframes 13–16 (elapsed framing, not "step N"). Reuse `leader-loop-status.tsx` Realtime + poll fallback. AC5.

## Phase 4 — Contract + ADR

- [x] 4.1 Author ADR-077 (Decision + 3 rejected alternatives; `brand_survival_threshold` frontmatter; AP-014 xref; general clause review-gated). Include the deepen mandates: node-side vs agent-side persistence classification (`cron-bug-fixer` = agent-side reference carve-out; run-keyed `bot-fix/<issue#>` names so re-spawn collides); "last-in-step" precise def; keys from `ctx.runId` never `randomUUID`; single-operator RLS assumption + workspace_id-before-multi-tenant. AC8.
- [x] 4.2 Document NG9 (heavy bypass crons deferred); `log()` coverage = `spawnClaudeEval`-routed only.

## Phase 5 — Verify

- [x] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. AC9.
- [x] 5.2 `./node_modules/.bin/vitest run test/server/routine-run-progress.test.ts`.
- [ ] 5.3 PR body: `Ref #5766` (not `Closes`). AC10.

## Post-merge (automatable)

- [ ] P.1 Apply migration 120 (Supabase MCP or `web-platform-release.yml#migrate`). AC11.
- [ ] P.2 Close #5766 after apply. AC12.
- [ ] P.3 (monitoring, not a gate) calibrate stale threshold over 48h with ≥1 representative long run.
