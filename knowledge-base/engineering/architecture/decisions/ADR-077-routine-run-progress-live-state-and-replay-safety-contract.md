---
title: routine_run_progress live-state table + replay-safety contract for heavy crons
status: accepted
date: 2026-07-01
related: [5766, 5417, 5694, 5767, 5240]
related_adrs: [ADR-030, ADR-033]
related_plans:
  - knowledge-base/project/plans/2026-07-01-feat-durable-agent-run-lifecycle-plan.md
brand_survival_threshold: single-user incident
---

# ADR-077: routine_run_progress live-state table + replay-safety contract

## Status

**Accepted** (2026-07-01, #5766).

## Context

The web-platform run log (`routine_runs`, migration 107) is **terminal-only**: it writes one
row per run at completion via the run-log Inngest middleware. While a multi-minute heavy
claude-loop cron runs — or when the container is evicted mid-run (#5417: restarts 10–60×/day) —
the operator sees a silent gap, then eventually a terminal row. There is no live/in-flight state
and no honest signal when a run is resumed after eviction.

The autonomous **agent-spawn** path (`agent-on-spawn-requested.ts` + `leader-loop-status.tsx`) is
already Inngest-durable + observable, and interactive-run resume was handled by #5240. The genuine
gap is the **heavy cron** surface. The Inngest run-state API (`lib/inngest/list-runs.ts`) exposes
only event-specific **terminal history** (`/v1/events/{id}/runs`) — no query-by-function-name, no
in-flight liveness, no heartbeat — so it cannot back an operator-facing in-flight reader (Phase 0
F1 gate: BUILD).

Brand-survival threshold: `single-user incident`. Failure modes: the dashboard shows a dead run as
healthy (or a healthy run as stuck), or a resumed run silently re-executes a mutating side effect
(git commit, GitHub write) against the operator's repo.

## Decision

**1. In-flight run state lives in a NEW mutable sidecar table `routine_run_progress`, not on
`routine_runs`.** `routine_runs` carries a *blanket* `BEFORE UPDATE/DELETE` WORM trigger (107) — all
in-place updates are forbidden — so a `running → completed` transition is structurally impossible
there. The sidecar is mutable (heartbeat UPDATEs every ~30s), **attribution-free** (no `actor_id`/FK
to `public.users` → no PII, stays out of the Art-17 erasure + WORM-cascade machinery), and ephemeral
(deleted on terminal write; orphans reader-bounded by max-run-duration — no `pg_cron` sweep).

**2. The writer lives at the instrumentation point (`spawnClaudeEval`), not the run-log middleware.**
`spawnClaudeEval` receives `runId`+`attempt` (threaded from each caller's ctx) and owns the upsert +
heartbeat; the middleware `transformOutput` owns only the terminal-triggered delete. This makes
**live-row domain ≡ heartbeat domain by construction** — no `isHeavyCron` predicate to drift. The
two heavy crons that bypass `spawnClaudeEval` (`cron-daily-triage`, `cron-follow-through-monitor`)
get no live row in v1 (deferred, never false-stuck).

**3. Replay-safety contract.** Inngest `step.run` memoizes a completed step's *return value*, not its
side effects — so a mutating step that is re-executed on `wake` can repeat its effect. Every mutating
step MUST be **idempotency-keyed or last-in-step**, where:
- **"last-in-step"** = the mutation is the final awaited side effect in its `step.run`, with no awaited
  work after it (else a crash post-mutation-pre-return repeats it).
- **idempotency keys derive from stable Inngest run identity** (`ctx.runId` [+ deterministic
  sub-index]), **never `randomUUID()`/`Date.now()`** (which defeat cross-replay dedup by construction).

**4. Node-side vs agent-side persistence classification.** The contract's idempotency clause reaches
**node-side** persistence (`safeCommitAndPr` — replay-idempotent: commit-detect, push no-op, PR-create
`422 already exists` tolerated). It does NOT reach **agent-side** persistence, where the LLM runs
`git`/`gh pr` *inside* the `claude-eval` step (`cron-bug-fixer`): a mid-`claude-eval` eviction re-spawns
claude and can open a **duplicate PR/branch**. Agent-side crons MUST use **deterministic run-keyed
resource names** (branch `bot-fix/<issue#>`) so a re-spawn *collides* (422) rather than duplicates, OR
lift the mutation into a deterministic node step. `cron-bug-fixer` is the reference carve-out.

**5. Enforcement is review-gated, not machine-enforced** (the general clause cannot be proven by a
runtime unit test): `observability-coverage-reviewer` + the write-boundary sweep
(`hr-write-boundary-sentinel-sweep-all-write-sites`) assert per-cron persistence declaration. The one
behaviorally-testable clause is the billing invariant via Inngest step memoization (a completed step
is not re-executed on replay).

## Rejected alternatives

### Append start + terminal rows to `routine_runs`
**Rejected.** Breaks the one-terminal-row-per-run audit contract and the WAL cost the middleware
bounds; heartbeats would explode the WORM table with per-tick rows.

### `worm_bypass` UPDATE on `routine_runs` per heartbeat
**Rejected.** WORM is for terminal audit rows, not mutable in-flight state; a `SECURITY DEFINER`
bypass RPC per 30s tick is heavy and inverts the table's purpose.

### Reuse the `action_sends` column-scoped WORM pattern (mutable columns on the audit table)
**Rejected.** `action_sends` (064) uses a *column-scoped* `BEFORE UPDATE OF <immutable cols>` trigger
that admits new mutable columns; `routine_runs` (107) uses a *blanket* statement-level trigger that
admits none. And `action_sends` mutates ONCE (ack); the heartbeat mutates every ~30s. A separate
attribution-free sidecar cleanly separates ephemeral live-state from the permanent audit/erasure
contract.

### A reaper cron for stuck detection
**Rejected (deferred).** Adds the 6-registry Inngest-cron lockstep. Reader-side staleness (rows older
than `max-run-duration` are ignored) + delete-on-terminal + delete-stale-on-upsert bound the orphan
count at ~16 routines without a new cron.

## Consequences

- **Known state — "stuck → gone":** a genuinely-dead run that Inngest never replays transitions from
  `stuck` to *disappeared* at the ignore bound (no terminal record). Accepted-orphan tradeoff; the
  operator sees an honest `stuck` while the window is live.
- **Single-operator RLS assumption.** SELECT is `auth.uid() IS NOT NULL` (mirrors `routine_runs`).
  Because the table is attribution-free it CANNOT be workspace-scoped by policy alone; a `workspace_id`
  + `is_workspace_member()` predicate is required before multi-tenant enablement — deferred with the
  other not-yet-workspace-keyed tables.

## C4 impact

None. The Inngest substrate (`inngest`/`inngestPostgres`/`inngestRedis` containers), the `supabase`
data store, the `founder` actor, and the `api→supabase` / `dashboard→api` / `api→inngest` /
`inngest→supabase` edges are all already modeled (`model.c4`). `routine_run_progress` is a schema
element inside the already-modeled `supabase` container (C4 models containers, not tables); no new
external actor, external system, container, or access relationship. No `views.c4` include change.

Pairs with #5767 (runaway guard) as the "agent-run supervisor".
