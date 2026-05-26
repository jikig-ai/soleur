---
name: feat-one-shot-3756-cf-tunnel-webhook
description: Task breakdown for replacing deploy_pipeline_fix SSH with CF Tunnel webhook
---

# Tasks: replace deploy_pipeline_fix SSH with CF Tunnel webhook

## Phase 1: Handler script + webhook hook + cloud-init

- [x] 1.0 Preconditions
  - [x] 1.0.1 Verify adnanh/webhook 2.8.2 supports `pass-environment-to-command` for the infra-config hook (same pattern as deploy hook)
  - [x] 1.0.2 Verify `systemd-run --on-active=` availability on Ubuntu 24.04
  - [x] 1.0.3 Verify `deploy` user sudoers for `systemd-run`/`systemctl restart webhook` (deepen-plan finding #2)
- [x] 1.1 Create `apps/web-platform/infra/infra-config-apply.sh` (hardcoded handler)
  - [x] 1.1.1 Read file contents from env vars (set by webhook `pass-environment-to-command`)
  - [x] 1.1.2 Atomic file write (mktemp + mv) for each managed file with hardcoded path/mode/owner
  - [x] 1.1.3 Post-write sequence: chmod, chown, visudo-validate-then-install, daemon-reload
  - [x] 1.1.4 Self-restart via `sudo systemd-run --on-active=3s ...` (deploy user needs sudoers entry)
  - [x] 1.1.5 Code comment block documenting self-restart state machine pattern
- [x] 1.2 Create `apps/web-platform/infra/infra-config-apply.test.sh`
  - [x] 1.2.1 Happy-path file write + permission verification to tmpdir
  - [x] 1.2.2 Missing/empty env var rejection
  - [x] 1.2.3 visudo validation failure halts sudoers install (mock visudo)
  - [x] 1.2.4 Atomic write (no partial file visible at destination)
- [x] 1.3 Edit `apps/web-platform/infra/hooks.json.tmpl`
  - [x] 1.3.1 Add `infra-config` hook entry with HMAC auth + `pass-environment-to-command`
  - [x] 1.3.2 Set `include-command-output-in-response: false` + `success-http-response-code: 202`
- [x] 1.4 Edit `apps/web-platform/infra/webhook.service`
  - [x] 1.4.1 Add `/etc/sudoers.d` to ReadWritePaths
- [x] 1.5 Edit `apps/web-platform/infra/cloud-init.yml`
  - [x] 1.5.1 Add `infra-config-apply.sh` to write_files (b64-encoded)
  - [x] 1.5.2 Update inline webhook.service copy with new ReadWritePaths
- [x] 1.6 Edit `apps/web-platform/infra/server.tf` (cloud-init params)
  - [x] 1.6.1 Add `infra_config_apply_script_b64` parameter to templatefile
- [x] 1.7 Add sudoers entry for webhook self-restart
  - [x] 1.7.1 Add `deploy ALL=(root) NOPASSWD: /usr/bin/systemd-run ...` to `deploy-inngest-bootstrap.sudoers` (or new file)
  - [x] 1.7.2 Update cloud-init sudoers provisioning if new file

## Phase 2: Terraform refactor + push script

- [x] 2.1 Create `apps/web-platform/infra/push-infra-config.sh`
  - [x] 2.1.1 Construct JSON payload with base64-encoded file contents, write to tmpfile (not shell variable)
  - [x] 2.1.2 Compute HMAC-SHA256 via file-based piping: `openssl dgst -sha256 -hmac "$SECRET" < "$TMPFILE" | sed 's/.*= //'`
  - [x] 2.1.3 curl to webhook endpoint with `@"$TMPFILE"` body + HMAC + CF Access headers
  - [x] 2.1.4 Assert HTTP 202
  - [x] 2.1.5 EXIT trap to clean up tmpfile
- [x] 2.2 Edit `apps/web-platform/infra/server.tf` (terraform_data refactor)
  - [x] 2.2.1 Remove `connection {}` block from deploy_pipeline_fix
  - [x] 2.2.2 Remove all `provisioner "file" {}` blocks
  - [x] 2.2.3 Remove `provisioner "remote-exec" {}` block
  - [x] 2.2.4 Add `provisioner "local-exec"` with `environment {}` block for sensitive values
  - [x] 2.2.5 Add infra-config-apply.sh + push-infra-config.sh to `triggers_replace` hash
- [x] 2.3 Run `terraform validate` in apps/web-platform/infra/

## Phase 3: Workflow simplification

- [x] 3.1 Edit `.github/workflows/apply-deploy-pipeline-fix.yml`
  - [x] 3.1.1 Remove cloudflared install step
  - [x] 3.1.2 Remove CF Access SSH token extraction
  - [x] 3.1.3 Remove cloudflared SSH bridge startup + iptables NAT
  - [x] 3.1.4 Remove ssh-agent setup and DEPLOY_SSH_PRIVATE_KEY verification
  - [x] 3.1.5 Remove host-key seeding step
  - [x] 3.1.6 Remove cloudflared teardown step
  - [x] 3.1.7 Remove CLOUDFLARED_VERSION / CLOUDFLARED_SHA256 env vars
  - [x] 3.1.8 Remove "Generate CI public SSH key" step
  - [x] 3.1.9 Remove "Capture local hashes" and "Verify server-side file hashes" steps
  - [x] 3.1.10 Add post-apply verification: poll /hooks/deploy-status 3x at 5s intervals, accept on HTTP 200 + valid JSON

## Phase 4: Documentation

- [x] 4.1 Verify all code comments are adequate (self-restart pattern, bootstrap note, sudoers rationale)
- [x] 4.2 Update PR body with post-merge operator bootstrap instructions
