# Tasks — correct the stale Anthropic API cost records

Plan: `knowledge-base/project/plans/2026-07-30-fix-correct-stale-anthropic-cost-records-plan.md`
Branch: `feat-one-shot-anthropic-cost-records-correction` · PR: #7086

## Phase 0: Preconditions (verify, do not assume)

- [x] 0.1 Read `knowledge-base/operations/expenses.md` rows "Anthropic API (ux-audit)" and
      "Anthropic API (CI claude-code-action)" in full before editing.
- [x] 0.2 Re-confirm `.github/workflows/scheduled-ux-audit.yml` is absent:
      `ls .github/workflows/scheduled-ux-audit.yml` → no such file.
- [x] 0.3 Re-confirm the two named CI workflows are dormant:
      `gh api repos/jikig-ai/soleur/actions/workflows/claude-code-review.yml --jq .state` → `disabled_manually`;
      `test-pretooluse-hooks.yml` is `workflow_dispatch`-only.
- [x] 0.4 Re-confirm `knowledge-base/finance/api-spend-ledger.jsonl` has 0 records.
- [x] 0.5 Re-confirm #5692 and #6297 are both OPEN (`gh issue view <N> --json state`).
- [x] 0.6 Record the exact current line numbers of the two `expenses.md` rows and the three
      `cost-model.md` sites — they shift as the files change.

## Phase 1: Correct the ux-audit row (expenses.md)

- [x] 1.1 Replace the mechanism sentence: name the `cron-ux-audit` Inngest handler on the prod
      host; cite deleting commit `5d3a1e11a`. Remove the `.github/workflows/scheduled-ux-audit.yml` reference.
- [x] 1.2 Widen the row's scope to the `_cron-claude-eval-substrate` fleet (21 consumers).
      Name the model tiers (`AUDIT_MODEL = claude-opus-5`, `EXECUTION_MODEL = SONNET_MODEL`)
      as the cost driver.
- [x] 1.3 Keep the `15.00` amount, explicitly labelled as the last-known **ux-audit-scoped**
      figure. Do NOT invent a fleet-wide number.
- [x] 1.4 Attach the estimate marker:
      `<!-- estimate verify_by=<date> owner=cfo source="Anthropic Console usage, or SOLEUR_CLAUDE_COST_DAILY once #6297 lands" -->`
- [x] 1.5 Delete the "Threshold warning at $15/run in workflow output" sentence — it describes
      a deleted file and has no cron-path equivalent.

## Phase 2: Correct the CI claude-code-action row (expenses.md)

- [x] 2.1 Replace the named sources with `fix-constraints-stage-a.yml` (agent step, gate-red
      only) plus `ci.yml`'s `plugin-root-propagation-gate` and `sandbox-canary-capture-gate`.
- [x] 2.2 Record that `claude-code-review.yml` is `disabled_manually` and
      `test-pretooluse-hooks.yml` is dispatch-only, so the stated capture path yields nothing
      and `api-spend-ledger.jsonl` is empty.
- [x] 2.3 Change status `accruing` → a value that is true (nothing is being measured). Amount
      stays `0.00`. Remove the "flips to recorded-actual at first monthly reconciliation"
      promise — that reconciliation has no input.
- [x] 2.4 Preserve the R&D-not-COGS classification and the Max-seat basis.

## Phase 3: Reconcile cost-model.md

- [x] 3.1 Align line ~199 (`Anthropic API (ux-audit cron)`) with the Phase 1 row.
- [x] 3.2 Align line ~158 and the provenance prose at ~175 with the Phase 2 row.
- [x] 3.3 PRESERVE UNCHANGED: the `$0 marginal` Max-loop treatment (~:175) and the BYOK `$0`
      per-user inference commitment (~:244). Add nothing contradicting either.
- [x] 3.4 Record the metering gap in the provenance prose, linking **#5692** and **#6297**;
      state that the org-total figure is unobtainable until #6297 lands.

## Phase 4: Annotate the reconciliation runbook

- [x] 4.1 Add a dated status banner to
      `knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md` stating its
      artifact inputs are dormant and pointing at #6297 as the successor mechanism.
- [x] 4.2 Do NOT delete the runbook.

## Phase 5: Verify

- [x] 5.1 AC1 (scope corrected — live records only, historical corpus carved out per the plan's
      AC1 note): `grep -c 'scheduled-ux-audit\.yml'` over expenses.md + cost-model.md +
      api-spend-reconciliation.md → **0/0/0** ✓
- [x] 5.2 AC3 `grep -c 'cron-ux-audit' expenses.md` → **1** ✓
- [x] 5.3 AC5 `#5692` → **1**, `#6297` → **1** in cost-model.md ✓
- [x] 5.4 AC6 BYOK line → **1**; `$0 marginal` → **1** (both preserved verbatim) ✓
- [x] 5.5 AC7 `git diff --name-only origin/main...HEAD` → 5 files, **0** outside `knowledge-base/` ✓
- [x] 5.6 AC8 runbook dormancy banner → **3** matches ✓
- [x] 5.7 AC10 amounts unchanged: row 50 `15.00`/`active`, row 51 `0.00`/`unmetered`;
      only `$3-$12` (the pre-existing ux-audit range) appears — no fabricated fleet figure ✓
- [x] 5.8 AC1–AC10 walked; all pass (AC1 narrowed with documented rationale).

## Phase 6: Exit gates

- [x] 6.1 `scripts/expenses-verify-by-check.sh` → exit 0; 26 markers, 0 expired, **0 anomalies**
- [x] 6.2 `scripts/expenses-verify-by-check.test.sh` → **11/11 passed**
- [x] 6.3 Table cell parity: rows 44–55 all **8 pipes** (no GFM extra-cell truncation)
- [x] 6.4 Auto-close keyword scan over `git log origin/main..HEAD --format=%B` → **clean**
- [x] 6.5 Full-suite exit gate `scripts/test-all.sh` → **rc=0, 235/235 suites passed**
      (read from the rc FILE; `SIBLING_RUN_DETECTED` fired — 3 concurrent worktrees — which
      governs false REDs, not a green result)

## Do NOT do

- Do NOT modify `fix-constraints-stage-a.yml`, `fix-constraints-stage-b.yml`, `ci.yml`, or any
  cron/workflow/script. ADR-074's two-stage split is deliberate; AC7 fails the PR if violated.
- Do NOT file a new tracking issue for alerting or attribution — #5692 and #6297 are open.
- Do NOT add a claim that per-user inference or local Claude Code loops draw org API credit.
