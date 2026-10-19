# Tasks — web-2 LUKS rebirth workflow (#9372)

Plan: knowledge-base/project/plans/2026-10-05-feat-web2-luks-rebirth-workflow-plan.md. Offline only: nothing is dispatched, applied, minted or written to Doppler.

## Phase 0 — measurements
- [ ] 0.1 Read server.tf volume/server user_data references; record the five-target set
- [ ] 0.2 Read web-host-replace-gate.sh (preamble, by-name refusal) and betterstack-query.sh --help plus one caller
- [ ] 0.3 Open-code-review overlap check over the final Files lists

## Phase 1 — plan gate (tests first)
- [ ] 1.1 Fixtures: tests/scripts/fixtures/web-host-rebirth/*.json (synthesized)
- [ ] 1.2 tests/scripts/test-web-host-rebirth-gate.sh with the Guard 1 matrix; RED
- [ ] 1.3 tests/scripts/lib/web-host-rebirth-gate.sh (web-1 refusal first; pre/post modes); GREEN
- [ ] 1.4 Measure a fixture against destroy-guard-filter-web-platform.jq counters

## Phase 2 — state classifier
- [ ] 2.1 Tests for refuse 1-6 and heal windows (Guard 2); RED
- [ ] 2.2 tests/scripts/lib/web2-rebirth-classify.sh; GREEN

## Phase 3 — emptiness helper
- [ ] 3.1 Tests with a query shim (Guard 4); RED
- [ ] 3.2 scripts/web2-rebirth-emptiness.sh; GREEN

## Phase 4-5 — workflow and its suite
- [ ] 4.1 apps/web-platform/infra/web2-luks-rebirth-workflow.test.sh (step-body execution under bash -e; Guard 3); RED
- [ ] 4.2 .github/workflows/web2-luks-rebirth.yml (S1-S13)

## Phase 6 — reboot-seen
- [ ] 6.1 w2l_reboot_seen in scripts/lib/web2-luks-rows.sh; call from w2l_judge and the follow-through; tests

## Phase 7 — registrations
- [ ] 7.1 suite-shard-legs.tsv, suite-durations.tsv, run-registered-suites.sh bounds
- [ ] 7.2 scripts/guard-vacuity-floor.test.sh promoted files
- [ ] 7.3 terraform-target-parity.test.ts (workflow list, census count, five-target pin); escrow-preflight census wording
- [ ] 7.4 model.c4 clause and regenerated model.likec4.json

## Phase 8 — records
- [ ] 8.1 runbook web2-luks-rebirth.md and pointer lines in web-host-birth.md / web-host-replace.md
- [ ] 8.2 ADR-263 addendum (conditioned, dispatch pending); closing checklist

## Phase 9 — verify
- [ ] 9.1 New suites, parity test, lint-guard-contract.py, c4 tests, markdown lint, check-adr-ordinals
- [ ] 9.2 Mutation battery on a sandbox copy per the Guard Contract
- [ ] 9.3 git diff --name-only origin/main...HEAD shows no .tf and no deploy_pipeline_fix trigger file
