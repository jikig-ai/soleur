---
title: "fix: install Doppler on server and remove .env fallback"
type: fix
date: 2026-04-03
issue: "#1493"
deepened: 2026-04-03
---

# fix: Install Doppler on Server and Remove .env Fallback

## Enhancement Summary

**Deepened on:** 2026-04-03
**Sections enhanced:** 4 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios)
**Research sources:** Terraform docs (Context7), Doppler service token learnings, systemd environment semantics, existing cloud-init/deploy patterns

### Key Improvements

1. **Use `terraform_data` instead of `null_resource`** -- built into Terraform core (no extra provider), modern replacement recommended by HashiCorp for Terraform >= 1.4
2. **Critical bug found: systemd does not inherit `/etc/environment`** -- the webhook.service unit lacks `EnvironmentFile`, so `DOPPLER_TOKEN` would not reach `ci-deploy.sh` even after installation. Fix: create a dedicated `/etc/default/webhook-deploy` environment file
3. **Added pre-apply `.env` audit step** to prevent data loss from secrets present in `.env` but missing from Doppler

### New Considerations Discovered

- Systemd services do not source `/etc/environment` (PAM login sessions do) -- a dedicated `EnvironmentFile` directive is required
- `terraform_data` eliminates the `hashicorp/null` provider dependency and uses `triggers_replace` (cleaner API)
- CI drift workflows only run `terraform plan`, so the provisioner connection block is never evaluated in CI (safe)

## Overview

The deploy script (`ci-deploy.sh`) silently falls back to `/mnt/data/.env` when Doppler CLI is unavailable on the Hetzner server. This caused a production outage -- `GITHUB_APP_ID` and `GITHUB_APP_PRIVATE_KEY` were added to the Doppler `prd` config but never reached the running container because the server lacks Doppler CLI despite the cloud-init template already containing install instructions.

## Problem Statement

The `cloud-init.yml` template already includes Doppler CLI installation (lines 125-128) and persists the service token to `/etc/environment`. However, `server.tf` has `lifecycle { ignore_changes = [user_data] }`, which means Terraform never re-runs cloud-init on the existing server. The Doppler install was added to cloud-init after initial provisioning, so it has never actually executed.

When `ci-deploy.sh` runs on the server:

1. `resolve_env_file()` checks `command -v doppler` -- fails (not installed)
2. Falls back to `/mnt/data/.env` -- a stale flat file missing recent secrets
3. Container starts with incomplete environment
4. `GITHUB_APP_ID` missing causes 500 errors on `POST /api/repo/install`

## Proposed Solution

### Phase 1: Install Doppler on Existing Server (SSH Provisioner)

Add a Terraform `terraform_data` resource with `remote-exec` provisioner to install Doppler CLI on the running server and configure the service token for the webhook systemd unit. This is a one-time bootstrap that bridges the gap between current server state and what cloud-init would provide on reprovisioning.

**Files changed:**

- `apps/web-platform/infra/server.tf` -- add `terraform_data.doppler_install` with `remote-exec`

```hcl
resource "terraform_data" "doppler_install" {
  # Re-run when doppler_token changes (forces re-provisioning of the token file)
  triggers_replace = sha256(var.doppler_token)

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = file("~/.ssh/id_ed25519")
  }

  provisioner "remote-exec" {
    inline = [
      # Install Doppler CLI (idempotent -- re-running is safe)
      "curl -Ls --tlsv1.2 --proto '=https' --retry 3 https://cli.doppler.com/install.sh | sh",
      # Persist token in /etc/environment for login sessions
      "grep -q '^DOPPLER_TOKEN=' /etc/environment && sed -i 's|^DOPPLER_TOKEN=.*|DOPPLER_TOKEN=${var.doppler_token}|' /etc/environment || echo 'DOPPLER_TOKEN=${var.doppler_token}' >> /etc/environment",
      # Create dedicated env file for webhook systemd service
      # (systemd does NOT source /etc/environment -- it uses PAM login sessions only)
      "printf 'DOPPLER_TOKEN=%s\\n' '${var.doppler_token}' > /etc/default/webhook-deploy",
      "chmod 600 /etc/default/webhook-deploy",
      "chown deploy:deploy /etc/default/webhook-deploy",
      # Verify installation
      "doppler --version",
      # Verify token works (non-destructive read)
      "DOPPLER_TOKEN=${var.doppler_token} doppler secrets --only-names --project soleur --config prd | head -5",
    ]
  }

  depends_on = [hcloud_server.web]
}
```

### Research Insights (Phase 1)

**Use `terraform_data` instead of `null_resource`:**

- `terraform_data` is built into Terraform core (available since v1.4) -- no `hashicorp/null` provider needed
- Uses `triggers_replace` (single value that triggers replacement) instead of `triggers` (map) -- cleaner API
- HashiCorp documentation explicitly recommends `terraform_data` as the replacement for `null_resource` provisioner patterns
- The project uses Terraform >= 1.6 (installed: 1.10.5), so `terraform_data` is available

**Critical: systemd environment inheritance:**

- `/etc/environment` is sourced by PAM during login sessions (SSH, `su`, `login`)
- Systemd services do NOT source `/etc/environment` -- they use `EnvironmentFile=` directives
- The `webhook.service` unit runs as `User=deploy` but has no `EnvironmentFile` directive
- Without this fix, `DOPPLER_TOKEN` would be absent from `ci-deploy.sh`'s environment even after Doppler is installed
- Solution: create `/etc/default/webhook-deploy` with just `DOPPLER_TOKEN` (principle of least privilege -- don't expose all of `/etc/environment` to the webhook process)
- The webhook.service unit must add `EnvironmentFile=/etc/default/webhook-deploy` (see Phase 1b below)

**CI safety:**

- Provisioners only execute during `terraform apply`, not `terraform plan`
- The CI drift workflow runs plan-only, so the SSH connection block is never evaluated in CI
- The resource will show as "will be created" in drift checks but will not cause failures

**Why `terraform_data` instead of reprovisioning:** Reprovisioning (removing `ignore_changes`) would destroy and recreate the server, causing extended downtime and data migration complexity. The `terraform_data` with `remote-exec` runs against the live server without disruption.

**Why not `hcloud_server` user_data update:** Even if we removed `ignore_changes = [user_data]`, changing user_data forces server replacement in Hetzner. Cloud-init only runs at first boot.

### Phase 1b: Add EnvironmentFile to webhook.service

The `webhook.service` systemd unit in `cloud-init.yml` must include an `EnvironmentFile` directive so that `ci-deploy.sh` (invoked by the webhook listener) has `DOPPLER_TOKEN` in its environment.

**File changed:** `apps/web-platform/infra/cloud-init.yml` (webhook.service section)

Add under the `[Service]` section:

```ini
EnvironmentFile=/etc/default/webhook-deploy
```

The `terraform_data.doppler_install` provisioner creates this file on the existing server. For newly provisioned servers, cloud-init's `runcmd` must also create it (same content as the provisioner).

Additionally, the `terraform_data` provisioner should restart the webhook service after writing the environment file so the running process picks up the new variable:

```bash
"systemctl restart webhook || true",
```

The `|| true` handles the case where webhook.service hasn't started yet (first-time provisioning).

### Phase 2: Harden ci-deploy.sh (Remove .env Fallback)

Update `resolve_env_file()` to fail hard when Doppler is unavailable instead of silently falling back to the stale `.env` file.

**File changed:** `apps/web-platform/infra/ci-deploy.sh`

Current behavior of `resolve_env_file()`:

```bash
# Falls back to /mnt/data/.env silently
resolve_env_file() {
  if command -v doppler >/dev/null 2>&1 && [[ -n "${DOPPLER_TOKEN:-}" ]]; then
    # ... try Doppler ...
  fi
  echo "/mnt/data/.env"  # Silent fallback
}
```

New behavior:

```bash
resolve_env_file() {
  if ! command -v doppler >/dev/null 2>&1; then
    logger -t "$LOG_TAG" "FATAL: Doppler CLI not installed"
    echo "Error: Doppler CLI not installed on this server" >&2
    exit 1
  fi

  if [[ -z "${DOPPLER_TOKEN:-}" ]]; then
    logger -t "$LOG_TAG" "FATAL: DOPPLER_TOKEN not set"
    echo "Error: DOPPLER_TOKEN environment variable not set" >&2
    exit 1
  fi

  local tmpenv
  tmpenv=$(mktemp /tmp/doppler-env.XXXXXX)
  chmod 600 "$tmpenv"
  if doppler secrets download --no-file --format docker --project soleur --config prd > "$tmpenv" 2>/dev/null; then
    echo "$tmpenv"
    return 0
  fi

  rm -f "$tmpenv"
  logger -t "$LOG_TAG" "FATAL: Doppler secrets download failed"
  echo "Error: Failed to download secrets from Doppler" >&2
  exit 1
}
```

Also simplify `cleanup_env_file()` -- since `resolve_env_file()` now always returns a temp file path or exits, the `/mnt/data/.env` guard is dead code:

```bash
# Before:
cleanup_env_file() {
  if [[ "$1" != "/mnt/data/.env" ]]; then
    rm -f "$1"
  fi
}

# After:
cleanup_env_file() {
  rm -f "$1"
}
```

### Research Insights (Phase 2)

**Error message specificity:**

- Each failure mode gets a distinct error message (`not installed`, `not set`, `download failed`) to enable rapid diagnosis from syslog without SSH access
- All errors go to both stderr (for webhook response inspection) and syslog via `logger` (for persistent audit trail)
- The `FATAL` prefix in logger messages distinguishes hard failures from warnings in log queries

**Edge case: `doppler secrets download` stderr suppression:**

- The `2>/dev/null` on the `doppler secrets download` line suppresses Doppler's stderr output (which includes progress bars and auth error details)
- This is intentional: stderr from Doppler could contain the service token in error messages
- The generic "Failed to download secrets" message is sufficient; detailed Doppler errors are available by running the command interactively on the server

**Interaction with `set -euo pipefail`:**

- `exit 1` inside `resolve_env_file()` terminates the entire script due to `set -e`
- The ERR trap (line 13) fires before exit, logging the failing line number
- This is correct behavior -- the function never returns a value on failure, it always exits

### Phase 2b: Pre-Removal .env Audit

**Before removing the `.env` fallback**, audit the existing server `.env` file to ensure every secret is present in Doppler `prd` config. This prevents data loss from secrets that were added to `.env` manually but never synced to Doppler.

```bash
# SSH into server and extract .env key names
ssh root@<server-ip> "grep -v '^#' /mnt/data/.env | grep '=' | cut -d= -f1 | sort" > /tmp/server-env-keys.txt

# Get Doppler prd key names
doppler secrets --only-names -p soleur -c prd 2>/dev/null | sort > /tmp/doppler-prd-keys.txt

# Find keys in .env but missing from Doppler
comm -23 /tmp/server-env-keys.txt /tmp/doppler-prd-keys.txt
```

If any keys are missing from Doppler, add them before proceeding to Phase 3. Per the learning in `2026-03-25-doppler-secret-audit-before-creation.md`, also check all other Doppler configs (`dev`, `ci`, `prd_terraform`) -- the value may exist elsewhere.

### Phase 3: Clean Up .env References

Remove the `/mnt/data/.env` creation and references from cloud-init since Doppler is now the sole secrets source.

**File changed:** `apps/web-platform/infra/cloud-init.yml`

- Remove the `.env` placeholder creation block (lines 156-163: `touch /mnt/data/.env`, `chmod`, comments about populating it)
- Replace the `.env` fallback logic in the initial `docker run` block at the bottom of runcmd (lines 206-227) with Doppler-only logic: download secrets to temp file via `doppler secrets download`, pass as `--env-file`, delete temp file after container starts. No fallback to `/mnt/data/.env`.
- Add creation of `/etc/default/webhook-deploy` in runcmd (for newly provisioned servers):

```yaml
# Create dedicated env file for webhook service (systemd does not source /etc/environment)
- printf 'DOPPLER_TOKEN=%s\n' '${doppler_token}' > /etc/default/webhook-deploy
- chmod 600 /etc/default/webhook-deploy
- chown deploy:deploy /etc/default/webhook-deploy
```

- Add `EnvironmentFile=/etc/default/webhook-deploy` to the webhook.service unit definition in the `write_files` section
- Update `apps/web-platform/.env.example` header comment to remove the "Copy this file to /mnt/data/.env on the production server" instruction, replacing it with a note that production uses Doppler

### Phase 4: Verify on Live Server

After `terraform apply`:

1. SSH into server, verify `doppler --version` works
2. Verify `DOPPLER_TOKEN` is set in environment: `grep DOPPLER_TOKEN /etc/environment`
3. Verify Doppler can fetch secrets: `source /etc/environment && DOPPLER_TOKEN=$DOPPLER_TOKEN doppler secrets --only-names --project soleur --config prd | head -5`
4. Trigger a test deploy to verify `ci-deploy.sh` uses Doppler successfully
5. Verify the health endpoint returns the expected version

## Technical Considerations

### Terraform State and Lifecycle

- `server.tf` has `ignore_changes = [user_data, ssh_keys, image]` -- this is intentional for imported servers and should NOT be removed (it would force server replacement)
- `terraform_data` with `remote-exec` is the HashiCorp-recommended pattern for post-provisioning configuration on existing servers (replaces `null_resource` since Terraform 1.4)
- `triggers_replace` on `sha256(var.doppler_token)` ensures the provisioner re-runs if the service token is rotated
- No `hashicorp/null` provider required -- `terraform_data` is a built-in Terraform resource

### Secret Security

- The Doppler service token (`dp.st.prd.*`) is scoped to `soleur/prd` config -- it can only read production secrets
- The token is persisted to two locations:
  - `/etc/environment` -- readable by all users (for interactive SSH sessions and debugging)
  - `/etc/default/webhook-deploy` -- `chmod 600`, owned by `deploy:deploy` (for the systemd webhook service)
- The dedicated environment file follows the principle of least privilege -- the webhook process only sees `DOPPLER_TOKEN`, not all variables from `/etc/environment`
- The `DOPPLER_TOKEN` in `prd_terraform` Doppler config is already provisioned and scoped correctly per the service token naming convention

### Systemd Environment Inheritance (Critical)

- Systemd services do NOT inherit `/etc/environment`. That file is sourced by PAM during interactive login sessions (SSH, `su`, `login`)
- The `webhook.service` unit must include `EnvironmentFile=/etc/default/webhook-deploy` to make `DOPPLER_TOKEN` available to `ci-deploy.sh`
- Without this fix, the hardened `resolve_env_file()` would always fail with "DOPPLER_TOKEN environment variable not set" even after Doppler CLI is installed
- This is the root cause of why the `.env` fallback was always being used -- the existing cloud-init writes `DOPPLER_TOKEN` to `/etc/environment` (line 128) but the systemd service never reads it

### Backward Compatibility

- The `telegram-bridge` component also calls `resolve_env_file()` from the same `ci-deploy.sh` -- the Doppler hardening applies to both components
- The `.env` file on the server may still exist but will no longer be referenced by any deploy path
- Cloud-init changes only affect newly provisioned servers; the `terraform_data` provisioner handles the existing server
- `cleanup_env_file()` can be simplified to always delete the file (remove the `/mnt/data/.env` conditional) since `resolve_env_file()` now only returns temp file paths or exits

### Shell Safety in remote-exec

- The `${var.doppler_token}` interpolation uses `printf '%s'` pattern for the dedicated env file (safe for any token content)
- The `sed` command for `/etc/environment` uses `|` delimiter which is safe for the `dp.st.prd.*` token format (alphanumeric plus dots)
- If Doppler token format changes in the future, the `sed` delimiter could conflict -- but the `/etc/default/webhook-deploy` file (which uses `printf`) is the authoritative source for the systemd service

### Risk: SSH Connectivity

The `remote-exec` provisioner requires SSH access from the machine running `terraform apply`. This works from the developer machine (SSH key in `~/.ssh/id_ed25519`) but will NOT work from CI (the drift-check and infra-validation workflows use `-target` and do not have SSH keys). The `terraform_data` resource will be planned but not applied in CI -- this is acceptable because it's a one-time bootstrap.

### Risk: CI Drift Detection False Positive

After this change, the drift detection workflow will report `terraform_data.doppler_install` as "will be created" on every run (since CI cannot apply it). This is expected and should be documented as a known drift item. If it generates noise, add a comment to the drift workflow noting this resource is developer-apply-only.

## Acceptance Criteria

- [ ] Doppler CLI is installed on the Hetzner server and `doppler --version` returns a valid version
- [ ] `DOPPLER_TOKEN` is set in `/etc/environment` on the server (for interactive sessions)
- [ ] `/etc/default/webhook-deploy` exists with `DOPPLER_TOKEN` set, owned by `deploy:deploy`, mode `600`
- [ ] `webhook.service` includes `EnvironmentFile=/etc/default/webhook-deploy`
- [ ] `ci-deploy.sh` `resolve_env_file()` exits with error when Doppler is unavailable (no `.env` fallback)
- [ ] `ci-deploy.sh` `resolve_env_file()` exits with error when `DOPPLER_TOKEN` is not set
- [ ] `ci-deploy.sh` `resolve_env_file()` exits with error when Doppler secrets download fails
- [ ] A deploy via the webhook successfully uses Doppler to inject secrets into the container
- [ ] The `/mnt/data/.env` file is no longer referenced in `ci-deploy.sh` or `cloud-init.yml` initial docker run
- [ ] `.env.example` header no longer instructs copying to `/mnt/data/.env`
- [ ] `cloud-init.yml` no longer creates `/mnt/data/.env` placeholder
- [ ] `cloud-init.yml` creates `/etc/default/webhook-deploy` in runcmd for new servers
- [ ] Terraform plan shows only `terraform_data.doppler_install` as a new resource (no server replacement)
- [ ] Pre-removal `.env` audit confirms all server-side secrets exist in Doppler `prd` config

## Test Scenarios

- Given Doppler CLI is not installed, when `ci-deploy.sh` runs, then it exits with error "Doppler CLI not installed" and does NOT fall back to `.env`
- Given `DOPPLER_TOKEN` is empty, when `ci-deploy.sh` runs, then it exits with error "DOPPLER_TOKEN environment variable not set"
- Given Doppler CLI is installed and token is valid, when `ci-deploy.sh` runs a web-platform deploy, then it downloads secrets from Doppler and starts the container successfully
- Given Doppler secrets download fails (e.g., revoked token), when `ci-deploy.sh` runs, then it exits with error "Failed to download secrets from Doppler"
- Given `terraform plan` runs against current state, then only `terraform_data.doppler_install` is shown as "create" (no server replacement)
- Given a newly provisioned server (clean reprovisioning), then cloud-init installs Doppler, creates `/etc/default/webhook-deploy`, and starts the container via Doppler without creating `.env`
- Given the webhook.service restarts, when `ci-deploy.sh` runs, then `DOPPLER_TOKEN` is present in the process environment (inherited via `EnvironmentFile`)
- Given `/mnt/data/.env` contains keys not in Doppler prd config, when the pre-removal audit runs, then missing keys are identified and must be added to Doppler before proceeding

## Domain Review

**Domains relevant:** Engineering, Operations

### Engineering

**Status:** reviewed (inline)
**Assessment:** The `null_resource` with `remote-exec` is the standard Terraform pattern for post-provisioning changes on existing servers. No architectural risk -- the server lifecycle management pattern with `ignore_changes` is preserved. The deploy script hardening is a strict improvement with no backward compatibility concerns since both components use the same `resolve_env_file()` function.

### Operations

**Status:** reviewed (inline)
**Assessment:** No new vendor costs (Doppler CLI is free). No new service tokens needed -- the existing `dp.st.prd.*` token in `prd_terraform` is already provisioned. The operational change is removing a manual secret management surface (`.env` file) in favor of the existing centralized Doppler workflow. This reduces ops burden for secret rotation.

## Dependencies and Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| SSH connection fails during `terraform apply` | Low | Medium | Verify SSH key and firewall access before apply; the terraform_data resource can be re-run |
| Doppler CLI install script changes format | Very Low | Low | The install URL is stable; pin to a version if needed |
| Existing `.env` file has secrets not yet in Doppler | Low | High | Phase 2b audit: compare `/mnt/data/.env` keys against `doppler secrets --only-names -p soleur -c prd` before removing fallback |
| CI drift detection shows false positive | Expected | Low | The `terraform_data.doppler_install` resource shows as "will be created" in CI plan-only runs; document as known item |
| webhook.service restart during provisioner | Low | Low | The `systemctl restart webhook` uses `\|\| true` to handle the case where the service hasn't started yet |
| `/etc/default/webhook-deploy` permissions drift | Very Low | Medium | The provisioner sets `chmod 600` and `chown deploy:deploy`; cloud-init does the same for new servers |

## References

- Issue: #1493
- Related learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Related learning: `knowledge-base/project/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
- Existing infra: `apps/web-platform/infra/server.tf`, `cloud-init.yml`, `ci-deploy.sh`
- Doppler prd config secrets: verified via `doppler secrets --only-names -p soleur -c prd`
- Doppler token in prd_terraform: verified `dp.st.prd.*` prefix (scoped to prd config)
