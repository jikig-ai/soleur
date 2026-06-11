# Brainstorm: Token-cost ledger for autonomous loops (#5086)

**Date:** 2026-06-11
**Issue:** #5086 (OPEN, priority/p2-medium, type/feature, domain/operations)
**Related:** #5085 (operator comprehension digest — delivery surface, sequence-after)
**Branch:** feat-loop-token-cost-ledger · **PR:** #5169 (draft)
**Lane:** cross-domain · **Brand-survival threshold:** single-user incident (USER_BRAND_CRITICAL)

## What We're Building

A **monthly metered-API-spend rollup** for engineering automation — NOT a per-loop dollar ledger.

Capture the genuinely-metered Anthropic API spend from the CI `claude-code-action` path
(`claude-code-review.yml`, `test-pretooluse-hooks.yml`, both authed with `ANTHROPIC_API_KEY`),
write per-run actuals to a committed machine-written sidecar, and surface **one** monthly aggregate
line in the ops expense ledger that `cost-model.md` references as a derived input. Local autonomous
loops (`one-shot`, `drain-labeled-backlog`, `test-fix-loop`, `*.workflow.js`) run on the flat Max 20x
subscription and are framed as **"$0 extra — covered by subscription,"** never given per-loop dollars.

## Why This Approach (the premise reframe)

The issue as written assumes the enumerated loops have per-token API spend to capture. They do not.
All five domain leaders independently reached the same conclusion:

- **Local loops are $0 marginal.** They run on the operator's flat Claude Code **Max 20x subscription**
  ($200/mo × 2 seats), already booked as R&D dev-tooling in `cost-model.md`. There is no per-run dollar
  cost — only token counts (already teed locally by `.claude/hooks/agent-token-tee.sh`, gitignored).
- **Per-loop dollar figures would manufacture a false billing surprise.** Showing "this loop cost $4.12"
  when nothing was charged erodes the exact BYOK operator-trust the feature exists to protect (CPO).
- **The ledger is hand-maintained.** `expenses.md` is a recurring-vendor table; per-run rows would
  explode it and break the `cost-model.md` burn derivation (COO). Per-run data belongs in a sidecar,
  not the ledger.
- **It doesn't move the burn number.** Loop tokens are already inside the $410/mo R&D Max-seat line;
  capturing them adds $0 to burn/break-even. The real finance value is **step-up/ceiling detection**
  (Sentry-PAYG pattern: watch for Max-20x token-ceiling spillover) and correctly booking CI spend as
  **R&D, not COGS** (CFO).
- **Feasibility confirmed.** `claude-code-action@v1.0.101` exposes an `execution_file` output (the
  Claude Code result JSON) carrying `total_cost_usd` — readable via `gh`/workflow step, no SSH/dashboard.

## Key Decisions

| # | Decision | Rationale | Source |
|---|----------|-----------|--------|
| 1 | Capture ONLY the CI `claude-code-action` (API-key) path | Only path with real per-token dollars | CTO/CFO/COO |
| 2 | Never write per-run rows into `expenses.md` | Hand-maintained recurring-vendor table; breaks cost-model derivation | COO |
| 3 | Per-run actuals land in a committed machine-written sidecar | Persistent, cross-operator (not the gitignored `.session-tokens.jsonl` dead-end) | CTO |
| 4 | `expenses.md` gets ONE monthly aggregate R&D line, ux-audit-style | ux-audit stays COGS; CI loops are R&D (engineering accelerator) | CFO/COO |
| 5 | Source = `execution_file` → `total_cost_usd`; no Console dashboard eyeballing | `hr-no-dashboard-eyeball-pull-data-yourself` | CTO |
| 6 | Local loops framed "$0 extra, subscription-covered" — never per-loop dollars | Avoid manufacturing a false billing surprise | CPO |
| 7 | Provenance-label figures: recorded-actual vs notional/estimate | Protects code-to-prd / investor handoff from overstatement | CLO |
| 8 | Secret hygiene: persist only tokens+dollars+run-IDs; never keys/org_id/raw API envelopes | Single load-bearing compliance flag | CLO |
| 9 | Add a CFO "Max-20x token-ceiling spillover" step-up trigger note to cost-model | Exposure tracking, Sentry-PAYG style | CFO |
| 10 | Visual design: N/A (no UI surface in scope; digest surfacing deferred to #5085) | Pure ops/finance/CI artifact work | — |

## Non-Goals (deferred)

- **Per-loop token-cost ledger across local loops** (the issue as literally written) — rejected:
  structurally dishonest ($0 marginal) and ledger-corrupting.
- **Baseline-deviation alerting** ("optionally alert when a run deviates") — defer until ≥1 month of
  sidecar data establishes a baseline; re-evaluate then.
- **#5085 digest surfacing** of the "subscription covered N loops; CI API = $X" reassurance line —
  belongs to #5085; sequence AFTER it lands. Do not block #5085.
- **Anthropic Console/usage-API pull** as primary source — `execution_file` covers per-run CI capture;
  Console pull is a later reconciliation fallback only.
- **Local-loop token-headroom telemetry** — engineering/observability metric, out of the ledger.

## Open Questions (for plan)

1. **Sidecar location + shape:** `knowledge-base/finance/api-spend-ledger.jsonl` (CTO) vs an
   `operations/`-rooted artifact (COO). Resolve at plan time; record as an ADR (data-model decision).
2. **Who rolls the monthly total into the `expenses.md` line:** a scheduled cron, the `/ship` flow, or
   `ops-advisor` monthly reconciliation. Must avoid a "ledger nobody reconciles" (never-defer-operator).
3. **R&D-line wording in `cost-model.md`:** new derived line vs fold into existing Anthropic line.
   Confirm CI `claude-code-action` is classified R&D (CFO) and keep ux-audit COGS line distinct.
4. **`total_cost_usd` for API-key vs notional runs:** confirm it reflects a real charge on the API-key
   path (it does) and label any non-API-key runs as notional (provenance, per Decision 7).

## Productize Candidate

`api-spend-rollup` — a recurring monthly reconciliation (pull `execution_file` actuals → update the one
`expenses.md` line). Recurring cadence makes it a candidate for a scheduled cron / skill rather than a
one-off. File as follow-up; do not pivot this brainstorm.

## Domain Assessments

**Assessed:** Marketing (omitted — operator-facing internal tooling, per hr-new-skills rationale),
Engineering, Operations, Product, Legal, Sales (n/a), Finance, Support (n/a)

### Engineering (CTO)
**Summary:** Issue conflates two cost worlds; only CI `claude-code-action` is real spend. Reuse
`agent-token-tee.sh` parsing logic but not its gitignored sink. Source = `execution_file` →
`total_cost_usd` (confirmed present in v1.0.101). Land in a committed sidecar + one aggregate
`expenses.md` row. First slice: a workflow step appending CI run cost to a monthly rollup. Cut alerting,
local-loop telemetry, digest surfacing from v1.

### Product (CPO)
**Summary:** Per-loop dollars on $0-marginal loops manufacture a false billing surprise — actively erodes
BYOK trust. Build a monthly reassurance signal, not per-loop dollars. Sequence after #5085 (its digest is
the delivery surface). The pre-run disclosure gate already covers the trust-critical moment.

### Operations (COO)
**Summary:** Never write per-run rows into `expenses.md`. Accept exactly one monthly rollup line,
ux-audit-style, `ops-advisor`-owned, pulled (not eyeballed). Real backlog risk if per-run capture isn't
paired with a monthly reconciliation lifecycle.

### Finance (CFO)
**Summary:** Loop tokens move burn by $0 (already in the flat $410 R&D line). Book CI `claude-code-action`
spend as R&D (engineering accelerator), not COGS; ux-audit stays its own COGS line. Highest finance value
is a Max-20x token-ceiling spillover trigger (Sentry-PAYG style), not per-run cost. One reconciled monthly
figure, no second ledger.

### Legal (CLO)
**Summary:** No material obligation — operator self-use, single tenant, own spend. Two prudence flags:
secret hygiene (persist only tokens+dollars+run-IDs, never keys/org_id/raw API envelopes) and provenance
labeling (recorded-actual vs estimate) to protect the code-to-prd/investor handoff.
