---
branch: feat-one-shot-12626-webplat-monitor-timeout
issue: 12626
plan: knowledge-base/project/plans/2026-11-11-fix-webplat-monitor-timeout-plan.md
lane: cross-domain
created: 2026-11-11
---

# Tasks — fix(ci): bound webplat mutation batteries (#12626)

Ordered from the plan's Implementation Phases. Technical forks pending CTO
ruling are in `decision-challenges.md` — arm-B assumptions inline.

- [ ] T1. Gate the three battery `run_suite` registrations
      (`approval-guard1-mutation`, `destroy-ask-mutation`,
      `home-census-mutations`) behind `VITEST_SHARD`-unset in the `want_webplat`
      block of `scripts/test-all.sh` (~lines 7387–7395), paired `skip_suite`
      declines naming `test-webplat-mutations`; placed below the unit gate, no
      `_diff_touches` token. (AC-1, AC-2)
- [ ] T2. Add `test-webplat-mutations` job to `.github/workflows/ci.yml`
      (matrix.battery over 3 stems, direct `bash apps/web-platform/test/<b>.test.sh`
      invocation copying the `shard-totality-mutations` job shape, derived
      ceilings); join the `test` aggregator needs/if mirrors; update
      flip-trigger comment. (AC-4)
- [ ] T3. Add the same job to `.github/workflows/main-health-monitor.yml`;
      wire `report` job needs/`R_` env/failure-leg loop/leg-report artifacts;
      re-derive ceiling comments. (AC-3)
- [ ] T4. Update `plugins/soleur/test/main-health-monitor-workflow.test.sh`
      leg census (6 legs), timeout-margin and 360-min envelope expectations;
      add battery-gate coverage assertions per plan Guard Contract (≥3
      mutation-matrix rows incl. dispatch-red). (AC-3, AC-6)
- [ ] T5. Add `_suite_budget_ms()` entries for the three batteries in
      `scripts/test-all.sh`; refresh durations TSVs if the capacity machinery
      consumes them for the new legs. (Property list)
- [ ] T6. Verify required-check surface: enumerate whether branch rulesets pin
      leg names or the `test` aggregator; sync
      `required-checks-merge-group-coverage.test.sh`/ruleset if needed.
      (Dependencies & Risks)
- [ ] T7. Validation: `--list` enumerate check; `VITEST_SHARD=1/2` decline
      run; `test-all-webplat-gate.test.sh` + monitor guard green; post-merge
      `workflow_dispatch` leg-report verification. (AC-5, Phase 3)
