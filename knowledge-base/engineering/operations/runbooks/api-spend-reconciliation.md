# Runbook: CI API-spend monthly reconciliation

**Owner:** ops-advisor (agent-run) · **Cadence:** monthly · **Issue:** #5086 · **ADR:** ADR-056
**Automation status:** manual agent-run bridge; scheduled automation tracked by #5173.

Rolls per-run CI `claude-code-action` cost (captured as `api-spend-<run_id>`
artifacts by `claude-code-review.yml` + `test-pretooluse-hooks.yml`) into the
committed sidecar `knowledge-base/finance/api-spend-ledger.jsonl` and the single
"Anthropic API (CI claude-code-action)" line in `knowledge-base/operations/expenses.md`.
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
