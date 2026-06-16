---
title: Inngest Routines management UI + Concierge delegation
feature: feat-routines-management
date: 2026-06-15
lane: cross-domain
brand_survival_threshold: single-user incident
status: draft
branch: feat-routines-management
pr: "#5342"
brainstorm: knowledge-base/project/brainstorms/2026-06-15-routines-management-brainstorm.md
---

# Spec: Inngest Routines Management UI + Concierge Delegation

## Problem Statement

The Soleur autonomous company runs 42 Inngest cron routines (`server/inngest/cron-manifest.ts` →
`EXPECTED_CRON_FUNCTIONS`) that do real work (triage, content publishing, legal/competitive audits,
payment-failure handling). They are observable and operable only by reading code and using the
`soleur:trigger-cron` CLI/route — there is no web UI. The operator cannot see at a glance what is
scheduled, whether the last run succeeded, or the execution history, and cannot safely trigger a routine
off-schedule from the web.

## Goals

- **G1** Operator can see all routines in the web UI, grouped by domain, with frequency, owner role,
  on/archived state, and last-run status/date/duration.
- **G2** Operator can browse a full, durable execution history (Recent Runs) with trigger-source
  attribution (scheduled / manual / agent).
- **G3** Operator can manually trigger ("debug mode") any *allowlisted* routine off-schedule, with a
  deny-by-default confirmation gate for high-side-effect routines.
- **G4** Every lifecycle/trigger event is recorded in a WORM audit ledger capturing actor-class
  (HUMAN vs CONCIERGE AGENT), delegating principal, timestamp, routine id/version, and invocation mode.
- **G5** Agent-native parity: every operator action (view, run, toggle) is also a callable agent tool.
- **G6** Operator can delegate routine **create / edit / remove** to the Concierge via a chat window;
  the Concierge proposes a reviewable routine, **dry-run tests + verifies** it, and only then offers
  confirmation, which **opens a PR** (routines are deployed code).

## Non-Goals

- **NG1** Runtime routine creation — routines are deployed code; "create" = a PR-scaffold that goes live
  on merge + deploy, never an instant live routine.
- **NG2** True deploy-time Archive (v1 Archive is a display/disabled state; durable toggle is a HOW
  decision).
- **NG3** Real (non-dry-run) execution of an unconfirmed routine during the Concierge test step.

## Functional Requirements

- **FR1** Routines tab: list all `EXPECTED_CRON_FUNCTIONS`, grouped by domain badge, with owner-role chip,
  human-readable frequency, last-run status pill + timestamp + duration, On/Archived indicator, Run-now
  button, and overflow menu. Sort + Group controls.
  → wireframe: `knowledge-base/product/design/routines/routines-management.pen`.
- **FR2** Recent Runs tab: reverse-chronological table across all routines (name, domain, status,
  started-at, duration, trigger source), paginated, backed by the durable run-log.
- **FR3** Routine metadata sidecar: a client-free leaf exporting `Record<fnId, {domain, ownerRole,
  scheduleLabel}>` with a parity test asserting `keys(sidecar) === EXPECTED_CRON_FUNCTIONS`.
- **FR4** Run-now: POST to the existing `/api/internal/trigger-cron` via the existing
  `manual-trigger-allowlist`; no bypass endpoint.
- **FR5** Protected-routine gate: financial/egress/deletion routines (e.g. `cfo-on-payment-failed`,
  `cron-content-publisher`, `cron-legal-audit`, `cron-github-app-drift-guard`) require an explicit
  confirmation modal before manual run (deny-by-default subset).
- **FR6** Durable run-log: each routine execution writes a record (routine id, status, started/ended,
  duration, trigger source, actor-class, delegating principal).
- **FR7** Agent-tool parity for list / read-runs / run-now actions.
- **FR8** Concierge tab: a chat window (sibling to Routines / Recent Runs) to delegate routine
  create/edit/remove. Input box placeholder invites create/edit/remove requests.
  → wireframe: `…/routines/screenshots/04-concierge-chat-create-routine.png`.
- **FR9** Generated-routine review card in the Concierge reply: name, domain, owner role, frequency +
  raw cron, target file path, "what it will do", with Edit and "test it" actions — shown BEFORE any
  confirmation.
- **FR10** Concierge verification step: a **dry-run/sandbox** execution (no real email/publish/financial/
  egress/delete side-effects) with a visible "DRY RUN — no external effects" marker; reads back the app
  output and asserts correctness. Confirmation is offered ONLY after verification passes. For **edit**,
  re-run the existing routine and verify against live; for **create**, dry-run the drafted logic.
- **FR11** Confirmation action **opens a PR** scaffolding the new `cron-*.ts` (with the 5 lockstep
  registry edits) — copy states it goes live on merge + deploy, not instantly. **Remove** opens a PR
  deleting the cron + its 5 registry entries.
- **FR12** Concierge actions recorded in the WORM audit ledger as "operator-via-agent" (actor-class
  AGENT + delegating principal).

## Technical Requirements

- **TR1** `INNGEST_SIGNING_KEY` must never reach the client (`app/(dashboard)/**`, `components/**`) —
  existing grep test must keep passing; all Inngest reads are server-only.
- **TR2** Do not change the `EXPECTED_CRON_FUNCTIONS` array element type; do not add per-function metadata
  exports (preserve the client-free leaf, #4734).
- **TR3** Any new internal/agent-callable route registered in `PUBLIC_PATHS` in the same PR
  (2026-06-01 learning).
- **TR4** Run-log table: Supabase migration with RLS scoped to the operator tenant; WORM/append-only.
- **TR5** Manual-trigger allowlist parity test must cover the protected subset.
- **TR6** Sentry heartbeats (if any new cron) gated on final attempt; do not page on transient retries.
- **TR7** Treat Inngest `/v1` as enrichment only (loopback-gated, retention-bounded); run-log is the
  source of truth for history.

## Acceptance Criteria

- Operator opens the Routines tab and sees all 42 routines grouped by domain with accurate last-run state.
- Recent Runs shows historical executions with correct trigger-source attribution.
- Run-now triggers an allowlisted routine; a protected routine requires confirmation first.
- A manual run produces a WORM audit-ledger record attributing the human operator.
- An agent can list routines and trigger an allowlisted routine via a callable tool (parity).
- All existing inngest-key-server-only and registry-count/parity tests still pass.

## Open Questions

See brainstorm "Open Questions" (Concierge naming, Archive semantics, run-log write path, `/v1`
reachability, owner-role taxonomy).
