# Tasks — #8535 registry store volume: stale plaintext/unfired sweep + NFR row

Plan: `knowledge-base/project/plans/2026-09-22-chore-registry-luks-plaintext-doc-sweep-plan.md`

## 1. Setup / baselines
- 1.1 Render `registry-userdata-budget.sh <scratch>/before.yml` on the pre-edit tree (AC4(b)).
- 1.2 Record `wc -c .github/workflows/apply-web-platform-infra.yml` (baseline 482,443 B).
- 1.3 Record `git merge-base origin/main HEAD` for AC4(a).

## 2. Core edits (exact-string edits only; no bulk sed, no jq rewrite)
- 2.1 Ledger row `hcloud_volume.registry`: `does_not_defend`, `evidence`, `retrieved_on` (D2). Check `numstat` is `3 3` and the lint passes (AC6).
- 2.2 NFR-027 row plus the "4 of 5" status line, copied from the refreshed ledger row (AC5).
- 2.3 Recut runbook (file 1):
  - 2.3.1 Rename the heading and rewrite the decision section to state mechanism.
  - 2.3.2 Add the pre-dispatch check and the `registry-host-replace-dispatch.md` link. The check reads the newest `SOLEUR_ZOT_DISK` row. If `store_luks` is not `yes` (Arm A), or `store_escrow` is `fail_passphrase` or `fail_header` (Arm B), go to the `registry_store_not_luks` triage table.
  - 2.3.3 Add a `History (dated)` block. It covers the recut in run 31437037877 and its failed restore leg, fixed by PR #7430 (`4aef468c80`).
  - 2.3.4 Correct the "If it stops" bullet, the inventory-section sentence and the first-fire note.
  - 2.3.5 Annotate the addendum paragraph and the #7278 bullet (D6, D7).
- 2.4 Blocker script (file 2): correct the header comments and the PASS `echo` in place. The logic stays unchanged (AC7).
- 2.5 Inventory workflow header and the `ZERO TERRAFORM` block (file 3).
- 2.6 `zot-registry.tf` HCL comment above `user_data =` (file 4).
- 2.7 Job-rationale runbook `## registry_luks_recut` (file 5).
- 2.8 Gate library header comment (file 6).
- 2.9 `apply-web-platform-infra.yml` (file 7): the dropdown description, the step comment and the `::error::` line (mechanism-only wording, D6).
- 2.10 `terraform-target-parity.test.ts` doc comment (file 10).

## 3. Verification
- 3.1 AC4(a): the comment-stripped diff against the merge-base is empty. AC4(b): render `after.yml` and `cmp` it.
- 3.2 AC1: run the grep, then write the classified hit list to `specs/feat-one-shot-8535-registry-plaintext-sweep/ac1-hits.txt`. Then run AC2.
- 3.3 AC3: `wc -c` < 490,000, and `bun test plugins/soleur/test/workflow-file-size.test.ts` passes.
- 3.4 AC8: `bash tests/scripts/test-registry-luks-recut-gate.sh`, then `bun test plugins/soleur/test/terraform-target-parity.test.ts`.
- 3.5 `bash -n scripts/followthroughs/registry-luks-blocker-6929.sh`, then `npx markdownlint` on the edited `.md` files.
- 3.6 PR body:
  - The first line is "Merging does not mutate production", followed by the `cmp` result, the `wc -c` figure and `Closes #8535`.
