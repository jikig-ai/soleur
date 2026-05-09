---
title: "Tasks: Terraform drift fix #3485 (seo_response_headers + deploy_pipeline_fix)"
type: tasks
issue: "#3485"
plan: "knowledge-base/project/plans/2026-05-09-fix-terraform-drift-seo-response-headers-and-deploy-pipeline-fix-3485-plan.md"
date: 2026-05-09
---

# Tasks — #3485 Terraform drift remediation

This is an ops-remediation runbook. No code changes, no PR for code. Tasks are the operator workflow.

## Phase 1 — Confirm both drifts locally

- [ ] 1.1 `cd apps/web-platform/infra && terraform init -input=false`
- [ ] 1.2 Verify `terraform version` reports `Terraform v1.10.5`
- [ ] 1.3 Export R2 creds (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` from Doppler `prd_terraform`)
- [ ] 1.4 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -detailed-exitcode -no-color -input=false -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"`
- [ ] 1.5 Confirm exit code 2 with EXACTLY two resources: `~ cloudflare_ruleset.seo_response_headers` and `-/+ terraform_data.deploy_pipeline_fix`. ABORT if any third resource appears.
- [ ] 1.6 Re-confirm Drift B source (deepen pre-confirmed: #3398/#3400, commit `b1a7c7ec`, 2026-05-07 10:14 — `ci-deploy.sh` poll-ceiling bump to 900s). Re-run `git log -1 --pretty=format:'%H %ai %s' main -- apps/web-platform/infra/{ci-deploy.sh,webhook.service,cat-deploy-state.sh,canary-bundle-claim-check.sh,hooks.json.tmpl}` to confirm no newer trigger-file commit landed since 2026-05-09 plan time.

## Phase 2 — Apply Drift A (`seo_response_headers`) — REQUIRES PER-COMMAND OPERATOR ACK

- [ ] 2.1 Freeze merges: `gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'` returns empty
- [ ] 2.2 Show exact apply command, wait for explicit per-command `go` from operator (no menu-stretch)
- [ ] 2.3 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=cloudflare_ruleset.seo_response_headers -input=false -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"` (no `-auto-approve`; operator types `yes` interactively)
- [ ] 2.4 Confirm "Apply complete! Resources: 0 added, 1 changed, 0 destroyed."
- [ ] 2.5 If Cloudflare API rejects, re-run (idempotent)

## Phase 3 — Apply Drift B (`deploy_pipeline_fix`) — REQUIRES PER-COMMAND OPERATOR ACK

- [ ] 3.1 Re-confirm freeze: `gh pr list --state open --json autoMergeRequest --jq '.[] | select(.autoMergeRequest != null)'` returns empty
- [ ] 3.2 Verify SSH agent: `ssh-add -l | grep -i ed25519`
- [ ] 3.3 L3 firewall pre-check (per `hr-ssh-diagnosis-verify-firewall`): `curl -s ifconfig.me/ip` AND `hcloud firewall describe soleur-web-platform --output json | jq -r '.rules[] | select(.protocol == "tcp" and (.port // "") == "22") | .source_ips[]'` — operator IP must appear in source list. Run `/soleur:admin-ip-refresh` if not. (Firewall name is `soleur-web-platform`, NOT `web-platform-firewall` — verified `apps/web-platform/infra/firewall.tf:2`.)
- [ ] 3.4 Show exact apply command, wait for explicit per-command `go` from operator (Phase 2's ack does NOT stretch)
- [ ] 3.5 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=false -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"` (no `-auto-approve`; operator types `yes` interactively)
- [ ] 3.6 Confirm "Apply complete! Resources: 1 added, 0 changed, 1 destroyed."
- [ ] 3.7 If tainted (SSH provisioner failed), re-run (all provisioner steps idempotent)

## Phase 4 — Verify Drift B via file+systemd contract

- [ ] 4.1 `SERVER_IP=$(terraform output -raw server_ip)`
- [ ] 4.2 Compute local hashes for `ci-deploy.sh`, `canary-bundle-claim-check.sh`, `cat-deploy-state.sh`
- [ ] 4.3 SSH: `sha256sum /usr/local/bin/{ci-deploy,canary-bundle-claim-check,cat-deploy-state}.sh && systemctl is-active webhook`
- [ ] 4.4 Confirm all three remote hashes match local AND `systemctl is-active webhook` returns `active`
- [ ] 4.5 If hash mismatch: `terraform taint terraform_data.deploy_pipeline_fix` then re-apply (Phase 3.5)
- [ ] 4.6 If webhook not active: `journalctl -u webhook --since '5 minutes ago'` and escalate
- [ ] 4.7 Optional liveness sanity: `curl -I https://soleur.ai/health` → HTTP 200

## Phase 5 — Verify Drift A semantics via Cloudflare API

- [ ] 5.1 Source `CF_ZONE_ID` and `CF_API_TOKEN` from Doppler `prd_terraform` (NOT `CLOUDFLARE_ZONE_ID` — Terraform var is `var.cf_zone_id` per `variables.tf:80`)
- [ ] 5.2 GET `/zones/${CF_ZONE_ID}/rulesets/51e84830aab949aeb0c1df8282efa07d`, `jq` for the api.soleur.ai rule
- [ ] 5.3 Confirm `description` ends with `(no-op until proxied — see #3379)` AND `header_value` is `noindex, nofollow` (jq path is `.action_parameters.headers[] | select(.name == "X-Robots-Tag") | .value` — `headers` is an ARRAY, not a map)
- [ ] 5.4 If description still pre-apply: re-run Phase 2

## Phase 6 — Re-verify both drifts gone

- [ ] 6.1 Re-run Phase 1 plan command
- [ ] 6.2 Confirm exit code 0, "No changes. Your infrastructure matches the configuration."
- [ ] 6.3 If a NEW drift surfaces on a different resource, file a separate issue (do not conflate with #3485)

## Phase 7 — Close issue + trigger drift workflow

- [ ] 7.1 `gh issue close 3485 --comment "<two-paragraph close-out: Drift A + Drift B with sha256 evidence and Drift B source PR/SHA from Phase 1.6>"`
- [ ] 7.2 `gh workflow run scheduled-terraform-drift.yml`
- [ ] 7.3 Watch + verify `gh run view "$RUN_ID" --json conclusion --jq .conclusion` returns `success`
- [ ] 7.4 If gate's `DPF_REGEX` did NOT fire on the source PR: file a follow-up against #3043 with empirical grep evidence (do not silently re-widen the regex)

## Out-of-scope / Non-goals

- Structural prevention work — tracked at #3043 / `/ship` Phase 5.5
- Changing the `triggers_replace` expression
- Auditing other `terraform_data.*_install` or other `cloudflare_ruleset.*` resources
- Addressing #3379 (api.soleur.ai DNS-only CNAME) — Drift A only documents the no-op
