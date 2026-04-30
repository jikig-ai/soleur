---
spec: feat-one-shot-3061-tf-drift
plan: knowledge-base/project/plans/2026-04-30-fix-terraform-drift-deploy-pipeline-fix-3061-plan.md
issue: "#3061"
classification: ops-only-prod-write
date: 2026-04-30
---

# Tasks: Fix Terraform drift on `terraform_data.deploy_pipeline_fix` (#3061)

> **Ops runbook.** No code change, no PR. Operator runs `terraform apply -target=...` against `prd_terraform`, verifies via file+systemd contract, then closes #3061.

## Phase 1 — Confirm drift source locally

- [ ] 1.1 `cd apps/web-platform/infra` from the worktree
- [ ] 1.2 Extract R2 backend creds: `export AWS_ACCESS_KEY_ID=$(doppler secrets get AWS_ACCESS_KEY_ID -p soleur -c prd_terraform --plain)` and `AWS_SECRET_ACCESS_KEY` (same form)
- [ ] 1.3 `terraform init -input=false`
- [ ] 1.4 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -detailed-exitcode -no-color -input=false -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"`
- [ ] 1.5 Verify exit code 2, plan names ONLY `terraform_data.deploy_pipeline_fix` (1 to add, 0 to change, 1 to destroy). If any other resource appears in the plan, abort and escalate.

## Phase 2 — Apply (per-command operator ack)

- [ ] 2.1 Confirm no PR is in merge queue: `gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'` → expect empty
- [ ] 2.2 Verify SSH agent has prod private key: `ssh-add -l | grep -i ed25519`
- [ ] 2.3 **Show the exact apply command and wait for explicit `go` from the operator** (no menu-option ack, no `-auto-approve`):

  ```bash
  doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
    terraform apply -target=terraform_data.deploy_pipeline_fix -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"
  ```

- [ ] 2.4 Operator reviews terraform's interactive plan output and types `yes`
- [ ] 2.5 Apply completes: "Apply complete! Resources: 1 added, 0 changed, 1 destroyed."
- [ ] 2.6 If tainted (provisioner failure mid-apply), re-run the same command — all provisioner steps are idempotent

## Phase 3 — Verify production via file+systemd contract

- [ ] 3.1 `SERVER_IP=$(cd apps/web-platform/infra && terraform output -raw server_ip)`
- [ ] 3.2 Compute local hashes:
  - `LOCAL_CI_HASH=$(sha256sum apps/web-platform/infra/ci-deploy.sh | awk '{print $1}')`
  - `LOCAL_CANARY_HASH=$(sha256sum apps/web-platform/infra/canary-bundle-claim-check.sh | awk '{print $1}')`
  - `LOCAL_CAT_HASH=$(sha256sum apps/web-platform/infra/cat-deploy-state.sh | awk '{print $1}')`
- [ ] 3.3 SSH and check: `ssh -o ConnectTimeout=5 root@"$SERVER_IP" "sha256sum /usr/local/bin/ci-deploy.sh /usr/local/bin/canary-bundle-claim-check.sh /usr/local/bin/cat-deploy-state.sh && systemctl is-active webhook"`
- [ ] 3.4 Verify each remote sha256 matches the corresponding `LOCAL_*_HASH`
- [ ] 3.5 Verify `systemctl is-active webhook` returns `active`
- [ ] 3.6 (Optional liveness sanity) `curl -I https://soleur.ai/health` → expect HTTP 200
- [ ] 3.7 Do NOT use the legacy `curl -H X-Signature-256: ... https://deploy.soleur.ai/hooks/deploy-status` probe — it returns HTTP 403 from CF Access on anonymous probes

## Phase 4 — Re-verify drift is gone

- [ ] 4.1 Re-run the Phase 1 plan command; expect exit code 0 ("No changes. Your infrastructure matches the configuration.")
- [ ] 4.2 If a different resource drifts now, file a separate `infra-drift` issue (do NOT conflate with #3061)

## Phase 5 — Close issue + trigger drift workflow

- [ ] 5.1 Close #3061 with a Phase-4 verification comment via `gh issue close 3061 --comment "..."` (see plan §Phase 5 for canonical comment text)
- [ ] 5.2 Trigger the drift workflow: `gh workflow run scheduled-terraform-drift.yml`
- [ ] 5.3 Watch and verify success: `RUN_ID=$(gh run list --workflow scheduled-terraform-drift.yml --limit 1 --json databaseId --jq '.[0].databaseId')` then `gh run watch "$RUN_ID"` then `gh run view "$RUN_ID" --json conclusion --jq .conclusion` → expect `success`

## Capture (compound) — recurrence pattern + structural follow-up

- [ ] 6.1 Confirmed during deepen-plan: the `/ship` Phase 5.5 `DPF_REGEX` at `plugins/soleur/skills/ship/SKILL.md:448` is **stale** — it lists 4 files but `triggers_replace` now hashes 5 (the 5th being `canary-bundle-claim-check.sh`, added in #3042 / 87bc9227). PR #3042 thus did NOT trigger the gate at merge time, which is the proximate cause of #3061. **File a follow-up enhancement issue** (post-apply, separate from the remediation) titled "Widen /ship Phase 5.5 DPF_REGEX to match all triggers_replace inputs (and add a regression test parsing server.tf)". Milestone: Post-MVP / Later. Reference: this plan's Research Insights section.
- [ ] 6.2 No new learning file needed for the drift class itself — both `knowledge-base/project/learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` and `2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` cover it. The deepen-plan finding (gate-stale regex) is recorded in the plan's Research Insights and tracked via the follow-up issue from 6.1.
