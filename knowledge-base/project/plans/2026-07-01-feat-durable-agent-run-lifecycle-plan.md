---
title: "feat: Durable agent-run lifecycle — 'running is a DB fact' + replay-safety contract"
issue: 5766
branch: feat-durable-agent-run-lifecycle
pr: 5868
date: 2026-07-01
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
type: feature
brainstorm: knowledge-base/project/brainstorms/2026-07-01-durable-agent-run-lifecycle-brainstorm.md
spec: knowledge-base/project/specs/feat-durable-agent-run-lifecycle/spec.md
design: knowledge-base/product/design/routines/run-status-lifecycle.pen
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

# ✨ feat: Durable agent-run lifecycle — "running is a DB fact" + replay-safety contract

## Overview

Make in-flight **heavy agent-loop cron runs** on the web-platform a **queryable, live DB fact**
with honest resume semantics, closing the `routine_runs` "terminal-only" gap (the exact
#5417/#5694 silent-gap pain). Today `routine_runs` writes exactly one terminal row per run
(`completed|failed`); while a multi-minute claude-eval cron runs — or when the container is
evicted mid-run — the founder sees nothing, then eventually a row. This adds:

1. A **new mutable `routine_run_progress` live-state table** (one row per in-flight run:
   step/heartbeat), written from the shared `spawnClaudeEval` substrate + run-log middleware, so
   a running run is a DB fact and an evicted run is detectable as a **stale heartbeat**.
2. A **replay-safety contract** (ADR-075): every mutating Inngest step is idempotency-keyed or
   last-in-step; write+commit atomized; a resumed run stamps **"Resumed from step N"**.
3. Founder-visible **running / stuck / resumed** states + a **completed≠succeeded** rendering,
   surfaced through the existing `/api/dashboard/routines/runs` + `routines-surface.tsx`.

Scope is the **16 heavy claude-loop crons** (bug-fixer, ux-audit, seo-aeo, community-monitor, …),
not all 45 (light data crons run in seconds; no silent gap). The autonomous **agent-spawn** path
(`agent-on-spawn-requested.ts` + `leader-loop-status.tsx`) is already durable+observable and is
**out of scope**; interactive/one-shot re-homing is deferred to **#5870**.

**Complexity: medium** — one new migration + one live-state helper + one heartbeat chokepoint +
UI/API surfacing. No new Inngest cron (avoids the 6-registry lockstep), no parallel event-log
store, no new `wake` primitive (Inngest replay *is* wake).

## Infrastructure (IaC)

**No new infrastructure.** This is a pure schema + application-code change against already-provisioned
surfaces: the Supabase Postgres (migration `120` applies via the existing `web-platform-release.yml#migrate`
pipeline or the Supabase MCP — no SSH, no dashboard, no new secret), and the already-provisioned self-hosted
Inngest substrate (ADR-030). No new server, systemd unit, vendor account, DNS record, secret, or cron. Phase 2.8
reviewed — opt-out ack in the header.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| FR4: "distinguish completed-but-`{ok:false}` from succeeded" is new work | `run-log.ts:157-161` **already** writes `status='failed'` for BOTH thrown errors and `data?.ok===false` (the #5674 fix). DB has no "completed-but-errored" state — `completed`⇒success, `failed`⇒error. | FR4 reduces to **UI-only**: render `failed` distinctly (StatusPill already maps `failed`→red) + surface `error_summary`. The wireframe's "lifecycle vs outcome" split is over-modeled; collapse to `completed`(green)/`failed`(red). Do NOT re-implement backend classification. A finer `error_classification` (fatal/auth/billing) is an **OQ**, not v1. |
| An optimistic "running" pill already exists | `routines-surface.tsx:107-111` `STATUS_COLOR` has `running:blue`, shown ~5s post-trigger (`RECONCILE_DELAY_MS`) as a **client** placeholder, not DB-backed. | FR1 replaces the client placeholder with a **durable heartbeat-backed** live row spanning the full run + eviction. |
| TR2: extend `routine_runs` with a `running` state | `routine_runs` has a **blanket** `BEFORE UPDATE/DELETE` WORM trigger (`107:85-108`) — ALL updates forbidden (unlike `action_sends`, whose `064` trigger is column-scoped `BEFORE UPDATE OF`). | **New mutable table `routine_run_progress`** (ADR-075); `routine_runs` stays untouched terminal WORM. Update-in-place on `routine_runs` is structurally impossible. |
| TR5: build "completed steps not re-metered on resume" | Inngest `step.run` memoization + existing per-step idempotency keys (`cost-writer.ts`, keyed `${actionSendId}-turn-${n}`) already ensure completed cost steps don't re-run on replay. | TR5 = **document + test** the invariant, not build it. |
| Heartbeat at step boundaries | Heavy crons spend minutes inside ONE `spawnClaudeEval` step (`_cron-claude-eval-substrate.ts:732`); step-boundary heartbeats would false-positive "stuck" mid-healthy-run. | Heartbeat = **periodic wall-clock tick inside `spawnClaudeEval`** (one chokepoint, 15 crons), per the output-aware-heartbeat learning. |

## Spec-Flow Reconciliation (P0/P1 fixes)

spec-flow-analyzer traced every writer/reader against code. Dispositions:

| ID | Sev | Finding | Disposition in this plan |
|---|---|---|---|
| P0-1 | P0 | Heartbeat writer has no `runId`; ~16-file plumbing under-scoped to 1 file | Files to Edit expanded: thread `runId`/heartbeat-callback into `spawnClaudeEval` + all callers; OQ for ALS-vs-explicit. |
| P0-2 | P0 | `startProgress` INSERT collides on replay (attempt>1, same `runId`, `run_id UNIQUE`) | `startProgress` is an **UPSERT** `ON CONFLICT (run_id) DO UPDATE` in `transformInput`. |
| P0-3 | P0 | `resumed_from_step` placed where inputs don't exist | Moved to `run-log.ts transformInput` (has `runId`/`attempt`/prior row). |
| P1-1a | P1 | Orphan `stuck` rows have no deleter (NG6 rejects reaper cron, yet claims TTL-purge) | **pg_cron TTL sweep** (DB job, not Inngest cron) + delete-stale-same-routine in upsert. |
| P1-1b | P1 | "Resume now" button (wireframe 14) has no producer | **Cut from v1** (NG8) — Inngest auto-replays; a manual resume isn't wired and re-trigger = new run. Wireframe over-specified. |
| P1-2 | P1 | `resumed` not mutually exclusive with running/stuck; precedence undefined | `resumed` is a **badge overlay** (from `resumed_from_step IS NOT NULL`), not a status; pill precedence **stuck > running**. |
| P1-3 | P1 | INSERT domain (all 45 crons) ≠ heartbeat domain (16 heavy) → false-stuck on light crons | Gate `startProgress` to `isHeavyCron(fnId)`. |
| P1-4 | P1 | AC12 "zero false-stuck" passes vacuously at 1-user volume (empty set) | AC12 precondition: ≥1 representative long run (≥ threshold) executed in the window (trigger one deliberately). |
| P1-5 | P1 | `route.ts STATUS_VALUES={completed,failed}` — status-filter drops live rows | Enumerate `running`/`stuck`/`resumed` in the reader filter domain. |
| P2-1 | P2 | "resumed-then-failed" state not enumerated (terminal row loses resume context) | **Accepted loss (v1):** resumed badge shows only while the live row exists; a resumed-then-failed writes a plain `failed` terminal row. Documented; OQ4 revisit. |
| P2-2 | P2 | `STATUS_COLOR` muted fallback lets `stuck`≡`resumed`; AC5 under-asserts | AC5 tightened: distinct from running **and from each other**; require explicit `STATUS_COLOR` entries + `never`. |
| P2-3 | P2 | AC2 asserts the tick, not the DB heartbeat advance (G1 is "DB fact") | Add a DB-level test asserting `last_heartbeat_at` advances in the row (AC2b). |
| P2-4 | P2 | AC7 may assert key presence, not charge count | AC7 clarified behavioral: invoke twice same key ⇒ one metered row. |
| P2-5 | P2 | Heavy crons spend the whole run in ONE `step.run("claude-eval")` — "step N" is coarse/meaningless | **Reconcile granularity:** drop `total_steps`/`current_step_index` (Phase 1); the heartbeat carries **elapsed / `heartbeat_count`**, and "Resumed" reads "resumed after ~Xm of recovered progress," NOT "step 6 of N." Wireframe 15's fine "step 6" is reframed to elapsed-progress. |

## Plan-Review Reconciliation (simplicity + architecture)

Keystone decision: **`upsertProgress` is written from `spawnClaudeEval`, not the run-log middleware.** Because `spawnClaudeEval` already needs `runId`+`attempt` threaded for the heartbeat, co-locating the upsert there makes the **live-row domain ≡ heartbeat domain by construction** — dissolving spec-flow P0-2/P0-3/P1-3 AND arch-HIGH-1 (straggler false-stuck) AND the arch `transformInput`-async-hot-path caveat in one move.

| # | Source | Finding | Disposition |
|---|---|---|---|
| S-F2 | simplicity | Collapse the write split into `spawnClaudeEval`; delete `isHeavyCron` | **Adopt.** Upsert + heartbeat both fire from `spawnClaudeEval`; `finishProgress` (delete) stays in run-log `transformOutput`. Domain = "routes through `spawnClaudeEval`" (structural, no enumerated set to drift). |
| S-F3/F4/F6 | simplicity | Drop `resumed_from_heartbeat`, `current_step` (constant), `heartbeat_count` (redundant) | **Adopt.** Badge = `attempt>1`. Minimal table: `id, routine_id, run_id UNIQUE, attempt, started_at, last_heartbeat_at`. |
| S-F5 | simplicity | Drop `pg_cron` TTL sweep | **Adopt.** Orphans handled by: terminal delete + delete-stale-same-routine on upsert + reader ignores rows older than max-run-duration (row count bounded by ~16 routines). |
| S-F7 | simplicity | v1 = `spawnClaudeEval`-routed only; defer stragglers | **Adopt** (see A-1). |
| S-YAGNI | simplicity | Drop AC2a (proxy), drop standalone replay test of untouched code, move AC12 out of checklist | **Adopt.** Keep ADR-075 (codification) + AC7 (billing, genuinely enforceable). |
| A-1 | architecture | `isHeavyCron ⊆ heartbeat set` invariant; 2 HEAVY crons bypass `spawnClaudeEval`: `cron-daily-triage.ts:149`, `cron-follow-through-monitor.ts:246` | **Dissolved by S-F2** (no `isHeavyCron`): the two bypass crons get NO live row in v1 → deferred, never false-stuck. Named in NG9. |
| A-2 | architecture | `transformOutput` delete-vs-terminal-write ordering unspecified; delete-first + terminal-fail = run vanishes | **Adopt.** `finishProgress` fires **terminal-write-first, delete-second**, AND after BOTH early returns (`:148` step-level `if (step) return`, `:166` thrown-non-final). AC + Phase 2. |
| A-3 | architecture | Drop ALS; thread explicit bound callback (ALS across `step.run` is fragile — `enterWith`, undefined on replay) | **Adopt.** ~16 one-line `heartbeat: () => heartbeat(ctx.runId)` edits; no ALS. |
| A-4 | architecture | Replay-safety contract enforceable for billing, aspirational for general clause | **Adopt.** ADR-075 general clause scoped **review-gated** (write-boundary sweep + `observability-coverage-reviewer`), NOT machine-enforced; the one behavioral test is AC7 (billing, `cost-writer.ts:144` `ON CONFLICT (invocation_id) DO NOTHING`). |
| A-5 | architecture | Reader precedence live-vs-terminal undefined | **Adopt.** Merge prefers the terminal `routine_runs` row over a lingering live row (AC4). |
| A-LOW | architecture | Duplicate-ADR-number hazard (027/030/031/033/038 each ×2); ADR-075 needs `brand_survival_threshold` + AP-014 xref | **Adopt.** Phase 0 greps BOTH `ADR-075-*` filename AND `adr:` frontmatter; ADR-075 carries `brand_survival_threshold: single-user incident` + AP-014 cross-link. |
| S-F1 | simplicity | Could the Inngest run-state API back the reader, eliminating the table? | **Phase 0 gate** (below). Expected: minimal table justified by output-aware liveness + SIGKILL-fast detection (arch affirmed the sidecar), but verify before Phase 1. |

## User-Brand Impact

**If this lands broken, the user experiences:** the routines dashboard shows a run as healthy-running
when it is actually dead (or as stuck when it is fine), or a resumed run silently re-presents already-done
work as fresh — the founder trusts a run state that is false.

**If this leaks, the user's workflow/money is exposed via:** a resumed run replays a mis-attributed or stale
journal step and re-executes a mutating side effect (git commit, GitHub write, credit spend) against the
wrong workspace. Mitigated by the ADR-075 replay-safety contract + attribution-free live table.

**Brand-survival threshold:** single-user incident. (Carried forward from brainstorm; `requires_cpo_signoff:
true`. CPO reviewed the brainstorm — Domain Review carry-forward below. `user-impact-reviewer` runs at PR review.)

## Goals

- G1 — In-flight heavy-cron runs are a queryable live DB fact (`running` + heartbeat).
- G2 — Evicted/stuck runs are **visibly distinct** from healthy-running (stale heartbeat, reader-computed).
- G3 — A resumed run is honestly labeled **"Resumed from step N"**; completed steps are not re-metered.
- G4 — Replay-safety contract codified (ADR-075) + enforced at review (`observability-coverage-reviewer` + write-boundary sweep).
- G5 — Terminal `failed` renders distinctly from `completed`, `error_summary` surfaced (FR4, UI-only).

## Non-Goals

- NG1 — Re-homing interactive `agent-runner.ts` / CC-plugin one-shot onto Inngest (deferred → **#5870**).
- NG2 — A parallel event-log store (Inngest run history + `routine_runs` + `routine_run_progress` IS the log).
- NG3 — A new `wake(runId)` primitive (Inngest replay is wake).
- NG4 — Per-token/per-turn-delta journaling (heartbeat is per-tick, not per-token).
- NG5 — In-flight tracking for the 29 light data crons or the already-observable agent-spawn path.
- NG6 — A new reaper cron (avoids 6-registry lockstep; stale computed in the read path; live row deleted on terminal write).
- NG7 — A finer `error_classification` column (OQ; FR4 satisfied by existing completed/failed).
- NG8 — A manual **"Resume now"** control (wireframe 14 over-specified it; spec-flow P1-1b). Inngest auto-replays on its own; re-triggering via `runRoutine` creates a NEW run, not a resume. Cut from v1; the dashboard shows `stuck` honestly and lets Inngest's own retry/replay recover.
- NG9 — The two **heavy crons that bypass `spawnClaudeEval`** (`cron-daily-triage.ts:149`, `cron-follow-through-monitor.ts:246`, both "Mirrors spawnClaudeEval; does not route through it" — arch-A-1) get no live row in v1. They are **not false-stuck** (no row is written at all); instrumenting them is a follow-up. v1 coverage = `spawnClaudeEval`-routed crons only.

## Files to Create

- `apps/web-platform/supabase/migrations/120_routine_run_progress.sql` + `.down.sql` — new mutable live-state table (next number verified: highest is 119).
- `apps/web-platform/server/inngest/routine-run-progress.ts` — `upsertProgress()` / `heartbeat()` / `finishProgress()` helpers (service-client writes; fail-soft).
- `knowledge-base/engineering/architecture/decisions/ADR-075-routine-run-progress-live-state-and-replay-safety-contract.md` — ADR (frontmatter: `brand_survival_threshold: single-user incident`, cross-link AP-014; general replay-safety clause scoped **review-gated**, not machine-enforced — arch-A-4).
- `apps/web-platform/test/server/routine-run-progress.test.ts` — deterministic unit tests incl. the AC7 billing-invariant behavioral test (no LLM in assertion path; vitest `test/**/*.test.ts` glob). **No standalone `replay-safety-contract.test.ts`** (S-YAGNI: it would assert pre-existing cost-writer/commit paths this PR doesn't touch; the ADR codifies the contract, `observability-coverage-reviewer` + write-boundary sweep enforce it at review).

## Files to Edit

**Writer model (post-review — keystone):** `spawnClaudeEval` owns BOTH the upsert and the heartbeat (it gets `runId`+`attempt` threaded); `run-log.ts transformOutput` owns only the terminal-triggered delete. This makes live-row domain ≡ heartbeat domain by construction (no `isHeavyCron` predicate). See `## Plan-Review Reconciliation`.

- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `spawnClaudeEval` (`:732`): accept `runId`+`attempt` (via bound `progress` closure). On entry, `upsertProgress(fnId, runId, attempt)` (`ON CONFLICT (run_id) DO UPDATE` — replay attempt>1 refreshes, no collision) + delete-stale-same-routine. Then a periodic wall-clock `heartbeat(runId)` tick (~30s) while the child runs. All fail-soft. **Replay-safety:** heartbeat/upsert are within-step side effects (self-heal on next tick); no mutating step split.
- **`spawnClaudeEval` callers** (~16 sites that already close over `ctx.runId` + call it inside `step.run` per ADR-033): pass `runId`+`attempt`. **Explicit bound callback, NOT ALS** (arch-A-3: ALS across `step.run` is fragile — `enterWith`, undefined on replay). ~16 mechanical one-line edits.
- `apps/web-platform/server/inngest/middleware/run-log.ts` — `transformOutput` only: `finishProgress(runId)` (delete live row) **after the terminal write succeeds** and **after BOTH early returns** (`:148` step-level `if (step) return`, `:166` thrown-non-final) — arch-A-2 ordering. Deleting a non-existent row is a harmless no-op, so no `isHeavyCron` gate needed. `transformInput` **unchanged** (stays synchronous — no hot-path I/O). Preserve fail-soft mirror.
- `apps/web-platform/app/api/dashboard/routines/runs/route.ts` — merge in-flight `routine_run_progress` rows, **preferring the terminal `routine_runs` row when both exist for a `run_id`** (arch-A-5); compute `stuck` reader-side (`now - last_heartbeat_at > threshold`) but **ignore rows older than max-run-duration** (S-F5 orphan bound); **enumerate `running`/`stuck`/`resumed` in `STATUS_VALUES` (`:16`)** so status-filtering doesn't drop live rows (P1-5).
- `apps/web-platform/components/routines/routines-surface.tsx` — `STATUS_COLOR` gets **distinct** entries for `stuck` + `never`; **`resumed` is a badge overlay** derived from `attempt > 1` (P1-2 / S-F3); pill precedence **stuck > running**. Render heartbeat/elapsed + "Resumed" (elapsed-progress framing, not "step N" — P2-5) per wireframes 13–16; reuse `leader-loop-status.tsx` Realtime + 2s-poll fallback.

## Architecture Decision (ADR/C4)

### ADR
- **Create ADR-075** — "routine_run_progress live-state table + replay-safety contract". Decision: in-flight run
  state lives in a NEW mutable table (`routine_runs` WORM trigger forbids in-place transition); the replay-safety
  contract (mutating steps idempotency-keyed/last-in-step; write+commit atomic) is the cross-cutting invariant every
  heavy-cron tool must honor. `## Alternatives Considered`: (a) append start+terminal rows to `routine_runs` — rejected
  (breaks the one-terminal-row-per-run audit contract + WAL cost the middleware bounds); (b) worm_bypass UPDATE on
  `routine_runs` per heartbeat — rejected (WORM is for terminal audit, not mutable in-flight state; heavy RPC per tick);
  (c) reaper cron for stuck detection — deferred (6-registry lockstep; reader-side stale is sufficient for v1).
  Extends ADR-033 (heavy crons spawn claude in `step.run`) + ADR-030 (self-hosted EU Inngest). Status: `accepted`.

### C4 views
- **No C4 model/view change.** Completeness enumeration (all three `.c4` read): (a) external human actors — `founder`
  (operator↔dashboard read) already modeled; no new actor. (b) external systems — none new; crons run in the already-modeled
  `inngest` container, write to `supabase`. (c) containers/data-stores — `routine_run_progress` is a schema element INSIDE the
  already-modeled `supabase` database container (C4 models containers, not tables); `inngest`/`inngestPostgres`/`inngestRedis`
  modeled (`model.c4:168-179`). (d) access relationships — the live read/write flows through existing `api→supabase`,
  `dashboard→api`, `api→inngest`, `inngest→supabase` edges (`model.c4:288-293`); no changed access grain. Operational-audit-log
  tables sit below C4 container grain — no view `include` line changes.

### Sequencing
- ADR-075 authored in this PR (not deferred). #5694 (deploy-stable worker) is a soft prereq for *long* runs only — the
  heartbeat + reader-side stale detection ship independently and degrade gracefully without it.

## Observability

```yaml
liveness_signal:
  what: routine_run_progress heartbeat (last_heartbeat_at) + terminal routine_runs row
  cadence: heartbeat every ~30s during spawnClaudeEval; terminal row on completion
  alert_target: Sentry (stale-heartbeat beyond threshold with no terminal row) — reuse run-log Sentry mirror
  configured_in: apps/web-platform/server/inngest/routine-run-progress.ts + infra/sentry/*.tf (alert rule only; no new monitor)
error_reporting:
  destination: Sentry via existing run-log fail-soft mirror
  fail_loud: live-row write failures mirror to Sentry, never throw into the cron handler (preserve run-log fail-soft contract)
failure_modes:
  - mode: cron evicted mid-run (SIGKILL, #5417)
    detection: in-surface — last_heartbeat_at goes stale (reader computes now - last_heartbeat_at > threshold); cross-check Inngest run-state
    alert_route: dashboard shows "stuck"; Sentry alert on stale-live-row-without-terminal
  - mode: run resumes on Inngest replay
    detection: in-surface — live row survives crash; resumed_from_step stamped when attempt>1 / prior progress present
    alert_route: dashboard "Resumed from step N" (informational, not an alert)
  - mode: completed-but-{ok:false}
    detection: run-log already writes status='failed' (structured, existing); error_summary populated
    alert_route: dashboard red 'failed' pill + error_summary
logs:
  where: Sentry breadcrumbs + routine_run_progress row (in-surface state)
  retention: live row is ephemeral — deleted on terminal write; orphans TTL-purged (short window). routine_runs unchanged.
discoverability_test:
  command: "execute_sql: SELECT routine_id, current_step, last_heartbeat_at, now()-last_heartbeat_at AS staleness FROM routine_run_progress ORDER BY last_heartbeat_at"
  expected_output: in-flight runs listed with fresh heartbeats; no stale rows without a matching terminal routine_runs row (no remote-shell)
```

**Affected-surface (blind cron worker, Phase 2.9.2):** the heartbeat is an **in-surface** probe emitted FROM the cron
worker (not a host-side gate). Its structured fields (`current_step`, `last_heartbeat_at`, `attempt`, `resumed_from_step`)
discriminate the competing hypotheses in one row — evicted (stale heartbeat, no terminal) vs. healthy-long-run (fresh
heartbeat) vs. resumed (resumed_from_step set) vs. clean-completed (row deleted + terminal routine_runs present).

## Implementation Phases

### Phase 0 — Preconditions (verify before code)
- **F1 gate (build-vs-join):** confirm the self-hosted Inngest run-state API (`lib/inngest/list-runs.ts`) does NOT already expose per-routine in-flight liveness with SIGKILL-fast detection. If it does, collapse the table to a read-path join and STOP. Expected outcome: minimal table justified (output-aware liveness + faster-than-step-timeout eviction detection; arch affirmed the sidecar) — but verify first.
- Confirm migration 120 free (verified: highest is 119). Grep BOTH `ADR-075-*` filename AND `adr:` frontmatter (duplicate-ADR-number hazard — arch-A-LOW).
- Read `spawnClaudeEval` (`:732`) — confirm it can host `upsertProgress` + a periodic tick and that callers close over `ctx.runId`+`attempt`.
- Enumerate the HEAVY crons that bypass `spawnClaudeEval`: `cron-daily-triage.ts:149`, `cron-follow-through-monitor.ts:246` (arch-A-1) — confirm they are the only heavy bypassers; they are **out of v1 scope** (NG9), not false-stuck (they get no live row).
- Confirm `run-log.ts transformOutput` early returns (`:148` step-level, `:166` thrown-non-final) so `finishProgress` lands after both.

### Phase 1 — Schema (RED: migration test first)
- `120_routine_run_progress.sql` — **minimal table** (post-review): `id uuid PK`, `routine_id text NOT NULL`, `run_id text NOT NULL UNIQUE`, `attempt smallint NOT NULL DEFAULT 1`, `started_at timestamptz NOT NULL`, `last_heartbeat_at timestamptz NOT NULL`. Index on `last_heartbeat_at`. **Dropped** `total_steps`/`current_step_index` (P2-5), `current_step` (constant `"claude-eval"` — S-F4), `heartbeat_count` (redundant with `last_heartbeat_at` — S-F6), `resumed_from_heartbeat` (badge = `attempt>1` — S-F3). **Attribution-free** (no actor_id/FK-to-users → no PII surface; TR4). NOT WORM (mutable heartbeat). RLS: service-role write; founder SELECT via existing routines RLS. Sibling-migration check for non-transactional DDL (no `CONCURRENTLY`).
  - **Orphan handling (no `pg_cron` — S-F5):** terminal delete (`finishProgress`) + delete-stale-same-routine on upsert + reader ignores rows older than max-run-duration. Row count bounded by ~16 routines; a run-once-then-dead orphan is a harmless reader-filtered row.
  - **GDPR-gate fold-ins (Phase 2.7, both Important):** annotate `-- LAWFUL_BASIS: legitimate_interest (operational run observability)` (mirrors `routine_runs`/ADR-028) and `-- RETENTION: ephemeral — deleted on terminal write; orphans reader-bounded by max-run-duration`. Gate confirmed: no Art.9/Art.17/Chapter-V findings (attribution-free + EU-resident).
- `.down.sql`: drop table.

### Phase 2 — Live-state helper + heartbeat (RED→GREEN) — final writer model
- `routine-run-progress.ts`: `upsertProgress(fnId, runId, attempt)` (INSERT…ON CONFLICT(run_id) DO UPDATE + delete-stale-same-routine), `heartbeat(runId)` (bump `last_heartbeat_at`), `finishProgress(runId)` (delete). All service-client; fail-soft (mirror to Sentry, never throw).
- `spawnClaudeEval` + ~16 callers: caller passes `runId`+`attempt` (explicit bound closure — arch-A-3). On entry `upsertProgress`; then periodic `heartbeat(runId)` tick (~30s) while child runs. Domain ≡ heartbeat domain by construction (no `isHeavyCron`).
- `run-log.ts transformOutput`: `finishProgress(runId)` **after** the terminal `write_routine_run` succeeds and **after both** early returns (`:148`, `:166`) — arch-A-2. `transformInput` untouched.
- **Replay-safety:** upsert/heartbeat are within-step self-healing side effects; no mutating step split (git commit/PR/credit stays idempotency-keyed or last-in-step per ADR-075).

### Phase 3 — API + UI (RED→GREEN)
- `runs/route.ts`: merge live rows; compute `stuck` reader-side (`now - last_heartbeat_at > threshold`).
- `routines-surface.tsx`: `StatusPill`/`STATUS_COLOR` add `stuck`/`resumed`; render heartbeat/elapsed/"Resumed from step N"/`error_summary` per wireframes 13–16; reuse `leader-loop-status.tsx` Realtime + 2s-poll fallback.

### Phase 4 — Contract + ADR
- Author ADR-075 (above); the general replay-safety clause is **review-gated** (write-boundary sweep + `observability-coverage-reviewer`), the billing clause is behaviorally tested (AC7). No standalone contract test of untouched code.
- Confirm the two heavy bypass crons (`cron-daily-triage`, `cron-follow-through-monitor`) are documented as NG9 (out of v1); `log()` that coverage is `spawnClaudeEval`-routed only.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `120_routine_run_progress.sql` creates the minimal mutable, attribution-free live table (`run_id UNIQUE`, `last_heartbeat_at` index; columns exactly `id, routine_id, run_id, attempt, started_at, last_heartbeat_at`; `-- LAWFUL_BASIS:` + `-- RETENTION:` annotations; no `pg_cron`); `routine_runs` byte-unchanged (`git diff` shows no edit to `107_*`).
- [ ] AC2 — **DB-level** (G1 "DB fact"): `spawnClaudeEval` upserts a row on entry, and after two ~30s ticks the row's `last_heartbeat_at` has advanced (read-back, not a mocked-call proxy — P2-3/S-YAGNI; fake clock; **no LLM in the assertion path**).
- [ ] AC3 — Replay: `upsertProgress` with `ON CONFLICT (run_id) DO UPDATE` on `attempt>1` refreshes the surviving row with no `run_id UNIQUE` collision (deterministic — P0-2). The write is in `spawnClaudeEval` (has `runId`+`attempt`), not the middleware (P0-3 dissolved).
- [ ] AC4 — A light cron (not `spawnClaudeEval`-routed) gets **no** live row (domain-by-construction — P1-3/A-1). `runs/route.ts`: in-flight rows carry a reader-computed `stuck` flag (`now - last_heartbeat_at > threshold`); rows older than max-run-duration are ignored (not "stuck forever" — S-F5); when a live row and a terminal `routine_runs` row share a `run_id`, the **terminal row wins** (A-5); `STATUS_VALUES` enumerates `running`/`stuck`/`resumed` (P1-5).
- [ ] AC5 — UI: `running`/`stuck`/`completed`/`failed` have **distinct** `STATUS_COLOR` entries (distinct from running **and from each other** — P2-2); `resumed` is a **badge overlay** from `attempt > 1` (P1-2/S-F3); `never` has an explicit color. Component test asserts all four wireframe states + the badge.
- [ ] AC6 — `transformOutput` ordering (A-2): `finishProgress` fires **after** the terminal `write_routine_run` and **after both** early returns (`:148` step-level, `:166` thrown-non-final) — test that a step-level event and a non-final throw do NOT delete the live row, and a delete-before-terminal cannot vanish a run.
- [ ] AC7 — Billing invariant (**behavioral** — P2-4/A-4): invoking a completed cost step twice with the same idempotency key yields **one** metered row (backed by `cost-writer.ts:144` `ON CONFLICT (invocation_id) DO NOTHING`).
- [ ] AC8 — ADR-075 exists with `## Decision` + `## Alternatives Considered` (3 rejected), `brand_survival_threshold: single-user incident` frontmatter, AP-014 cross-link, and the C4 "no-impact" enumeration.
- [ ] AC9 — Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`. Tests: `./node_modules/.bin/vitest run test/server/routine-run-progress.test.ts` (path matches `test/**/*.test.ts` glob).
- [ ] AC10 — `Ref #5766` in PR body (not `Closes` — migration applies post-merge; see AC13).

### Post-merge (automatable)
- [ ] AC11 — Migration 120 applied to prd (automatable via `mcp__plugin_supabase_supabase__apply_migration` or `web-platform-release.yml#migrate`; not a hand step).
- [ ] AC12 — Close #5766 via `gh issue close` after AC11 succeeds.

**Post-deploy monitoring (NOT an acceptance criterion — S-YAGNI; does not gate merge or closure):** calibrate the stale threshold (automatable read, `hr-no-dashboard-eyeball`): query `routine_run_progress` staleness over 48h. Precondition to make the check non-vacuous at single-user volume (P1-4): ensure ≥1 heavy run of duration ≥ threshold executed in the window (trigger one via `runRoutine` if none did). Verdict: no live row exceeds the threshold while its cron is still executing per Inngest run-state → tune the threshold if it does.

## Domain Review

**Domains relevant:** Engineering (CTO), Product (CPO), Legal (CLO) — carried forward from the 2026-07-01 brainstorm `## Domain Assessments`.

### Engineering (CTO)
**Status:** reviewed (carry-forward). **Assessment:** generalize + add queryable state, not build-a-substrate; keep CC-plugin worktree/lease as owner; core risk = at-least-once side effects on replay (idempotency-keyed/last-in-step); #5694 soft prereq for long runs only; no parallel event-log, no new wake primitive. Reflected in TR1, ADR-075, NG2/NG3.

### Product (CPO)
**Status:** reviewed (carry-forward). **Assessment:** live visibility already ships for agent-spawn; genuine gap is `routine_runs` terminal-only; reuse `leader-loop-status.tsx`/`action_sends` patterns; trust label "resumed from step N", never silently re-run visible side effects. Reflected in FR1/FR3, Files to Edit.

### Legal (CLO)
**Status:** reviewed (carry-forward). **Assessment:** LOW-MODERATE, pre-mitigated by ADR-030 EU residency; hygiene = journal TTL/purge + DSAR/erasure reachability + billing invariant. Reflected in TR3/TR4/TR5 + attribution-free live table (Phase 1) + ephemeral-with-TTL retention (Observability). GDPR gate re-run at Phase 2.7.

### Product/UX Gate
**Tier:** blocking (UI-surface files: `routines-surface.tsx`). **Decision:** reviewed — wireframes already produced in brainstorm Phase 3.55 (`run-status-lifecycle.pen`, frames 13–16, committed) and referenced in spec FR1–FR4. **Agents invoked:** ux-design-lead (brainstorm), spec-flow-analyzer (this plan, Phase 2.5). **Skipped specialists:** none. **Pencil available:** yes (`.pen` on disk, non-empty, referenced in spec FRs).

## Open Code-Review Overlap

**None.** 61 open `code-review` issues queried (Phase 1.7.5); none reference the planned files (`run-log.ts`, `routines-surface.tsx`, `_cron-claude-eval-substrate.ts`, `routines/runs/route.ts`, `cron-manifest.ts`, `routine_run_progress`). Check ran; no fold-in/defer required.

## Test Scenarios

- Heartbeat cadence (fake clock; captured DB writes) — deterministic, no LLM.
- Eviction → stale heartbeat → `stuck` (reader computes; no dependency on a clean SIGTERM write).
- Replay → `resumed_from_step` stamped; completed cost step not re-metered.
- Terminal write deletes live row; orphaned live row TTL-purged.
- UI: 4 states render distinctly (component test, vitest `test/**/*.test.tsx` jsdom).

## Risks & Mitigations

- **False "stuck" on healthy long runs** → heartbeat ticks *during* `spawnClaudeEval` (not step boundaries); threshold ≥ 2–3× tick; AC12 calibration.
- **Replay double-execution of a mutation** → ADR-075 contract + `replay-safety-contract.test.ts`; write+commit atomized (learning 2026-06-14).
- **Live-row write failure poisoning a cron** → fail-soft mirror (never throw), preserving run-log contract.
- **WORM confusion** → live table is NOT WORM (mutable); `routine_runs` untouched; no worm_bypass role-check trap (use GUC if any bypass ever needed — learning 2026-05-18).
- **Direct-spawn straggler crons uninstrumented** → Phase 4 enumerates the 10; instrument or explicit scope-out; `log()` any dropped coverage (no silent cap).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
## Open Questions (→ deepen-plan / ADR)
- OQ1 — Exact heartbeat tick (~30s?) + stale threshold + max-run-duration bound, calibrated by real claude-eval durations (post-deploy monitoring note).
- OQ2 — Stuck cross-check against the Inngest run-state API (out-of-band, learning 2026-06-01) vs. reader-side stale alone. (The build-vs-join half is the Phase 0 F1 gate; this is the residual robustness question.)
- OQ3 — `error_classification` (fatal/auth/billing) column — v2 follow-up or fold in? (FR4 satisfied without it.)
- _Resolved during review:_ straggler coverage → NG9 (`spawnClaudeEval`-routed only); writer placement → `spawnClaudeEval` (Plan-Review Reconciliation); ALS → explicit callback (A-3).
