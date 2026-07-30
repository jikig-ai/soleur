# Runbook: CI API-spend monthly reconciliation

**Owner:** ops-advisor (agent-run) · **Cadence:** monthly · **Issue:** #5086 · **ADR:** ADR-056
**Automation status:** manual agent-run bridge; scheduled automation tracked by #5173.

> ## ⚠️ STATUS 2026-07-30 — this runbook's inputs are dormant; it will find nothing
>
> Both artifact producers named below are inactive: `claude-code-review.yml` is
> `disabled_manually` (0 runs since 2026-07-01) and `test-pretooluse-hooks.yml` is
> `workflow_dispatch`-only (3 runs lifetime). No `api-spend-*` artifact exists in the
> repo, and `knowledge-base/finance/api-spend-ledger.jsonl` holds **0 records**. A run
> of this procedure today returns an empty set — that is the expected result, not a
> failed run.
>
> **Do not delete this runbook.** Its `gh`/`jq`-only, no-dashboard discipline is
> correct and it becomes accurate again the moment either workflow is re-enabled.
>
> **Successor mechanism:** #6297 wires `cron-anthropic-cost-report` to the Anthropic
> Admin Cost & Usage API for an authoritative org-total, superseding per-run artifact
> capture. It is blocked on an un-mintable `ANTHROPIC_ADMIN_KEY` (the Admin API
> requires a team organization; this org is an individual account). Meanwhile the
> surfaces that actually draw the key — the claude-eval Inngest cron fleet, `ci.yml`'s
> two in-image Claude probes, and `fix-constraints-stage-a`'s agent step — are
> unmetered by any procedure, this one included.

Rolls per-run CI `claude-code-action` cost (captured as `api-spend-<run_id>`
artifacts by `claude-code-review.yml` + `test-pretooluse-hooks.yml`) into the
committed sidecar `knowledge-base/finance/api-spend-ledger.jsonl` and the single
"Anthropic API (CI)" line in `knowledge-base/operations/expenses.md`.
No SSH, no dashboard — all `gh`/`jq` (`hr-no-dashboard-eyeball-pull-data-yourself`).

> **90-day window:** GitHub Actions artifacts expire after 90 days. Run monthly so
> no run's cost is lost before it is appended to the (permanent) JSONL.

## Procedure

```bash
# 1. List the prior period's runs for each capturing workflow (repeat per workflow).
gh run list --workflow claude-code-review.yml --json databaseId,createdAt,conclusion --limit 200
gh run list --workflow test-pretooluse-hooks.yml --json databaseId,createdAt,conclusion --limit 200

# 2. Download each run's artifact (skips runs with no artifact — action was gated off).
mkdir -p /tmp/api-spend-rollup
for id in <run-ids-in-period>; do
  gh run download "$id" -n "api-spend-$id" -D "/tmp/api-spend-rollup/$id" 2>/dev/null || true
done

# 3. Append the new records to the committed sidecar (dedupe by run_id).
cat /tmp/api-spend-rollup/*/api-spend-*.json >> knowledge-base/finance/api-spend-ledger.jsonl

# 4. Sum the period's actual cost.
jq -s 'map(.total_cost_usd) | add' knowledge-base/finance/api-spend-ledger.jsonl
```

## Update the ledger

- Edit the "Anthropic API (CI claude-code-action)" row in `expenses.md`: set the
  Amount to the summed actual, flip Status `accruing → active`, change the notes
  provenance from `estimate/accruing` to `recorded-actual (<month>)`.
- Reflect the new R&D subtotal in `cost-model.md` (the line currently shows
  `0.00 (accruing)`); re-derive the R&D / Dev Tooling subtotal and burn if the
  figure is material (>10% category shift, per `cost-model.md` review cadence).
- Commit sidecar + ledger + cost-model together in one monthly commit.
