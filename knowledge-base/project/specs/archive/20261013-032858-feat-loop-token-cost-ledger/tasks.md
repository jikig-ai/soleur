---
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-11-feat-ci-api-spend-ledger-plan.md
closes: 5086
---

# Tasks: CI API-spend ledger (#5086)

## Phase 0 — Preconditions
- [x] 0.1 Confirm pinned jq path `map(select(.type=="result"))[-1].total_cost_usd` against one real `claude-code-review` run's `execution_file`
- [x] 0.2 Add `id: claude-hooks-test` to the `claude-code-action` step in `.github/workflows/test-pretooluse-hooks.yml`
- [x] 0.3 Author `knowledge-base/engineering/architecture/decisions/ADR-056-ci-api-spend-ledger.md` (artifact-vs-commit decision + verified jq path)

## Phase 1 — Extract helper (redaction boundary)
- [x] 1.1 `scripts/extract-api-spend.sh`: explicit 9-key projection + numeric type-coercion; fail-closed on malformed input
- [x] 1.2 `scripts/fixtures/execution-file-sample.json` (synthetic, `<<…>>` placeholder tokens)
- [x] 1.3 `scripts/extract-api-spend.test.sh`: cases (a) exact-keys+typed, (b) excluded-field key absent, (c) value-injection scrubbed, (d) malformed→empty+exit≠0
- [x] 1.4 Register `run_suite "extract-api-spend" bash scripts/extract-api-spend.test.sh` in `scripts/test-all.sh`

## Phase 2 — CI capture steps
- [x] 2.1 `claude-code-review.yml`: add extract+upload step (`if: steps.claude-review.outputs.execution_file != ''`, `continue-on-error: true`, `upload-artifact@ea165f8…f02 # v4.6.2`, name `api-spend-${{ github.run_id }}`, upload only the extracted record)
- [x] 2.2 `test-pretooluse-hooks.yml`: same step against `steps.claude-hooks-test.outputs.execution_file`

## Phase 3 — Ledger seed + reconciliation
- [x] 3.1 Seed empty `knowledge-base/finance/api-spend-ledger.jsonl`
- [x] 3.2 `knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md` (concise command block; 90-day window note)
- [x] 3.3 `expenses.md`: one R&D/dev-tools line "Anthropic API (CI claude-code-action)", `accruing`/`0.00`, cross-link sidecar + runbook
- [x] 3.4 `cost-model.md`: reference new line under R&D / Dev Tooling + one-line Max-20x spillover exposure note

## Phase 4 — Verify
- [x] 4.1 `bash scripts/test-all.sh` passes (incl. new suite); `actionlint` clean on both workflows
- [x] 4.2 All pre-merge ACs (1–11) green
- [ ] 4.3 Post-merge ACs (12–13) tracked for first-run + first-reconciliation
