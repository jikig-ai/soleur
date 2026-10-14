---
title: Durable agent-run lifecycle — "running is a DB fact" + replay-safety contract
date: 2026-07-01
status: brainstorm-complete
issue: 5766
branch: feat-durable-agent-run-lifecycle
pr: 5868
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Durable agent-run lifecycle (#5766)

## What We're Building

Make in-flight agent/cron runs on the **web-platform** a **queryable, live DB fact** with
honest resume semantics — instead of the current terminal-only run log where a running (or
crashed) run is a silent gap until it finishes. Two pillars:

1. **"Running is a DB fact"** — long crons/agent-runs write a **non-terminal `running` row +
   heartbeat** at start and per step (not just the terminal `completed|failed` row `routine_runs`
   writes today), so an evicted/stuck run shows as a distinguishable live state rather than
   nothing. Surfaced through the **existing** `/api/dashboard/routines/runs` surface + a live
   indicator reusing the `leader-loop-status.tsx` pattern. Terminal state must distinguish
   **completed-but-failed** (`{ok:false}`) from **completed-and-succeeded** (green ≠ success).
2. **Replay-safety contract** — a documented invariant + enforced guard that every **mutating
   step** (git commit, GitHub write, credit spend) is idempotency-keyed or last-in-step, so a
   worker eviction + Inngest replay never re-executes a side effect. A run that resumes shows a
   **"Resumed from step N"** label — never silently re-presents re-done work as fresh.

Pairs with **#5767** (runaway guard) to form the "agent-run supervisor."

## Why This Approach

### The issue's premise is substantially stale — verified in code

All three domain leaders independently found #5766 is **mostly already built for the surface it
best fits**, so we re-scoped from "build a durable lifecycle" to "close the genuine remaining gap":

| Surface | Durable resume today? | Live in-flight status today? |
|---|---|---|
| **Agent-spawn** (`agent-on-spawn-requested.ts`) | **Yes** — Inngest `step.run` memoized, `idempotency=actionSendId`, `retries:3`, turn-state on `action_sends` | **Yes** — `leader-loop-status.tsx` ("turn 3 of 8", cost, Stop/Undo/Retry, Realtime) |
| **Interactive/one-shot CC** (`agent-runner.ts`, WebSocket) | Partial — #5240 shipped honest resume + SDK-resume + Supabase-replay; committed work + draft PR survive on the persistent Hetzner volume | Partial |
| **Cron/routine** (`routine_runs`) | **No** — terminal-only; "running is not a DB fact" | **No** |

So AC #1/#3/#4 are already met for agent-spawn; #5240 covered interactive honest-resume. The
**real hole is the cron/routine surface** (terminal-only run log) — which is also the exact pain
of #5417 (restarts 10-60×/day) and #5694 (deploy-stable worker).

### Why "running is a DB fact" + contract, not full re-homing (YAGNI)

- **Reuse, don't reinvent (CTO).** `routine_runs` + run-log middleware + `/api/dashboard/routines/runs`
  + `leader-loop-status.tsx` are the substrate; add a non-terminal state + heartbeat, don't build a
  parallel event-log store (Inngest's own run history + `routine_runs` *is* the log).
- **Do NOT re-home the CC-plugin path or interactive `agent-runner.ts` onto Inngest** — the
  worktree/lease model is an adequate L5 for the local path; the side-effect replay hazard is worst
  for interactive tool-heavy runs, and #5240 already captured most of that value on the persistent
  volume. (Rejected as "Full durability" option.)
- **The side-effect replay hazard is the core risk**, so the contract is load-bearing, not optional:
  `step.run` memoizes the *return value*, not side effects — a step that writes a file then commits
  in a *separate* step replays to a clean tree. Atomize write+commit; idempotency-key every external
  mutation.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Re-scope from "build durable lifecycle" to "make cron/agent runs a live DB fact + replay-safety contract" | Agent-spawn already durable+observable; #5240 covered interactive resume; the cron/routine terminal-only log is the genuine gap |
| 2 | Add a non-terminal `running` state + heartbeat to the run-log layer (extend `routine_runs`/middleware), not a new parallel store | CTO YAGNI — Inngest run history + `routine_runs` is the event log; a parallel store double-owns state and re-incurs the WAL cost the middleware bounds |
| 3 | Terminal status must distinguish completed-but-failed (`{ok:false}`) from completed-and-succeeded | Known trap: `status="completed"` masks `{ok:false}` returns; green ≠ success (`2026-06-29` cron-health learning) |
| 4 | Replay-safety contract: every mutating step idempotency-keyed or last-in-step; write+commit atomized into one `step.run` | `step.run` memoizes return value not side effects; enforced via `observability-coverage-reviewer` + write-boundary sweep at plan/review |
| 5 | "Resumed from step N" trust label; never silently re-present re-done work as fresh | Brand promise ("an AI org that remembers"); silent re-do is the trust breach, per #5240 honesty-first |
| 6 | Do NOT re-home interactive `agent-runner.ts` or the CC-plugin one-shot onto Inngest | Worktree/lease is adequate L5; committed work already survives; replay hazard worst there — deferred as follow-up |
| 7 | Journal writes to the self-hosted EU substrate (ADR-030) + defined TTL/purge; assert, don't assume | CLO residency hygiene; Inngest state is self-hosted Redis/EU-Supabase on Hetzner hel1 (ADR-030 amended 2026-06-17) |
| 8 | Billing invariant: completed journaled steps are NOT re-metered on resume | Consumer-transparency; the journal is the mitigant (replay skips completed steps) — state it explicitly |
| 9 | Pairs with #5767 (runaway guard) as the "agent-run supervisor"; verify agent-spawn turn-resume granularity as a sub-step | CTO/CPO — the two together are the supervisor; the granularity check may already be solved by `step.run` boundaries |
| 10 | Visual design: wireframe the run-status states — `knowledge-base/product/design/routines/run-status-lifecycle.pen` (screenshots `13–16`: running-live / stuck-evicted / resumed-from-step-N / completed≠succeeded) | New operator-visible live status states on the routines run surface; reuse `StatusPill`/`leader-loop-status.tsx` visual language |

## Open Questions

1. **Heartbeat cadence & stale threshold.** How often does a running step heartbeat, and after what
   silence is a run shown as "stuck/evicted"? Resolve at plan/ADR time against Inngest step durations.
2. **Which cron/agent classes get in-flight tracking first?** All ~45 EXPECTED_CRON_FUNCTIONS, or
   only the long/heavy agent-loop crons (bug-fixer, ux-audit) where the silent gap actually hurts?
   Likely the latter (YAGNI) — scope at plan time.
3. **Non-terminal row lifecycle vs. the WORM/append-only `routine_runs` contract.** `routine_runs` is
   append-only terminal rows today; a mutable `running`→`completed` transition needs a design choice
   (update-in-place vs. start-row + terminal-row pair). Check the `routine_runs` immutability trigger
   before assuming update-in-place. **ADR candidate.**
4. **Agent-spawn turn-resume granularity** — does an in-turn crash lose the current turn's reasoning,
   or does `step.run` already bound it? A HOW verification; may make part of this a no-op.
5. **Interop with `worktree_write_lease` (migration 116) / session-state leases** — the status-query
   contract must not double-own lifecycle on the CC-plugin path.

## User-Brand Impact

- **Artifact:** the durable agent-run lifecycle — the run-log/heartbeat data model + the operator-facing
  run-status surface (`routine_runs`, run-log middleware, `/api/dashboard/routines/runs`, live indicator).
- **Vector:** a resumed run replays a mis-attributed or stale journal step and silently re-executes a
  mutating side effect (git commit, GitHub write, credit spend) against the wrong workspace, or a stuck
  run is shown as healthy — the operator trusts a run state that is false.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Summary:** The web durable substrate already exists in skeleton (`agent-on-spawn-requested.ts` —
step-memoized, idempotency-keyed, retry-safe); this is **generalize + add queryable state**, not
build-a-substrate. Two surfaces, one status contract: keep the CC-plugin worktree/lease as lifecycle
owner, expose only a status-query seam. Core risk = at-least-once side effects on replay (non-idempotent
tool calls must be idempotency-keyed or last-in-step). #5694 (deploy-stable worker) is a soft prereq for
long/heavy runs only. YAGNI: don't journal every token, don't build a parallel event-log table, don't
invent a new `wake` primitive (Inngest replay *is* wake), don't re-home the CC-plugin path. ADR candidate
for the run-lifecycle generalization + ownership boundary.

### Product (CPO)

**Summary:** Corrected an initial over-estimate — live run visibility largely **already ships** for
agent-spawn (`leader-loop-status.tsx` + per-run cost). #5766-as-written conflates surfaces; the genuine
p2 gap is **`routine_runs` has no live/in-flight state** (the #5417/#5694 pain) plus verifying agent-spawn
turn-resume. Reuse `leader-loop-status.tsx`/`action_sends` rather than a parallel surface. Trust
requirement stands: label "resumed from step N", never silently re-run visible side effects. Pairing with
#5767 stands.

### Legal (CLO)

**Summary:** LOW-MODERATE, mostly pre-mitigated. The durable journal is a new retention surface (persists
previously-ephemeral in-flight reasoning/tool IO), but lands on substrate the Art. 30 register already
covers — ADR-030 (amended 2026-06-17, #5450) pins Inngest run-state to self-hosted Redis on Hetzner hel1
+ EU Supabase, so **no third-country transfer** if the journal writes to that same substrate (assert it).
No threshold event (tenant-zero, operator is the only data subject today). Hygiene: define journal
TTL/purge, confirm DSAR-export + Art. 17 erasure reachability, and state the billing invariant
("completed steps not re-metered on resume"). Cross-tenant resume mis-attribution is a data-integrity
concern for CTO/security-sentinel; legal only inherits the breach exposure if the `wake(runId)`
tenant-scoping invariant fails.

## Capability Gaps

None. All required seams exist in code, verified against the worktree HEAD:
- Run-log substrate: `apps/web-platform/supabase/migrations/107_routine_runs.sql`, run-log middleware
  `apps/web-platform/server/inngest/middleware/run-log.ts`, API `apps/web-platform/app/api/dashboard/routines/runs/route.ts`.
- Durable agent-run skeleton: `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts`.
- Live status pattern: `apps/web-platform/components/dashboard/leader-loop-status.tsx` (+ migration
  `069_action_sends_leader_loop.sql`).
- Residency posture: `knowledge-base/engineering/architecture/decisions/ADR-030-inngest-as-durable-trigger-layer.md`.
