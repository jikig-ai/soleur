# Runbook: CI API-spend monthly reconciliation

**Owner:** ops-advisor (agent-run) · **Cadence:** monthly · **Issue:** #5086 · **ADR:** ADR-056
**Automation status:** manual agent-run bridge; scheduled automation tracked by #5173.

> ## ⚠️ STATUS 2026-07-30 — expect an empty set; that is correct, not a failure
>
> There are **three** api-spend producers, not the two named below. Two are dormant:
> `claude-code-review.yml` is `disabled_manually` (0 runs since 2026-07-01) and
> `test-pretooluse-hooks.yml` is `workflow_dispatch`-only (3 runs lifetime). The third,
> **`fix-constraints-stage-a.yml`, is ACTIVE** (417 runs since 2026-07-01) and correctly
> wires `Capture API spend` + `Upload API spend artifact` — but its agent step fires only
> on a red constraint gate, so it yields nothing on a green tree. That is a **zero-yield
> meter, not a missing one**, and the distinction matters: the remediation is to leave it
> alone, not to re-point metering. No `api-spend-*` artifact exists today and
> `knowledge-base/finance/api-spend-ledger.jsonl` holds **0 records**, so a run of this
> procedure returns an empty set — the expected result, not a failed run.
>
> **Do not delete this runbook.** Its `gh`/`jq`-only, no-dashboard discipline is correct,
> and it produces real output the first time a red constraint gate fires stage-a's agent
> step (or either dormant workflow is re-enabled).
>
> **What this runbook does NOT cover, and what does.** The claude-eval Inngest cron
> fleet — the dominant `ANTHROPIC_API_KEY` draw — is **not** in scope here and does not
> need to be: ADR-108 meters it per-run via `SOLEUR_CLAUDE_COST` markers, queryable from
> Better Stack with no admin key (`betterstack-log-query.md` §Querying Anthropic cost
> markers). Genuinely unmetered by anything: `ci.yml`'s `plugin-root-propagation-gate`
> and `sandbox-canary-capture-gate`.
>
> **Successor mechanism:** #6297 wires `cron-anthropic-cost-report` to the Anthropic
> Admin Cost & Usage API for an authoritative **org-total**, superseding per-run artifact
> capture. It is blocked on an un-mintable `ANTHROPIC_ADMIN_KEY` (the Admin API requires
> a team organization; this org is an individual account).

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

- Edit the "Anthropic API (CI)" row in `expenses.md`: set the
  Amount to the summed actual, flip Status `unmetered → active` (NOT `accruing` — that
  status was retired 2026-07-30), change the notes provenance to `recorded-actual (<month>)`,
  and REMOVE the row's `<!-- estimate verify_by=... -->` marker (the marker IS the estimate
  flag; verifying against a live source removes it).
- Reflect the new R&D subtotal in `cost-model.md` (the line currently shows
  `0.00 (unmetered)`); re-derive the R&D / Dev Tooling subtotal and burn if the
  figure is material (>10% category shift, per `cost-model.md` review cadence).
- Commit sidecar + ledger + cost-model together in one monthly commit.
