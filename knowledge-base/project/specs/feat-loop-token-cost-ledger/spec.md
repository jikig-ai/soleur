---
lane: cross-domain
brand_survival_threshold: single-user incident
closes: 5086
related: 5085
brainstorm: knowledge-base/project/brainstorms/2026-06-11-loop-token-cost-ledger-brainstorm.md
---

# Feature: Monthly metered-API-spend rollup for engineering automation (#5086)

## Problem Statement

Soleur runs Anthropic-backed automation in two places: (1) **local Claude Code autonomous loops**
(`one-shot`, `drain-labeled-backlog`, `test-fix-loop`, `*.workflow.js`) on the operator's flat Max 20x
subscription, and (2) **CI `claude-code-action` jobs** (`claude-code-review.yml`,
`test-pretooluse-hooks.yml`) authed with `ANTHROPIC_API_KEY`. Issue #5086 asks to "feed actual API spend
into the ops expense ledger," but the local loops have **$0 marginal cost** (flat subscription) — only the
CI path incurs real per-token charges. There is currently no post-run capture closing the gap between the
pre-run billing disclosure (`hr-autonomous-loop-skill-api-budget-disclosure`) and what automation actually
cost. BYOK makes cost visibility an operator-trust feature, but a naive per-loop dollar figure on
subscription-flat loops would manufacture a billing surprise that never happened.

## Goals

- Capture **real, metered** CI `claude-code-action` API spend per run (from the action's `execution_file`
  → `total_cost_usd`), no SSH / no dashboard eyeballing.
- Persist per-run actuals in a **committed, machine-written sidecar** (cross-operator, not the gitignored
  local `.session-tokens.jsonl`).
- Surface **one** monthly aggregate line in `knowledge-base/operations/expenses.md`, referenced by
  `knowledge-base/finance/cost-model.md` as a derived input (ux-audit-line pattern).
- Frame local subscription loops as **"$0 extra — covered by subscription,"** never per-loop dollars.
- Add a CFO **Max-20x token-ceiling spillover** step-up trigger note to the cost model (exposure tracking,
  Sentry-PAYG style).

## Non-Goals

- Per-loop dollar ledger across local loops (the issue as literally written — $0-marginal, ledger-corrupting).
- Per-run rows inside `expenses.md` (hand-maintained recurring-vendor table; sidecar only).
- Baseline-deviation alerting — deferred until ≥1 month of sidecar data exists.
- #5085 digest surfacing of the reassurance line — belongs to #5085; sequence after, do not block it.
- Anthropic Console/usage-API pull as primary source — `execution_file` covers CI capture.
- Local-loop token-headroom telemetry — observability metric, out of the ledger.

## Functional Requirements

### FR1: Per-run CI cost capture

A workflow step in each `claude-code-action` job reads the action's `execution_file` output, extracts
`total_cost_usd` + token usage + run identifier, and appends one record to the committed sidecar. Records
are provenance-labeled `recorded-actual` (API-key runs) vs `notional` (any non-API-key run).

### FR2: Committed sidecar ledger

A machine-written committed artifact (location TBD at plan — `knowledge-base/finance/api-spend-ledger.jsonl`
candidate) accrues per-run records. Stores **only** tokens, dollar amount, model, run ID, timestamp,
provenance label. Never stores API keys, org IDs, or raw API-response envelopes.

### FR3: Monthly ledger rollup line

`expenses.md` carries one aggregate line ("Anthropic API — CI automation", R&D/dev-tooling bucket) updated
monthly to the prior full month's summed actual. `cost-model.md` references it as a derived input and keeps
the existing ux-audit COGS line distinct.

### FR4: Cost-model step-up trigger

`cost-model.md` gains a scaling-trigger note: "Max 20x token ceiling → spillover forces +seat or API
overage," with the watched threshold named (exposure, not realized cost).

## Technical Requirements

### TR1: No-SSH discoverability

Cost source is the action's `execution_file` (Claude Code result JSON), read in-workflow via `jq`. No
SSH, no dashboard. Satisfies `hr-no-dashboard-eyeball-pull-data-yourself`. The plan MUST declare an
`## Observability` block citing how a capture failure (missing `execution_file`, malformed JSON) surfaces.

### TR2: Secret hygiene (compliance)

Sidecar write path persists only the allowlisted fields (FR2). A test asserts no `sk-ant`, `org_id`, or
auth-header substrings can reach the committed file (CLO load-bearing flag).

### TR3: Reconciliation lifecycle (no orphan ledger)

The monthly rollup MUST have a named owner + cadence (`ops-advisor` monthly reconciliation candidate) so the
sidecar→ledger line stays current. Avoid a "ledger nobody reconciles" (never-defer-operator-actions).

### TR4: Data-model ADR

The sidecar-vs-ledger landing decision is recorded as an ADR (`/soleur:architecture`) before implementation.
