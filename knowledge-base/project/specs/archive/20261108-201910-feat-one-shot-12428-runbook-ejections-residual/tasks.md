# Tasks — feat-one-shot-12428-runbook-ejections-residual

Plan: `knowledge-base/project/plans/2026-11-08-docs-runbook-ejections-residual-plan.md`
Issue: #12428 (tracks; stays OPEN — `Ref`, never `Closes`) | PR: #12430 — docs-only runbook edit; no code, tests, or workflow changes.

## Phase 1 — §2 dated ledger entry

- [x] 1.1 In `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`,
  append the 2026-11-08 dated bullet at the end of the §2 "Where things stand" ledger
  (immediately after the 2026-11-07 entry, before `## 3.`), using the proposed text in
  plan Phase 1 verbatim (or tighter — every number must still match
  `receipts/rerun/replay-summary.txt` and `receipts/rerun/histograms.txt`).

## Phase 2 — §4 limits-list sibling bullet

- [x] 2.1 In the same file, append the ejections-residual bullet at the end of the §4
  limits list (after the `no-run` bullet ending "…under-counting, not over)", before
  `## 5.`), using the proposed text in plan Phase 2 verbatim or tighter.

## Phase 3 — Verification

- [x] 3.1 Run AC1–AC3 greps from the plan's Acceptance Criteria (region-scoped awk/grep
  checks; receipt-token match).
- [x] 3.2 Run `bash scripts/markdown-lint.sh knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`
  — expect `clean`.
- [x] 3.3 Run `git diff --check` and confirm AC5's append-only single-file diff holds.
- [x] 3.4 Commit the runbook edit (message: `docs(runbook): record post-corroboration
  criterion-a re-run and ejections-listing residual (#12428)`).
