---
module: Web Platform Infrastructure
date: 2026-04-03
problem_type: integration_issue
component: tooling
symptoms:
  - "GITHUB_APP_ID missing from container environment"
  - "500 error on POST /api/repo/install"
  - "ci-deploy.sh silently falls back to stale /mnt/data/.env"
  - "Doppler CLI not installed on Hetzner server despite cloud-init template"
root_cause: config_error
resolution_type: config_change
severity: critical
tags: [doppler, deploy, secrets, systemd, terraform, cloud-init, env-file]
synced_to: []
---

# Doppler Not Installed on Server — Silent .env Fallback Caused Outage

## Problem

The deploy script (`ci-deploy.sh`) silently fell back to `/mnt/data/.env` when Doppler CLI was unavailable. New secrets added to Doppler `prd` config (`GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY`) never reached the running container because:

1. `cloud-init.yml` had Doppler install instructions, but `server.tf` uses `lifecycle { ignore_changes = [user_data] }` — Terraform never re-runs cloud-init on the existing server
2. Even if Doppler were installed, systemd services do NOT source `/etc/environment` — the `webhook.service` unit had no `EnvironmentFile` directive, so `DOPPLER_TOKEN` was absent from `ci-deploy.sh`'s environment
3. `resolve_env_file()` silently fell back to the stale `.env` file with no error logging

## Root Cause

Three compounding failures:

- **Provisioning gap:** `ignore_changes = [user_data]` means cloud-init changes are never applied to existing servers
- **systemd environment misunderstanding:** `/etc/environment` is sourced by PAM (login sessions), not by systemd service units
- **Silent fallback:** `resolve_env_file()` treated Doppler unavailability as a non-fatal warning

## Solution

### 1. terraform_data provisioner (one-time bootstrap)

Added `terraform_data.doppler_install` with `remote-exec` to install Doppler CLI on the existing server and write the service token to `/etc/default/webhook-deploy` (chmod 600, deploy:deploy).

### 2. systemd EnvironmentFile

Added `EnvironmentFile=/etc/default/webhook-deploy` to the `webhook.service` unit in cloud-init. Token stored only in this restricted file — NOT in `/etc/environment` (world-readable).

### 3. Hardened resolve_env_file()

Removed all `.env` fallback paths. The function now exits with specific error messages:

- "Doppler CLI not installed on this server" (exit 1)
- "DOPPLER_TOKEN environment variable not set" (exit 1)
- "Failed to download secrets from Doppler" (exit 1)

### 4. Security hardening from review

- Removed `DOPPLER_TOKEN` from `/etc/environment` (world-readable, served no functional purpose since only root SSHes in)
- Token verification now sources from `/etc/default/webhook-deploy` instead of inline env prefix (avoids `/proc/<pid>/cmdline` exposure)
- Parameterized SSH private key path for CI compatibility

## Key Insight

**systemd does NOT source `/etc/environment`.** This is a common misconception. `/etc/environment` is read by PAM during interactive login sessions (SSH, `su`, `login`). Systemd services must use `EnvironmentFile=` directives to receive environment variables. Always use dedicated env files with restricted permissions for service tokens.

**Silent fallbacks mask production failures.** The `.env` fallback made the deploy "succeed" with stale secrets, which is worse than failing loudly. Hard failures with specific error messages enable rapid diagnosis.

## Prevention

- When adding secrets to Doppler, verify they reach the running container (not just the Doppler dashboard)
- Never use `/etc/environment` for service tokens — always use `EnvironmentFile` with restricted permissions
- Deploy scripts should fail hard when the primary secrets source is unavailable
- When cloud-init has `ignore_changes`, use a `terraform_data` provisioner to bridge the gap for existing servers

## Session Errors

1. **Test mock setup caused incorrect failures** — The `run_deploy_doppler` helper used a generic loop for mock creation with `exec "$@"` patterns that caused unexpected exit 127 errors. Recovery: rewrote mocks using explicit per-command scripts matching existing test patterns. **Prevention:** When adding new test helpers, copy the exact mock pattern from existing helpers rather than abstracting.

2. **Real `doppler` binary leaked into test PATH** — `MOCK_DOPPLER_MISSING=1` didn't prevent the real `doppler` at `~/.local/bin/doppler` from being found because the test prepended MOCK_DIR to PATH without restricting the rest. Recovery: restricted PATH to `MOCK_DIR + standard system dirs`. **Prevention:** Test helpers that simulate "binary not installed" must use a restricted PATH, not just prepend a mock directory.

3. **Wrong script path for setup-ralph-loop.sh** — First attempt used `./plugins/soleur/skills/one-shot/scripts/` instead of `./plugins/soleur/scripts/`. Recovery: corrected the path. **Prevention:** Verify script paths exist before invoking them; the one-shot skill should use the correct base path.

## References

- Issue: #1493
- Related: `knowledge-base/project/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
- Related: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Filed for future: #1497 (move Doppler into containers for tenant isolation)
