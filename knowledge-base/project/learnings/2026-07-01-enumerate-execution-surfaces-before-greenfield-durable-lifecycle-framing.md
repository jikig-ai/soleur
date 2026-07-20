---
title: "Before accepting a greenfield durable-lifecycle / L5 framing, enumerate the distinct execution surfaces and grep each — the gap is usually one surface, not all"
date: 2026-07-01
category: workflow-patterns
tags: [brainstorm, durability, inngest, agent-runtime, premise-validation, surface-enumeration]
issue: 5766
pr: 5868
---

# Learning: enumerate execution surfaces before accepting a greenfield durable-lifecycle framing

## Problem

Issue #5766 asked to build a "durable agent-run lifecycle" (L5 harness layer) for web-platform
runs — model an agent run as an Inngest durable function, journal each step, `wake(runId)` on
crash. The framing (imported from an Anthropic "5 harness layers" essay) reads as greenfield:
"a run that can't resume silently dies and burns credits." Taken at face value, the brainstorm
would have designed a net-new event-log + resume substrate.

That framing conflated **three distinct agent-execution surfaces** that are in very different
states of durability. A brainstorm that treats "agent runs" as one thing designs for the worst
surface and re-builds what already exists on the others.

## Solution

Before letting the durable-lifecycle framing bound the option space, enumerate the distinct
execution surfaces and grep each for existing durability + status primitives:

| Surface | Symbol grepped | State found |
|---|---|---|
| Autonomous **agent-spawn** | `server/inngest/functions/agent-on-spawn-requested.ts` | Already Inngest step-durable (`step.run` memoized, `idempotency=actionSendId`, `retries:3`) + live status panel `leader-loop-status.tsx` |
| Interactive/**one-shot** | `server/agent-runner.ts` (WebSocket) | Honest resume shipped by #5240; committed work + draft PR survive on persistent Hetzner volume |
| **Cron/routine** | `supabase/migrations/107_routine_runs.sql` | **Terminal-only** — "running is not a DB fact"; the genuine gap |

Only the cron/routine surface lacked live/in-flight state. The build re-scoped from "build a
durable lifecycle" to "make cron/agent runs a live DB fact + codify a replay-safety contract,"
reusing `routine_runs` / run-log middleware / `leader-loop-status.tsx` instead of a parallel store.

## Key Insight

**A durability symptom framed as "we have no X" is usually "we have X on 2 of 3 surfaces."** The
fix is surface enumeration + per-surface grep, not accepting the greenfield premise. This is the
durability-lifecycle cousin of the existing "verify storage topology before accepting a durability
framing" rule (#5240) and "the web harness is an SDK loop, not a CLI with transcripts" — all three
are the same failure: a general mental model (CLI, "durable platform", "L5 layer") applied to a
web-platform that already solved most of it on a subset of surfaces.

**Secondary insight — leader reconciliation is the value, not any single leader.** All three domain
leaders (CTO/CPO/CLO) initially over- or mis-estimated the gap; the CPO explicitly corrected its own
first answer once repo-research separated the surfaces. Fast-returning leaders reason from a general
model; the repo-research grep is the authority that reconciles them. Spawn both in one batch and force
the reconciliation before presenting options.

## Session Errors

- **Sanity grep used the wrong subdir** — `grep -rl "inngest" apps/web-platform/src` returned 0;
  Inngest wiring lives under `apps/web-platform/server/inngest/`, not `src/`. Recovery: the
  repo-research agent used the authoritative paths; the false-zero never entered an artifact.
  **Prevention:** one-off — a throwaway sanity check, not a load-bearing assertion. When a pre-spawn
  grep returns zero, treat it as "check the path" not "absence," and defer to the research agent's
  full sweep rather than propagating the zero. No workflow change warranted (already covered in spirit
  by the "verify is-X-mounted claims with the specific consuming symbol" brainstorm rule).

## Tags
category: workflow-patterns
module: brainstorm, web-platform/server/inngest
