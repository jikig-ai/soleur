---
feature: L5 Runaway Guard — Doom-Loop Detection + Token/Cost Circuit Breaker
issue: 5767
branch: feat-l5-runaway-guard
draft_pr: 5881
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
created: 2026-07-01
brainstorm: knowledge-base/project/brainstorms/2026-07-01-l5-runaway-guard-brainstorm.md
---

# Spec: L5 Runaway Guard

## Problem Statement

Autonomous agent runs on the Soleur web platform consume the operator's own Anthropic (BYOK) credits
server-side, unattended. A non-technical founder "cannot watch a terminal," and the signature L5 failure
mode is a run that loops on the same error and burns thousands of dollars overnight with no artifact to
show for it. Today's guards are narrow and incomplete:

- The durable leader loop (`agent-on-spawn-requested.ts`, from #5866/#5868) has a **per-spawn, hardcoded,
  silent** cost ceiling (`PER_SPAWN_COST_CEILING_CENTS=260`), a BYOK `killTripped` cap, and
  `LEADER_MAX_TURNS=8` — but no run/window-wide aggregation, no operator tunability, and **no notification**
  when it trips (`persistFailure` only writes `failure_reason`).
- The heavy autonomous crons (`_cron-claude-eval-substrate.ts`) spawn opaque `claude --print` with **no
  token metering** — only wall-clock + `--max-turns`.
- **No doom-loop / no-progress detector** exists on any surface (the hash+Jaccard math in `stop-hook.sh`
  is CC-only and unwired to cost).
- **No pre-run cost estimate** exists anywhere.
- ToS §3a.5 represents "no Jikigai-provided cost ceiling" — **already contradicted** by the shipped ceiling.

## Goals

1. A **rolling-24h-per-founder, operator-tunable, notified** cost circuit breaker that halts a run when the
   ceiling is crossed (extends the existing per-spawn ceiling).
2. A **pre-run cost estimate** always shown at kickoff, plus an **opt-in** HITL spend-approval gate for
   routines the founder explicitly arms as high-cost.
3. A **doom-loop detector** (nudge → halt on repeated no-progress edits) on the web leader loop and the
   CC plugin, reusing existing hash+Jaccard math.
4. **Token metering for the heavy-cron substrate** so those runs come under the same ceiling.
5. **Legal/compliance reconciliation:** amend ToS §3a.5/§11, update the Article 30 register + DPD + GDPR
   Policy, pass `/soleur:gdpr-gate`.
6. An **ADR** capturing the cross-surface enforcement topology.

## Non-Goals

- A single unified runtime primitive across web + CC (surfaces inherently diverge on enforcement — share
  policy schema + hash math only).
- A blanket per-kickoff approval gate (rejected: reintroduces approval fatigue; violates
  `wg-verified-work-ships-without-asking`).
- Generalizing `test-fix-loop`'s test-exit-code convergence into the doom-loop detector (leave narrow).
- A new per-edit-event DB table (WAL-budget risk — fold counters into existing live-state rows).
- Setting the final default ceiling dollar value (CFO deliverable at plan time).

## Functional Requirements

- **FR1 (PR-A):** Aggregate BYOK spend over a **rolling 24h window per founder** (extend the
  `audit_byok_use` sum query with a time filter) and halt the run when it crosses an **operator-tunable**
  ceiling; terminal `failure_reason` distinct from the per-spawn case.
- **FR2 (PR-A):** On any budget/doom-loop halt, send an operator notification via the existing
  `notifications.ts` WS→Push→Email hierarchy. Message contains, in plain-language dollars: amount spent
  ($X of $Y), why it stopped, what was/wasn't accomplished, one next action (raise+resume or abandon).
  Wireframes: `design/runaway-guard/screenshots/03a-halt-banner-cost-ceiling.png`,
  `03b-halt-banner-doom-loop.png`, `03c-halt-email-transactional.png`.
- **FR3 (PR-A):** ToS §3a.5 amended to describe a best-effort Jikigai ceiling (operator bears overage);
  §11 overage carve-out confirmed; Article 30 register + DPD + GDPR Policy updated; `/soleur:gdpr-gate`
  passes. (clo-attestation; v1 counsel-review gate.)
- **FR4 (PR-B):** Pre-run **cost estimate** always shown at kickoff (informational, non-blocking, dollars).
  Wireframe: `design/runaway-guard/screenshots/01-pre-run-cost-estimate.png`.
- **FR5 (PR-B):** **Opt-in** HITL approval modal for founder-armed high-cost routines only. Wireframe:
  `design/runaway-guard/screenshots/02-hitl-spend-approval-modal.png`.
- **FR6 (PR-C):** Doom-loop detector — detect repeated no-progress edits per target (identical-action hash
  `(file_path+diff)` + Jaccard, reusing `stop-hook.sh` math), inject a "reconsider your approach" nudge,
  and **halt after N nudges**. On the web loop, halt by returning terminal `ok:false` (never throw).
- **FR7 (PR-C):** CC-plugin best-effort variant via PostToolUse(Edit|Write) hook (`agent-token-tee.sh`
  wiring template); labelled best-effort, may only act at the next tool/Stop boundary.
- **FR8 (PR-D):** Switch heavy-cron spawn to `--output-format stream-json --verbose`; parse per-turn
  `usage` from stdout JSONL; tally cumulative tokens in the existing `routine_run_progress` row; halt via
  the existing `AbortController` SIGTERM→SIGKILL seam. (Gated on Open-Q #2 go/no-go.)

## Technical Requirements

- **TR1:** Web halts terminate by returning `ok:false` (terminal, no Inngest retry) and check the durable
  counter **on entry** — a throw triggers replay and re-enters `spawnClaudeEval`, replay-looping the runaway.
- **TR2:** Doom-loop counters + cumulative-token tally live in the existing `routine_run_progress` /
  `action_sends` row (add columns), **not** a new per-edit table.
- **TR3:** Every new ceiling names the threat it protects against + a synthetic test (per
  `2026-05-05-defense-relaxation-must-name-new-ceiling`). Absolute run ceiling MUST NOT reset on
  forward-progress signals (dual-timer DoS-safety, per `2026-06-12-idle-watchdog-reset...`).
- **TR4:** CC-surface halt-state file (if used) applies all five TOCTOU race guards
  (`2026-03-18-stop-hook-toctou-race-fix`) + a 4h TTL for orphan cleanup.
- **TR5:** Notification payload minimized to cost/token aggregates + run-id — no prompt/response content,
  no PII beyond the operator's own account id. Halt paths mirror to Sentry
  (`cq-silent-fallback-must-mirror-to-sentry`); `observability-coverage-reviewer` gates them.
- **TR6:** Shared policy schema (run-wide token ceiling, per-target edit cap, hard-iteration cap) + shared
  hash helper extracted from `stop-hook.sh`, consumed by both surfaces.

## Build Sequence (multi-PR train)

1. **PR-A** — FR1, FR2, FR3 (safety floor + ToS/register). CFO default-value deliverable.
2. **PR-B** — FR4, FR5 (estimate + opt-in HITL).
3. **PR-C** — FR6, FR7 (doom-loop detector, web + CC).
4. **PR-D** — FR8 (cron stream-json metering). Gated on Open-Q #2.
5. **ADR** — enforcement topology (web hard-kill vs CC best-effort); create via `/soleur:architecture`.

## Open Questions

See brainstorm `## Open Questions` — default ceiling value (CFO), cron stream-json go/no-go, budget-check
granularity, resume semantics, doom-loop no-progress signal choice.
