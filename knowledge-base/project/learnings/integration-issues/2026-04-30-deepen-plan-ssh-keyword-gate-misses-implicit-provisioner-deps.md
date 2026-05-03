---
title: deepen-plan SSH-keyword gate misses implicit SSH deps in terraform apply of provisioner-bearing resources
date: 2026-04-30
category: integration-issues
module: deepen-plan, plan, infra
tags: [terraform, ssh, firewall, provisioner, deepen-plan, hr-ssh-diagnosis-verify-firewall, admin-ip-drift]
related_issues: [3061, 3068, 2681]
related_learnings:
  - 2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md
  - 2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md
  - 2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md
  - 2026-04-19-menu-option-ack-not-authorization-for-prod-writes.md
---

# Learning: deepen-plan SSH-keyword gate misses implicit SSH dependencies in `terraform apply` of provisioner-bearing resources

## Problem

While remediating Terraform drift on `terraform_data.deploy_pipeline_fix` (#3061), the operator's `terraform apply` against `prd_terraform` failed with:

```
Error: file provisioner error
  with terraform_data.deploy_pipeline_fix,
  on server.tf line 234, in resource "terraform_data" "deploy_pipeline_fix":
 234:   provisioner "file" {
timeout - last error: SSH authentication failed (root@135.181.45.178:22):
ssh: handshake failed: read tcp 10.2.0.2:41400->135.181.45.178:22: read:
connection reset by peer
```

This is the L3-firewall-reset signature for admin-IP drift. The operator's egress IP (`185.230.125.20`) was not in the Hetzner firewall `soleur-web-platform` (id `10708450`) allowlist for port 22. Recovery via the canonical runbook (`soleur:admin-ip-refresh` → `terraform apply -target=hcloud_firewall.web` → retry the original apply) succeeded.

The structural surprise: the plan for #3061 was deepened — and AGENTS.md `hr-ssh-diagnosis-verify-firewall` plus deepen-plan Phase 4.5 are *supposed* to catch this. But the gate missed.

## Root Cause

`hr-ssh-diagnosis-verify-firewall` (and `deepen-plan` Phase 4.5 / `plan` Phase 1.4) fire when the **plan body text** mentions SSH/network-connectivity symptom keywords: `reset|timeout|kex|handshake|5xx`.

The #3061 plan body never mentions SSH. Its phases describe the *resource action* (`terraform apply -target=terraform_data.deploy_pipeline_fix`) and a verification path that uses SSH for sha256 checks — but the apply-time SSH dependency is **implicit in the resource definition** (`server.tf:234` has `provisioner "file"` and `provisioner "remote-exec"` blocks). The `file`/`remote-exec` provisioner blocks force terraform to open an SSH connection during the create-step. The plan body has no reason to mention SSH because the operator only sees `terraform apply`.

So the keyword scan sees a plan about Terraform apply with no SSH symptoms and doesn't fire — but the apply itself opens an SSH connection that the firewall must allow.

This is a **trigger-text false negative**. The hard rule is correct; the keyword set under-fires for the case where SSH is implicit (provisioner-bearing resources) rather than explicit (a stated symptom).

## Solution

For this session: standard admin-IP refresh runbook.

For future plans that drive `terraform apply` on a resource with `file`/`remote-exec` provisioners: **the deepen-plan firewall gate must fire on resource-shape signal, not just symptom-text signal.** Concretely, if any plan-cited file (or any file the plan's apply targets) declares `provisioner "file"`, `provisioner "remote-exec"`, or a `connection { type = "ssh" ... }` block, the plan MUST include a pre-apply firewall preflight checkpoint, even if the plan body has zero SSH symptom keywords.

Recommended deepen-plan / plan widening (filed as a follow-up):

```bash
# Existing trigger (deepen-plan Phase 4.5):
RX_SSH='reset|timeout|kex|handshake|5xx'

# Proposed widening — also fire when plan references a provisioner-bearing apply:
RX_PROVISIONER='terraform apply.*-target=.*\b(deploy_pipeline_fix|orphan_reaper_install|disk_monitor_install|fail2ban_tuning|resource_monitor_install|apparmor_bwrap_profile|docker_seccomp_config)\b'
RX_SSH_IMPLICIT='provisioner "file"|provisioner "remote-exec"|connection \{[^}]*type *= *"ssh"'
```

Plus a Sharp Edge in the plan/deepen-plan skills: *"If the plan drives `terraform apply` on a resource with file/remote-exec provisioners, add a Phase 0 firewall preflight even when the plan body has no SSH symptom keywords. The provisioner block makes SSH a hard apply-time dependency."*

## Key Insight

Keyword-text gates miss implicit dependencies. When a resource type *guarantees* a network-layer dependency by its definition, the dependency must be detected at the resource-shape layer, not the prose layer. Trigger sets that scan only the plan's prose will under-fire on every plan that names the operation but not the underlying mechanism.

This is the inverse of the well-known "named-but-not-actually-used" false positive: here the plan *uses* SSH (every apply pass) but never *names* it.

## Session Errors

1. **`terraform apply` failed mid-create with SSH handshake reset.** The operator's egress IP had drifted out of the firewall allowlist while the plan was being deepened. The plan's deepen-pass missed this because the firewall keyword gate scans plan prose for `reset|timeout|handshake|5xx`, none of which appear in a routine `terraform apply` plan body. **Recovery:** ran `soleur:admin-ip-refresh` to add `185.230.125.20/32` to Doppler `ADMIN_IPS` (prd_terraform), then `terraform apply -target=hcloud_firewall.web -auto-approve` to push the change to Hetzner, then retried the original `-target=terraform_data.deploy_pipeline_fix` apply (succeeded in 9s). **Prevention:** widen the deepen-plan Phase 4.5 trigger to also fire on `terraform apply` of provisioner-bearing resources (see Solution); add a Sharp Edge to plan/deepen-plan skills.

2. **Plan AC named the wrong health URL.** Plan ACs said `https://soleur.ai/health` returns HTTP 200; actual response is 301 → `www.soleur.ai/health` → 404. The correct probe for the deployed app is `https://app.soleur.ai/health` (returns 200). **Recovery:** tested both and used the working one for verification. **Prevention:** plan templates that prescribe URL probes should pin the host explicitly and reference the route map (e.g., `app.soleur.ai/health`, not the bare apex). Cheap fix: add a one-line note in the postmerge runbook reference cited by ops-only plans.

3. **Doppler `ADMIN_IPS` and Hetzner firewall were already out of sync before this session.** Doppler had `66.234.146.25/32` which the firewall did not. Cause unknown — most likely a previous session set Doppler but skipped (or failed) the `terraform apply -target=hcloud_firewall.web` step. **Recovery:** the firewall apply this session reconciled both. **Prevention:** the admin-ip-refresh skill emits the apply command but does not run it; the operator-bound step is where drift can creep in. A future enhancement: the skill could `terraform plan -target=hcloud_firewall.web` and warn if Doppler and firewall already differ before the operator's edit lands.

## Tags

category: integration-issues
module: deepen-plan, plan, infra
tags: terraform, ssh, firewall, provisioner, admin-ip-drift, deepen-plan, hr-ssh-diagnosis-verify-firewall
