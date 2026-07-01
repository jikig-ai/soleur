---
title: "Moving a write to its instrumentation point can dissolve a cluster of placement-derived P0s — and a blanket-WORM trigger forces a sidecar table"
date: 2026-07-01
category: workflow-patterns
tags: [plan-review, spec-flow, simplicity, architecture, worm, inngest, writer-placement]
issue: 5766
pr: 5868
---

# Learning: dissolve placement P0s at the instrumentation point; blanket-WORM forces a sidecar

## Problem

The #5766 plan added a live-state write (upsert + heartbeat + resume-stamp) for in-flight cron runs.
spec-flow-analyzer found **three P0s** (P0-1 no `runId` at the write site; P0-2 INSERT collides on
replay; P0-3 resume-stamp placed where inputs don't exist) plus a P1 (`isHeavyCron` predicate that
would drift). The natural fix is to patch each: thread `runId`, add `ON CONFLICT`, move the stamp,
maintain an enumerated heavy-cron set. That is four fixes to four symptoms of ONE root cause: the
write was split across two sites (`run-log` middleware for INSERT, `spawnClaudeEval` for heartbeat),
and identity (`runId`/`attempt`) lived at only one of them.

## Solution

Two independent reviewers (code-simplicity + architecture-strategist) converged on the same move:
**write from the instrumentation point.** `spawnClaudeEval` already had to receive `runId` for the
heartbeat, so co-locating the upsert there made the **live-row domain ≡ heartbeat domain by
construction**. That single change dissolved P0-2, P0-3, P1-3 (`isHeavyCron` disappears — "routes
through `spawnClaudeEval`" IS the domain), AND an architecture finding that the two heavy crons
bypassing `spawnClaudeEval` would show as false-"stuck" (they now simply get no row = deferred, never
false), AND a hot-path caveat (an awaited upsert in the synchronous `transformInput` would poison the
cron start — moving it out kept `transformInput` sync). One move, five problems gone.

Separately, the schema shape was forced by a WORM detail: `routine_runs` has a **blanket**
`BEFORE UPDATE/DELETE` trigger (migration 107) — ALL updates forbidden. This is unlike `action_sends`,
whose migration-064 trigger is **column-scoped** (`BEFORE UPDATE OF <immutable cols>`), which admits
new mutable columns in place. So the mutable live-state could NOT ride `routine_runs`; it needed a
separate attribution-free sidecar table.

## Key Insight

**When a set of review findings all point at the placement of one write, look for the single site
that already needs the write's dependencies — moving the write there usually dissolves the cluster,
where patching each symptom would add code.** The simplicity lens ("collapse the split") and the
architecture lens ("the domains must be equal by construction") arrive at the same relocation from
different directions; that convergence is the signal it's the real fix, not a taste call.

Corollary (schema): before choosing "add a mutable column" vs "new table," read the target's WORM
trigger **form** — a *blanket* statement-level `BEFORE UPDATE` forbids in-place mutation entirely
(→ sidecar), while a *column-scoped* `BEFORE UPDATE OF` admits new mutable columns (→ extend in place).
The two look identical in a migration list; only the trigger body distinguishes them.

## Session Errors

- **IaC routing-gate hook blocked two plan Edits** on substring matches of "operator"/"manual" in
  benign prose, though the plan adds no infrastructure. Recovery: `<!-- iac-routing-ack:
  plan-phase-2-8-reviewed -->`. **Prevention:** one-off / by-design — the gate fails safe toward
  blocking and the ack is the intended opt-out. When a plan is pure schema+code against provisioned
  infra but its prose mentions operator/manual steps, add the ack proactively at write time. No
  workflow change warranted.

## Tags
category: workflow-patterns
module: plan, web-platform/server/inngest
