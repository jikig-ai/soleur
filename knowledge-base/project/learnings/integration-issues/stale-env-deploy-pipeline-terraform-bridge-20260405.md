---
module: System
date: 2026-04-05
problem_type: integration_issue
component: tooling
symptoms:
  - "Container has 18 env vars from stale .env while Doppler has 32 secrets"
  - "SENTRY_DSN missing from container — zero Sentry events since inception"
  - "Container has STRIPE_PUBLISHABLE_KEY (removed from Doppler) — stale data"
  - "flock fails with permission denied under ProtectSystem=strict"
root_cause: config_error
resolution_type: config_change
severity: critical
tags: [terraform, doppler, systemd, cloud-init, provisioner, webhook, env-file]
synced_to: []
---

# Troubleshooting: Deploy pipeline uses stale .env instead of Doppler secrets

## Problem

The web-platform deploy pipeline silently used a stale `/mnt/data/.env` file instead of downloading secrets from Doppler. Three compounding issues prevented Doppler secrets from reaching the container: stale ci-deploy.sh with .env fallback, missing EnvironmentFile in the running webhook.service, and ProtectSystem=strict blocking /var/lock for flock.

## Environment

- Module: web-platform infra (Terraform)
- Affected Component: ci-deploy.sh, webhook.service systemd unit, cloud-init.yml
- Date: 2026-04-05

## Symptoms

- Container has only 18 env vars (from stale .env) while Doppler has 32 secrets
- SENTRY_DSN and 13 other newer secrets never reach the container
- `docker exec soleur-web-platform printenv SENTRY_DSN` returns empty
- Container has `STRIPE_PUBLISHABLE_KEY` which was removed from Doppler — confirms stale data
- flock on `/var/lock/ci-deploy.lock` fails under ProtectSystem=strict

## What Didn't Work

**Attempted Solution 1:** Manual SSH fixes (SCP ci-deploy.sh, edit systemd unit)

- **Why it failed:** ProtectSystem=strict blocked /var/lock writes. Manual changes created drift and were reverted per AGENTS.md rule (never modify server state via SSH). Created #1548 to track the Terraform fix.

## Session Errors

**setup-ralph-loop.sh path was wrong on first attempt**

- **Recovery:** Used correct path `./plugins/soleur/scripts/setup-ralph-loop.sh` instead of `./plugins/soleur/skills/one-shot/scripts/`
- **Prevention:** The script lives at the plugin root `scripts/` directory, not inside individual skill directories

## Solution

Added a `terraform_data.deploy_pipeline_fix` resource to `apps/web-platform/infra/server.tf` following the existing `disk_monitor_install` pattern.

**Key changes:**

```hcl
# server.tf — new terraform_data resource
resource "terraform_data" "deploy_pipeline_fix" {
  triggers_replace = sha256(join(",", [
    file("${path.module}/ci-deploy.sh"),
    file("${path.module}/webhook.service"),  # standalone file, not inline string
  ]))

  # file provisioner pushes ci-deploy.sh and webhook.service
  # remote-exec: chmod, daemon-reload, restart webhook, rm -f /mnt/data/.env
}
```

```ini
# cloud-init.yml — one-line change for new servers
ReadWritePaths=/mnt/data /var/lock
```

**Standalone webhook.service file** extracted to avoid trigger hash / remote-exec desync (review P2 finding).

## Why This Works

1. **Root cause:** `server.tf` has `lifecycle { ignore_changes = [user_data] }` on the server resource, so cloud-init changes never propagate to the existing server. The repo version of ci-deploy.sh (hardened, no .env fallback) was never pushed to the server.

2. **terraform_data provisioner** is the established pattern (see `disk_monitor_install`) for bridging the gap between cloud-init (new servers) and existing servers. It uses SSH to push files and run commands, triggered by content hash changes.

3. **Three fixes in one atomic resource:**
   - Push current ci-deploy.sh (no .env fallback, exits on Doppler failure)
   - Write webhook.service with `EnvironmentFile=/etc/default/webhook-deploy` (injects DOPPLER_TOKEN) and `ReadWritePaths=/mnt/data /var/lock` (allows flock)
   - Delete stale `/mnt/data/.env` so deploys fail loudly if Doppler is unavailable

## Prevention

- When `ignore_changes = [user_data]` is set, treat cloud-init as "new servers only" — any config change to existing servers must use a `terraform_data` provisioner
- Extract systemd unit files to standalone files (not inline heredoc strings) so `triggers_replace` can hash the actual file content via `file()`
- When adding `ReadWritePaths` to a ProtectSystem=strict unit, verify the path covers all write operations the service's scripts perform (lock files, temp files, data directories)
- The `EnvironmentFile` directive is the only correct way to inject secrets into systemd services — `/etc/environment` is PAM-only and not read by systemd units

## Related Issues

- See also: [2026-04-03-doppler-not-installed-env-fallback-outage.md](./2026-04-03-doppler-not-installed-env-fallback-outage.md) — Original discovery of the .env fallback
- See also: [sentry-dsn-missing-from-container-env-20260405.md](./sentry-dsn-missing-from-container-env-20260405.md) — Sentry DSN missing confirmation
- See also: [../2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md](../2026-04-03-terraform-data-remote-exec-drift-encrypted-ssh-key.md) — terraform_data provisioner pattern and SSH key pitfall
- See also: [2026-04-05-terraform-doppler-dual-credential-pattern.md](./2026-04-05-terraform-doppler-dual-credential-pattern.md) — Doppler dual credential pattern for terraform apply
