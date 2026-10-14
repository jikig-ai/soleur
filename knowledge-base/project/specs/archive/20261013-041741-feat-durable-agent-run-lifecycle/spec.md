---
title: Durable agent-run lifecycle — "running is a DB fact" + replay-safety contract
feature: feat-durable-agent-run-lifecycle
issue: 5766
branch: feat-durable-agent-run-lifecycle
pr: 5868
date: 2026-07-01
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
brainstorm: knowledge-base/project/brainstorms/2026-07-01-durable-agent-run-lifecycle-brainstorm.md
design: knowledge-base/product/design/routines/run-status-lifecycle.pen
---

# Spec: Durable agent-run lifecycle (#5766)

## Problem Statement

The web-platform run log (`routine_runs`, surfaced by `/api/dashboard/routines/runs`) is
**terminal-only**: a run becomes a DB fact only when it finishes (`completed|failed`). While a
long cron/agent run executes — or when the container is evicted mid-run (#5417: restarts
10-60×/day) — the operator sees a silent gap, then eventually a row. There is no live/in-flight
state, no distinction between "completed-but-failed" and "succeeded", and no honest signal when a
run is resumed after eviction. The autonomous **agent-spawn** path is already durable+observable
(`agent-on-spawn-requested.ts` + `leader-loop-status.tsx`), and interactive resume was handled by
#5240 — so the genuine remaining gap is the cron/routine surface plus a codified replay-safety
contract.

## Goals

- G1 — Make in-flight cron/agent runs a **queryable, live DB fact** with a non-terminal `running`
  state + heartbeat, surfaced through the existing routines run surface.
- G2 — Distinguish **completed-and-succeeded** (`ok:true`) from **completed-but-failed** (`ok:false`)
  in the terminal state; green must never mean an errored return.
- G3 — Make evicted/stuck runs **visibly distinct** from healthy-running (stale heartbeat).
- G4 — Codify a **replay-safety contract** so an eviction + Inngest replay never re-executes a
  mutating side effect; a resumed run is honestly labeled **"Resumed from step N"**.
- G5 — Establish the status-query contract without double-owning lifecycle on the CC-plugin path.

## Non-Goals

- NG1 — Re-homing the interactive `agent-runner.ts` (WebSocket) or the CC-plugin `one-shot` onto
  Inngest for step-level resume. (Deferred follow-up; worktree/lease is adequate L5, committed work
  already survives, replay hazard worst there.)
- NG2 — A new parallel event-log store. `routine_runs` + Inngest run history IS the log.
- NG3 — A new `wake(runId)` primitive. Inngest replay is `wake`.
- NG4 — Token/turn-delta journaling. Journal per completed step only.
- NG5 — Building the deploy-stable worker container (#5694) — a soft prereq owned by its own issue.

## Functional Requirements

- FR1 — Long/heavy agent-loop crons write a **non-terminal `running` row at start** and update a
  **heartbeat** per completed step. (Wireframe: `13-run-status-running-live.png`.)
- FR2 — A run whose heartbeat exceeds the stale threshold renders as **stuck/evicted**, visually
  distinct from healthy-running, with the auto-resume note + manual "Resume now". (Wireframe:
  `14-run-status-stuck-evicted.png`.)
- FR3 — A resumed run carries a **"Resumed from step N — steps 1..N-1 completed, not re-run"** trust
  label in both the row and detail; cost continues (not reset). (Wireframe:
  `15-run-status-resumed.png`.)
- FR4 — Terminal rows split **lifecycle** (`completed`) from **outcome** (`succeeded` vs
  `returned error`); `{ok:false}` returns never render green. (Wireframe:
  `16-run-status-completed-vs-succeeded.png`.)
- FR5 — In-flight + terminal states are readable through the existing `/api/dashboard/routines/runs`
  surface (extend, do not fork) and a live indicator reusing the `leader-loop-status.tsx` pattern.

## Technical Requirements

- TR1 — **Replay-safety contract:** every mutating step (git commit, GitHub write, credit spend) is
  idempotency-keyed or the last action in its `step.run`; write+commit are atomized into one step
  (`step.run` memoizes the return value, not side effects). Enforced at review via
  `observability-coverage-reviewer` + a write-boundary sweep of the tool surface.
- TR2 — **Non-terminal-row lifecycle vs. WORM:** `routine_runs` is append-only terminal rows today;
  the `running`→terminal transition needs an explicit design (start-row + terminal-row pair, or a
  guarded update-in-place). Check the `routine_runs` immutability trigger before assuming
  update-in-place. **ADR deliverable** (per `wg-architecture-decision-is-a-plan-deliverable`).
- TR3 — **Residency:** the run journal/heartbeat writes to the self-hosted EU substrate (ADR-030:
  self-hosted Redis + EU Supabase on Hetzner hel1); assert no routing through Inngest Cloud.
- TR4 — **Retention:** define a journal TTL/purge; confirm the new state is reachable by DSAR export
  (`dsar-export-allowlist.ts`) and Art. 17 erasure (cascade on run/workspace delete).
- TR5 — **Billing invariant:** completed journaled steps are NOT re-metered on resume; surface
  "cost continued" not "cost reset".
- TR6 — **Registry lockstep:** any new Inngest function/state must update all parallel registries in
  one PR (route, `cron-manifest.ts`, count test, Sentry `.tf`, workflow) — slug byte-identical.
- TR7 — **Interop:** the status-query contract must not double-own lifecycle vs. `worktree_write_lease`
  (migration 116) / session-state leases on the CC-plugin path.
- TR8 — **Observability:** new server error paths on the (non-inspectable) worker surface must be
  Sentry-reachable without SSH (`hr-observability-as-plan-quality-gate`, `hr-no-ssh-fallback-in-runbooks`).

## Open Questions (carry to plan/ADR)

- OQ1 — Heartbeat cadence + stale threshold (against real Inngest step durations).
- OQ2 — Which cron/agent classes get in-flight tracking first (all ~45 vs. long agent-loop crons only).
- OQ3 — Agent-spawn turn-resume granularity — does an in-turn crash lose the current turn? (May
  reduce scope.)
- OQ4 — Non-terminal row model vs. `routine_runs` WORM contract (→ ADR).

## Dependencies & Related

- Pairs with **#5767** (runaway guard) → the "agent-run supervisor."
- Soft prereq for long/heavy runs: **#5694** (deploy-stable worker); context: **#5417** (restarts).
- Builds on **#5240** (interactive honest resume) and **ADR-030** (Inngest durable trigger layer).
