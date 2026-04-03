---
title: "fix: resolve web-platform infrastructure drift — apply terraform_data.doppler_install"
type: fix
date: 2026-04-03
---

# fix: resolve web-platform infrastructure drift — apply terraform_data.doppler_install

## Overview

The scheduled Terraform drift detection workflow ([run #34](https://github.com/jikig-ai/soleur/actions/runs/23956239300)) flagged drift in `apps/web-platform/infra/`. The drift is a single resource: `terraform_data.doppler_install` needs to be created. This resource was added in PR #1496 (merged 2026-04-03 17:48 UTC) but `terraform apply` was never run post-merge to execute the provisioner.

## Problem Statement

PR #1496 added a `terraform_data.doppler_install` resource with a `remote-exec` provisioner to install the Doppler CLI on the existing Hetzner server. The resource was committed and merged, but the corresponding `terraform apply` was listed as a post-merge verification step in the PR and was never executed. The drift detection workflow correctly identified this as exit code 2 (changes detected) and created issue #1505.

### Plan Output (confirmed locally)

```text
Plan: 1 to add, 0 to change, 0 to destroy.

  # terraform_data.doppler_install will be created
  + resource "terraform_data" "doppler_install" {
      + id               = (known after apply)
      + triggers_replace = (sensitive value)
    }
```

## Root Cause

The `terraform_data.doppler_install` resource uses a `remote-exec` provisioner that SSHes into the Hetzner server to:

1. Install the Doppler CLI
2. Write the Doppler service token to `/etc/default/webhook-deploy` (chmod 600)
3. Verify Doppler can access secrets
4. Restart the webhook service

This cannot run in CI (the drift workflow uses a dummy SSH key), so it must be applied locally with real SSH access.

## Proposed Solution

Run `terraform apply` locally from the worktree to execute the `terraform_data.doppler_install` provisioner. This is a one-time operation that will:

1. SSH into the Hetzner server
2. Install the Doppler CLI
3. Configure the service token
4. Restart the webhook service

After apply, the drift detection workflow will report exit code 0 (no changes) on the next run.

### Phase 1: Apply Terraform

```bash
cd apps/web-platform/infra

# Nested doppler invocation (see variables.tf header comment):
# Outer: plain env vars for R2 backend
# Inner: TF_VAR_* for Terraform variables
doppler run -p soleur -c prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform apply \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub" \
    -var="ssh_private_key_path=$HOME/.ssh/id_ed25519" \
    -target=terraform_data.doppler_install
```

### Phase 2: Verify Clean State

```bash
# Run terraform plan again — should show no changes (exit code 0)
doppler run -p soleur -c prd_terraform -- \
  doppler run --token "$(doppler configure get token --plain)" \
    -p soleur -c prd_terraform --name-transformer tf-var -- \
  terraform plan -detailed-exitcode -no-color -input=false \
    -var="ssh_key_path=$HOME/.ssh/id_ed25519.pub" \
    -var="ssh_private_key_path=$HOME/.ssh/id_ed25519"
```

### Phase 3: Verify Doppler on Server

```bash
# SSH into server and verify Doppler is functional
ssh root@$(terraform output -raw server_ipv4) 'doppler --version && \
  set -a; . /etc/default/webhook-deploy; set +a; \
  doppler secrets --only-names --project soleur --config prd | head -5'
```

### Phase 4: Verify Deploy Pipeline

```bash
# Trigger a deploy to verify the webhook uses Doppler successfully
# (The webhook service should restart and use doppler for secrets)
ssh root@$(terraform output -raw server_ipv4) 'systemctl status webhook'
```

### Phase 5: Close Drift Issue

```bash
gh issue close 1505 --comment "Resolved — terraform apply executed doppler_install provisioner. Plan shows 0 changes."
```

## Acceptance Criteria

- [ ] `terraform apply -target=terraform_data.doppler_install` completes successfully
- [ ] `terraform plan` returns exit code 0 (no drift)
- [ ] Doppler CLI is installed on the Hetzner server (`doppler --version` succeeds via SSH)
- [ ] `/etc/default/webhook-deploy` exists with correct permissions (600, deploy:deploy)
- [ ] Webhook service is running and uses Doppler for secrets
- [ ] Issue #1505 is closed

## Test Scenarios

- Given terraform apply targets doppler_install, when executed with real SSH key, then the provisioner runs all 7 inline commands successfully
- Given Doppler is installed on the server, when `doppler --version` is run, then it outputs the installed version
- Given the service token is written to `/etc/default/webhook-deploy`, when `systemctl restart webhook` runs, then the webhook process can access Doppler secrets
- Given terraform apply completed, when `terraform plan -detailed-exitcode` runs, then exit code is 0
- **Drift workflow verify:** `gh workflow run scheduled-terraform-drift.yml`, then poll until complete, then verify web-platform job shows steps 9-11 (issue creation, Discord) as skipped

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure operations task (applying an already-merged Terraform resource).

## Context

### Related Issues and PRs

- Issue #1505: infra: drift detected in web-platform (auto-created by drift workflow)
- Issue #1493: Install Doppler on server and remove .env fallback
- PR #1496: fix: install Doppler on server and remove .env fallback (#1493)
- Issue #1497: Move Doppler into containers for tenant isolation (future)

### Relevant Learnings

- `2026-04-03-doppler-not-installed-env-fallback-outage.md`: Documents the root cause and the `terraform_data.doppler_install` solution
- `2026-03-21-terraform-drift-dead-code-and-missing-secrets.md`: Exit code semantics (0=clean, 1=error, 2=drift)
- `2026-03-29-doppler-service-token-config-scope-mismatch.md`: Doppler service token scoping

### Risk Assessment

**Risk: Low.** This is applying an already-reviewed, already-merged Terraform resource. The `terraform_data` resource with `remote-exec` is idempotent in effect (reinstalling Doppler CLI is safe, overwriting the token file is safe). The `-target` flag limits the apply to only this single resource. No existing resources are modified or destroyed.

## References

- [Terraform terraform_data resource](https://developer.hashicorp.com/terraform/language/resources/terraform-data)
- [Doppler CLI install](https://docs.doppler.com/docs/install-cli)
- Drift workflow: `.github/workflows/scheduled-terraform-drift.yml`
- Infrastructure code: `apps/web-platform/infra/server.tf` (lines 41-70)
