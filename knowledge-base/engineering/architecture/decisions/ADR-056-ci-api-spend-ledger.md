---
title: "CI API-spend ledger: per-run artifact capture → monthly rollup, not per-run commit"
status: accepted
date: 2026-06-11
related: [5086, 5085, 5173]
related_adrs: [ADR-053]
related_plans:
  - knowledge-base/project/plans/2026-06-11-feat-ci-api-spend-ledger-plan.md
related_specs:
  - knowledge-base/project/specs/feat-loop-token-cost-ledger/spec.md
brand_survival_threshold: single-user incident
---

# ADR-056: CI API-spend ledger — per-run artifact capture, monthly rollup

## Context

Soleur runs Anthropic-backed automation in two places: local Claude Code
autonomous loops (`one-shot`, `drain-labeled-backlog`, `test-fix-loop`,
`*.workflow.js`) on the operator's flat **Max 20x subscription** ($0 marginal
per run), and two CI `claude-code-action` jobs (`claude-code-review.yml`,
`test-pretooluse-hooks.yml`) authed with `ANTHROPIC_API_KEY` — the only path
with **real per-token charges**. #5086 asks to surface that metered spend in the
ops ledger. Local loops are explicitly out of scope: per-loop dollars on a
flat-subscription run manufacture a false billing surprise (brainstorm reframe,
2026-06-11).

The brand-survival threshold is **single-user incident**: the `execution_file`
the action emits carries full message logs (prompts, diffs) and runs under an API
key, so the capture path is a credential-leak vector if mishandled.

## Decision

1. **Cost source (verified).** The action's `execution_file` output is a JSON
   array whose final element is `{"type":"result","total_cost_usd":N,…}`. jq path:
   `map(select(.type=="result"))[-1].total_cost_usd`. Verified against
   `anthropics/claude-code-action@v1.0.101` `src/entrypoints/format-turns.ts:400`
   (reads `total_cost_usd`) and fixture `test/fixtures/sample-turns.json:191-192`.

2. **Redaction boundary.** `scripts/extract-api-spend.sh` is the single boundary:
   explicit 9-key projection + numeric type-coercion + a fail-closed secret-shape
   scan. Only the allowlisted record `{run_id, sha, workflow, timestamp, model,
   input_tokens, output_tokens, total_cost_usd, provenance}` ever leaves the
   runner. The raw `execution_file` is never persisted or uploaded.

3. **Capture = per-run artifact, NOT per-run commit.** Each CI run uploads the
   extracted record as a GitHub Actions artifact `api-spend-<run_id>` (90-day
   retention). A monthly agent-run reconciliation (runbook in this PR; automated
   by #5173) downloads the period's artifacts, appends them to the committed
   sidecar `knowledge-base/finance/api-spend-ledger.jsonl` in **one** commit, sums
   `total_cost_usd`, and updates the single `expenses.md` rollup line +
   `cost-model.md`.

4. **Classification.** CI `claude-code-action` spend is **R&D / dev-tooling** (an
   engineering accelerator, like the Max seats), distinct from the COGS ux-audit
   Anthropic line.

5. **Provenance labels.** Records are `recorded-actual` (API-key runs). The seeded
   ledger line starts `accruing` (estimate) until the first real reconciliation.

## Alternatives Considered

| Alternative | Rejected because |
|---|---|
| Per-CI-run commit-back to the JSONL | Concurrency conflicts on parallel PR runs; noisy per-run commits; ambiguous branch targeting (claude-code-review runs on arbitrary PR branches). |
| External metrics sink (Better Stack / Supabase) | No metrics sink exists (Better Stack is uptime-only); a Supabase table would mix engineering cost into the product-runtime cost world the brainstorm deliberately kept separate, and add a new write surface. |
| Anthropic Console / usage-API pull as primary | Dashboard-shaped, weakly machine-addressable per-run; `execution_file` is the no-SSH per-run source. Console remains a later reconciliation fallback. |
| Compute cost client-side from tokens × rate | Unnecessary — `total_cost_usd` is present in `execution_file` and already accounts for cache discounts. |
| Reuse `.claude/hooks/agent-token-tee.sh` sink | That sink is gitignored, per-machine, ephemeral — a dead end for a persistent cross-operator ledger. (Its parsing approach is prior art only.) |

## Consequences

- One monthly commit, no per-run noise, no write contention.
- Per-run detail is 90-day-durable (artifacts) — enough for monthly aggregation
  and for #5173's future deviation baseline; beyond 90 days only the committed
  monthly aggregate + appended JSONL records survive.
- The reconciliation is agent-run (no operator SSH/dashboard, per
  `hr-no-dashboard-eyeball-pull-data-yourself`) until #5173 automates it on a cron.
