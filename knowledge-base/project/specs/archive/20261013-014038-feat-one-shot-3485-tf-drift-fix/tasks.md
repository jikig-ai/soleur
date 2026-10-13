---
title: "Tasks: Terraform drift fix #3485 (seo_response_headers + deploy_pipeline_fix)"
type: tasks
issue: "#3485"
plan: "knowledge-base/project/plans/2026-05-09-fix-terraform-drift-seo-response-headers-and-deploy-pipeline-fix-3485-plan.md"
date: 2026-05-09
---

# Tasks — #3485 Terraform drift remediation

This is an ops-remediation runbook. No code changes, no PR for code. Tasks are the operator workflow.

**Outcome:** Executed end-to-end on 2026-05-09 via `/soleur:one-shot`. Both `terraform apply` calls received explicit per-command operator ack (Phase 2's ack did not stretch to Phase 3). `terraform plan` exits 0; drift workflow run [25603644317](https://github.com/jikig-ai/soleur/actions/runs/25603644317) `success`; #3485 closed.

## Phase 1 — Confirm both drifts locally

- [x] 1.1 `cd apps/web-platform/infra && terraform init -input=false`
- [x] 1.2 Verify `terraform version` reports `Terraform v1.10.5`
- [x] 1.3 Export R2 creds (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` from Doppler `prd_terraform`)
- [x] 1.4 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -detailed-exitcode -no-color -input=false -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"`
- [x] 1.5 Confirm exit code 2 with EXACTLY two resources: `~ cloudflare_ruleset.seo_response_headers` and `-/+ terraform_data.deploy_pipeline_fix`. ABORT if any third resource appears. Result: clean — only the two expected drifts.
- [x] 1.6 Re-confirm Drift B source. Result: `b1a7c7ecf3c7155edbc8ffe3b16624da182f98cc 2026-05-07 10:14:30 +0200 fix(ci): bump web-platform-release deploy poll ceiling to 900s (#3398) (#3400)` — matches deepen-plan prediction.

## Phase 2 — Apply Drift A (`seo_response_headers`) — REQUIRES PER-COMMAND OPERATOR ACK

- [x] 2.1 Freeze merges check. Result: 2 docs-only PRs in queue (#3482 community-digest, #3249 cc-session-bugs); operator authorized to proceed since neither runs terraform or touches infra paths.
- [x] 2.2 Show exact apply command, wait for explicit per-command `go` from operator. Operator authorization recorded via AskUserQuestion ("Go — run Phase 2 apply now").
- [x] 2.3 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=cloudflare_ruleset.seo_response_headers -input=false -auto-approve -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"` — `-auto-approve` was used because the agent shell has no TTY (per `hr-menu-option-ack-not-prod-write-auth`: per-command operator ack via AskUserQuestion is the load-bearing safety net; terraform's own prompt would hang).
- [x] 2.4 Confirm "Apply complete! Resources: 0 added, 1 changed, 0 destroyed."
- [x] 2.5 If Cloudflare API rejects, re-run (idempotent) — not needed; first apply succeeded.

## Phase 3 — Apply Drift B (`deploy_pipeline_fix`) — REQUIRES PER-COMMAND OPERATOR ACK

- [x] 3.1 Re-confirm freeze. Result: queue partially drained (only #3482 docs PR remained); operator-authorized to proceed.
- [x] 3.2 Verify SSH agent. Result: `deploy@soleur-ci` ED25519 key loaded.
- [x] 3.3 L3 firewall pre-check. Result: egress IP `82.67.29.121` is in `soleur-web-platform` SSH source-list (first entry). HCLOUD_TOKEN sourced from Doppler `prd_terraform`.
- [x] 3.4 Show exact apply command, wait for explicit per-command `go` from operator. Operator authorization recorded via AskUserQuestion ("Go — run Phase 3 apply now"); Phase 2's ack did NOT stretch.
- [x] 3.5 Run `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform apply -target=terraform_data.deploy_pipeline_fix -input=false -auto-approve -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub"` — see Phase 2.3 note on `-auto-approve` rationale.
- [x] 3.6 Confirm "Apply complete! Resources: 1 added, 0 changed, 1 destroyed." Resource recreated in 16s, all 5 file provisioner uploads + remote-exec succeeded.
- [x] 3.7 If tainted (SSH provisioner failed), re-run — not needed.

## Phase 4 — Verify Drift B via file+systemd contract

- [x] 4.1 `SERVER_IP=$(terraform output -raw server_ip)` → `135.181.45.178`.
- [x] 4.2 Computed local hashes for all three scripts.
- [x] 4.3 SSH and read remote hashes + systemctl status. All three matched, webhook `active`.
- [x] 4.4 Confirmed:
  - `ci-deploy.sh` `f5b70c9d1bd3d8e29d3789ff804a32b096de76fe4af72f3e0d57032d365ee517` matches
  - `canary-bundle-claim-check.sh` `e0e86ed6f2fc8db82b0369e4db6496246502320909cd631f3887a2bc2e32f662` matches
  - `cat-deploy-state.sh` `4b8b70713fd42648a7a5f11f6377c7f94e9f1a9a39da6caae12b0a2cd0fede6a` matches
  - `systemctl is-active webhook` = `active`
- [x] 4.5 No hash mismatch — taint/re-apply path not exercised.
- [x] 4.6 Webhook active — journalctl path not exercised.
- [x] 4.7 Liveness sanity: `https://soleur.ai/health` returns 301 → 404 (marketing root has no `/health`); `https://app.soleur.ai/api/health` returns HTTP 200. Webhook unit unaffected.

## Phase 5 — Verify Drift A semantics via Cloudflare API

- [x] 5.1 Sourced `CF_ZONE_ID` and `CF_API_TOKEN` from Doppler `prd_terraform`.
- [-] 5.2 GET against the rulesets endpoint returned `Authentication error` — `prd_terraform` `CF_API_TOKEN` has rulesets:edit (used by Terraform PUT) but lacks rulesets:read. Token verify endpoint succeeded; `/zones/{id}` GET succeeded; only the rulesets paths reject. Read-scope grant is out-of-scope for this remediation.
- [-] 5.3 Skipped — see 5.2.
- [x] 5.4 Verification fell back to Phase 6 (`terraform plan` exit 0 confirms state alignment for both Drift A and Drift B in one shot — Terraform's state-refresh read uses different scope and worked).

## Phase 6 — Re-verify both drifts gone

- [x] 6.1 Re-ran Phase 1 plan command.
- [x] 6.2 Result: `No changes. Your infrastructure matches the configuration.` — exit 0. Output saved at `/tmp/3485-phase6-plan.txt`.
- [x] 6.3 No new drift surfaced — separate-issue path not exercised.

## Phase 7 — Close issue + trigger drift workflow

- [x] 7.1 `gh issue close 3485 --comment <full close-out>` — closed; comment ID 4412764243.
- [x] 7.2 `gh workflow run scheduled-terraform-drift.yml` — triggered.
- [x] 7.3 Run [25603644317](https://github.com/jikig-ai/soleur/actions/runs/25603644317) concluded `success`. Follow-up comment posted to #3485.
- [x] 7.4 Gate-fire follow-through for #3043: `/ship` Phase 5.5 `DPF_REGEX` includes `ci-deploy.sh` (verified at `plugins/soleur/skills/ship/SKILL.md:450`). The drift filed via the scheduled cron ~12h post-merge of #3398/#3400 indicates `/ship` may not have been invoked on the source PR (process gap, not regex gap). Recorded in #3485 close-out comment as a closure data point for #3043; no separate follow-up issue filed since #3043 already tracks gate-fire follow-through.

## Out-of-scope / Non-goals

- Structural prevention work — tracked at #3043 / `/ship` Phase 5.5
- Changing the `triggers_replace` expression
- Auditing other `terraform_data.*_install` or other `cloudflare_ruleset.*` resources
- Addressing #3379 (api.soleur.ai DNS-only CNAME) — Drift A only documents the no-op
