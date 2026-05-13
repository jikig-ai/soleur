---
title: "Tasks: Verify and close terraform_data.deploy_pipeline_fix drift #3620"
lane: procedural
date: 2026-05-13
plan: knowledge-base/project/plans/2026-05-13-fix-terraform-drift-deploy-pipeline-fix-3620-plan.md
issue: "#3620"
---

# Tasks

## Phase 1 — Verify prod state matches the post-apply contract

- [x] 1.1 Verified operator egress IP `82.67.29.121` present in Doppler `ADMIN_IPS` for `prd_terraform` (2026-05-13 verification run).
- [x] 1.2 Resolved prod `SERVER_IP=135.181.45.178` via `terraform output -raw server_ip`.
- [x] 1.3 Computed local SHAs for all 5 file inputs: `ci-deploy.sh=f7635385…`, `ci-deploy-wrapper.sh=b342b50b…`, `webhook.service=cfe827cf…`, `cat-deploy-state.sh=4b8b7071…`, `canary-bundle-claim-check.sh=e0e86ed6…`.
- [x] 1.4 SSH `sha256sum` on prod — all 5 server SHAs match local exactly.
- [x] 1.5 SSH `systemctl is-active webhook` — returned `active`.
- [x] 1.6 SSH `stat -c '%a %U:%G' /etc/webhook/hooks.json` — returned `640 root:deploy`.
- [x] 1.7 `terraform plan -detailed-exitcode` exit 0 — `No changes. Your infrastructure matches the configuration.` `terraform_data.deploy_pipeline_fix` refreshed at id `ebfe7e28-8680-9145-95f6-0f79d34cedd6` (the post-#3712 apply id).

## Phase 2 — Close #3620 as superseded by #3712

- [x] 2.1 Posted close-out comment on #3620 via `gh issue close 3620 --comment "..."` citing the #3712 apply (id `ebfe7e28-…`) and Phase 1 verification.
- [x] 2.2 `gh issue view 3620 --json state | jq -r .state` → `CLOSED`.

## Phase 3 — Commit plan artifacts + open documentation PR

- [x] 3.1 `git add` the plan + tasks + session-state files on `feat-one-shot-3620`; committed `docs: ops-remediation runbook for #3620 (superseded by #3712 apply)` (8c5d3c5a).
- [ ] 3.2 `git push -u origin feat-one-shot-3620` (deferred to `/soleur:ship`).
- [x] 3.3 Draft PR #3735 already exists from one-shot Step 0c (title + body to be updated by `/soleur:ship` Phase 3 to reference `Ref #3620 / Ref #3712`).
- [ ] 3.4 Apply `semver:patch` label; mark ready for review (handled by `/soleur:ship`).
