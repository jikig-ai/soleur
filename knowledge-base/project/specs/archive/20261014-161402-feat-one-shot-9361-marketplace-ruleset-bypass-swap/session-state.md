# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-04-fix-marketplace-ruleset-bypass-actor-swap-to-soleur-infra-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- No blocking errors. Skeleton checkpoint skipped; terraform plan/apply and ruleset writes not run during planning (read-only live probes only).

### Decisions
- known-gap-9361 annotation in apply-github-infra.yml is NOT edited (keeps the PR off .github/workflows); recorded as DC-1 in decision-challenges.md for the owner.
- Swap keeps the bypass actor's position; depends_on orders the file write after the ruleset; README "depends_on buys nothing" claim rewritten; legacy-arm removal changes only main.tf (var.github_app_* stay declared; variables.tf and ruleset-ci-required.tf belong to sibling PR #9455).
- Tests: T-mp-1d (4 rows) in tests/scripts/test-audit-ruleset-bypass.sh; verifier suite G1.2f, MIN_ASSERTIONS 27 -> 28; ADR-241, C4 and runbook edits ship in the same PR.
- Brand-survival threshold: single-user incident, requires_cpo_signoff true (CPO sign-off with four conditions folded in). Four deferral issues to create before PR-ready.
- Post-merge verification selects the apply run by merge-SHA ancestry; #9361 closes only after the five checks pass.

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; plan-review panel (dhh, kieran, simplicity, architecture, spec-flow, cto, cpo); lint-guard-contract, lint-infra-no-human-steps.
