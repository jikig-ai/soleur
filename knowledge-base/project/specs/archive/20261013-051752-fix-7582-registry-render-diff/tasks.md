# Tasks — fix-7582-registry-render-diff (#7582)

Plan: knowledge-base/project/plans/2026-09-28-fix-registry-dispatcher-render-diff-plan.md

## 1. RED
- [ ] 1.1 Create apps/web-platform/infra/registry-render-delta.test.sh (gate-body rows G1–G8, P1; stubbed gh; equality ledger)
- [ ] 1.2 Extend plugins/soleur/test/registry-host-replace-dispatch-verdict.test.sh (V-new: render_changed + empty commits)
- [ ] 1.3 Extend apps/web-platform/infra/registry-userdata-budget.test.sh (missing tf literal ⇒ exit 2; non-ghcr pin parses)
- [ ] 1.4 Run; record RED output

## 2. GREEN
- [ ] 2.1 registry-userdata-budget.sh reads tf literals; prefix-agnostic pin regex
- [ ] 2.2 Workflow gate: render inputs, server-type arm, render arm, why/render_changed outputs, timeout 5
- [ ] 2.3 setup-terraform (continue-on-error), TERRAFORM_VERSION env, push paths, job timeout 75
- [ ] 2.4 Dispatch REASON + verdict empty-commit arm consume render_changed/why
- [ ] 2.5 Suite registration (suite-shard-legs.tsv if required)

## 3. Docs
- [ ] 3.1 ADR-169 residual amended
- [ ] 3.2 Runbook updated
- [ ] 3.3 zot-registry.tf comment line (AC8 live proof)
