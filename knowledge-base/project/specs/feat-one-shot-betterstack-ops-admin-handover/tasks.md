# Tasks: feat-one-shot-betterstack-ops-admin-handover

Plan: `knowledge-base/project/plans/2026-11-16-chore-betterstack-ops-admin-handover-ledger-fix-plan.md`

## Phase 1: Test first (RED)

- [ ] 1.1 Rewrite the FIX B describe in `plugins/soleur/test/terraform-target-parity.test.ts`. Put it after the #8754 describe and use only hoisted helpers, with `g2eStrip()`. Include assertions (a), (b) and (c) and the non-vacuity anchors. Add a history line above `const TEST_FLOOR`, re-deriving the count with `grep -cE`. The constant stays 376.
- [ ] 1.2 Run `bun test plugins/soleur/test/terraform-target-parity.test.ts`. Expect RED on (a) and (b), because the resource is still declared and no removed block exists yet.

## Phase 2: IaC (GREEN)

- [ ] 2.1 `apps/web-platform/infra/uptime-alerts.tf`: delete the detached header, then replace the resource with the commented `removed { destroy = false }` block.
- [ ] 2.2 `apps/web-platform/infra/betterstack-logs-alerts.tf`: update the ROUTING comment.
- [ ] 2.3 `tests/scripts/lib/destroy-guard-filter-web-platform.jq`: replace the SHARP EDGE inventory with the grep recipe.
- [ ] 2.4 Run `terraform fmt -check` and `validate` (TF 1.10.5), the parity test and `test-infra-privileged-tier-census.sh` (expect 10 removed blocks).
- [ ] 2.5 Run mutation rows 1–7 and H1–H2 as throwaway edits, revert them, and record the tally for the PR body.

## Phase 3: Ledger and cost model

- [ ] 3.1 `knowledge-base/operations/expenses.md`: rewrite the Responder row (68.00 active 2026-12-14) and the Better Stack row (20.60 active 2026-12-14). Remove the marker, fold the 8th cell into Notes and bump `last_updated`.
- [ ] 3.2 Check AC6 (base-vs-HEAD lint) and AC7 (`awk` prints `2 0`).
- [ ] 3.3 `knowledge-base/finance/cost-model.md`: add the 2026-11-16 note and update the Source cell, the upgrade-exposure row and `last_updated`.

## Phase 4: Dated doc notes

- [ ] 4.1 Add a dated note to each of ADR-260, ADR-298, ADR-096 and ADR-276. Additive only.
- [ ] 4.2 `model.c4`: add a comment line and the relationship-string parenthetical, then run `bash scripts/regenerate-c4-model.sh`.
- [ ] 4.3 Re-run the P4 sweep command and confirm no unnoted stale claim remains.
- [ ] 4.4 Check AC8, AC9, AC10 and AC11 (c4 parity, freshness, vitest c4, encryption-posture `--repo-sweep`).

## Phase 5: Pre-ship

- [ ] 5.1 Run the AC13 read-only token probe and expect `200`. On `401` or `403`, route to the CTO.
- [ ] 5.2 AC12: confirm decision-challenges.md still holds both operator rows, for `ship` to file.
