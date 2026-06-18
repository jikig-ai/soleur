---
issue: 5515
lane: single-domain
plan: knowledge-base/project/plans/2026-06-18-fix-deploy-pipeline-depends-on-handler-bootstrap-plan.md
---

# Tasks — fix(infra): order webhook push after handler bridge (#5515)

## Phase 1 — RED (regression tests first)

- [ ] 1.1 In `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`, add **Test 1** (the `depends_on` edge): bound the `terraform_data "deploy_pipeline_fix"` block with the existing top-level-block regex (`:231-246`), then a FRESH `/depends_on\s*=\s*\[([\s\S]*?)\]/` match; assert it contains BOTH `terraform_data.apparmor_bwrap_profile` AND `terraform_data.infra_config_handler_bootstrap`. (Do NOT reuse the `triggers_replace` join extractor.)
- [ ] 1.2 Add **Test 2** (co-targeting invariant, SpecFlow P0-A): read `APPLY_DPF_WORKFLOW`, assert the `terraform apply` step co-`-target`s BOTH `terraform_data.deploy_pipeline_fix` AND `terraform_data.infra_config_handler_bootstrap`.
- [ ] 1.3 Add a header comment to both tests citing #5515 + the `missing_env`/one-apply-late rationale.
- [ ] 1.4 Run `cd <repo-root> && bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — Test 1 MUST be RED (edge not yet added); Test 2 should already be GREEN (workflow already co-targets).

## Phase 2 — GREEN (the fix)

- [ ] 2.1 In `apps/web-platform/infra/server.tf`, add `terraform_data.infra_config_handler_bootstrap` to `deploy_pipeline_fix`'s `depends_on` (`:578`): `depends_on = [terraform_data.apparmor_bwrap_profile, terraform_data.infra_config_handler_bootstrap]`.
- [ ] 2.2 Rewrite the stale `#4827/#4829 — deliberately NO depends_on` comment block (`:566-577`): cite #5515; name the `missing_env`/`hooks.json` one-apply-late mechanism (`infra-config-apply.sh:105-112`); preserve the helper/sudoers `install_rejected` distinction; note the accepted over-coupling trade-off (operator-local apply now recreates the idempotent bridge); note the secondary restart-serialization benefit (`server.tf:529` before `:637`).
- [ ] 2.3 Audit BOTH workflows' concurrency-group comments (SpecFlow P1-A): `grep -n "depends_on" .github/workflows/apply-deploy-pipeline-fix.yml .github/workflows/apply-web-platform-infra.yml`; update the rationale to reflect the now-two-element `depends_on`; confirm the comment states the other workflow's overlap surface is unchanged (it targets only `apparmor_bwrap_profile`).
- [ ] 2.4 Run the gate suite — Test 1 now GREEN; Test 2 still GREEN.

## Phase 3 — Verify

- [ ] 3.1 AC1: `grep -n "depends_on" apps/web-platform/infra/server.tf` shows both elements.
- [ ] 3.2 AC2: `grep -n "deliberately NO depends_on" server.tf` returns nothing; `grep -n "5515" server.tf` returns the new comment.
- [ ] 3.3 AC3: `cd apps/web-platform/infra && terraform init -backend=false && terraform validate` passes (no cycle). Note in PR that the durable cycle guard is the prod `terraform plan` step (SpecFlow P1-B).
- [ ] 3.4 AC4/AC5/AC7: full `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` green.
- [ ] 3.5 AC6: PR body uses `Closes #5515`.
