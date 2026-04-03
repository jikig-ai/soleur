---
title: "fix: install Doppler on server and remove .env fallback"
type: fix
date: 2026-04-03
issue: "#1493"
---

# fix: Install Doppler on Server and Remove .env Fallback

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

Add a Terraform `null_resource` with `remote-exec` provisioner to install Doppler CLI on the running server. This is a one-time bootstrap that bridges the gap between current server state and what cloud-init would provide on reprovisioning.

**Files changed:**

- `apps/web-platform/infra/server.tf` -- add `null_resource.doppler_install` with `remote-exec`

```hcl
resource "null_resource" "doppler_install" {
  # Re-run when doppler_token changes (forces re-provisioning of the token file)
  triggers = {
    doppler_token_hash = sha256(var.doppler_token)
  }

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
      # Persist token in /etc/environment for all users (same as cloud-init)
      "grep -q '^DOPPLER_TOKEN=' /etc/environment && sed -i 's|^DOPPLER_TOKEN=.*|DOPPLER_TOKEN=${var.doppler_token}|' /etc/environment || echo 'DOPPLER_TOKEN=${var.doppler_token}' >> /etc/environment",
      # Verify installation
      "doppler --version",
      # Verify token works (non-destructive read)
      "DOPPLER_TOKEN=${var.doppler_token} doppler secrets --only-names --project soleur --config prd | head -5",
    ]
  }

  depends_on = [hcloud_server.web]
}
```

**Why `null_resource` instead of reprovisioning:** Reprovisioning (removing `ignore_changes`) would destroy and recreate the server, causing extended downtime and data migration complexity. The `null_resource` with `remote-exec` runs against the live server without disruption.

**Why not `hcloud_server` user_data update:** Even if we removed `ignore_changes = [user_data]`, changing user_data forces server replacement in Hetzner. Cloud-init only runs at first boot.

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

### Phase 3: Clean Up .env References

Remove the `/mnt/data/.env` creation and references from cloud-init since Doppler is now the sole secrets source.

**File changed:** `apps/web-platform/infra/cloud-init.yml`

- Remove the `.env` placeholder creation block (lines 156-163: `touch /mnt/data/.env`, `chmod`, comments about populating it)
- Remove the `.env` fallback logic from the initial `docker run` block at the bottom of runcmd (lines 206-227) -- replace with Doppler-only logic matching the hardened `ci-deploy.sh`
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
- The `null_resource` provisioner is the correct pattern for post-provisioning configuration changes on existing servers
- The `triggers` block on `doppler_token_hash` ensures the provisioner re-runs if the service token is rotated

### Secret Security

- The Doppler service token (`dp.st.prd.*`) is scoped to `soleur/prd` config -- it can only read production secrets
- The token is persisted to `/etc/environment` which is readable by all users on the server; this is acceptable because the server is single-tenant (only `root` and `deploy` users, SSH restricted by firewall)
- The `DOPPLER_TOKEN` in `prd_terraform` is already provisioned and scoped correctly per the Doppler service token naming convention

### Backward Compatibility

- The `telegram-bridge` component also calls `resolve_env_file()` from the same `ci-deploy.sh` -- the Doppler hardening applies to both components
- The `.env` file on the server may still exist but will no longer be referenced by any deploy path
- Cloud-init changes only affect newly provisioned servers; the `null_resource` handles the existing server

### Risk: SSH Connectivity

The `remote-exec` provisioner requires SSH access from the machine running `terraform apply`. This works from the developer machine (SSH key in `~/.ssh/id_ed25519`) but will NOT work from CI (the drift-check and infra-validation workflows use `-target` and do not have SSH keys). The `null_resource` will be planned but not applied in CI -- this is acceptable because it's a one-time bootstrap.

## Acceptance Criteria

- [ ] Doppler CLI is installed on the Hetzner server and `doppler --version` returns a valid version
- [ ] `DOPPLER_TOKEN` is set in `/etc/environment` on the server
- [ ] `ci-deploy.sh` `resolve_env_file()` exits with error when Doppler is unavailable (no `.env` fallback)
- [ ] `ci-deploy.sh` `resolve_env_file()` exits with error when `DOPPLER_TOKEN` is not set
- [ ] `ci-deploy.sh` `resolve_env_file()` exits with error when Doppler secrets download fails
- [ ] A deploy via the webhook successfully uses Doppler to inject secrets into the container
- [ ] The `/mnt/data/.env` file is no longer referenced in `ci-deploy.sh` or `cloud-init.yml` initial docker run
- [ ] `.env.example` header no longer instructs copying to `/mnt/data/.env`
- [ ] `cloud-init.yml` no longer creates `/mnt/data/.env` placeholder
- [ ] Terraform plan shows only the `null_resource.doppler_install` as a new resource (no server replacement)

## Test Scenarios

- Given Doppler CLI is not installed, when `ci-deploy.sh` runs, then it exits with error "Doppler CLI not installed" and does NOT fall back to `.env`
- Given `DOPPLER_TOKEN` is empty, when `ci-deploy.sh` runs, then it exits with error "DOPPLER_TOKEN environment variable not set"
- Given Doppler CLI is installed and token is valid, when `ci-deploy.sh` runs a web-platform deploy, then it downloads secrets from Doppler and starts the container successfully
- Given Doppler secrets download fails (e.g., revoked token), when `ci-deploy.sh` runs, then it exits with error "Failed to download secrets from Doppler"
- Given `terraform plan` runs against current state, then only `null_resource.doppler_install` is shown as "create" (no server replacement)
- Given a newly provisioned server (clean reprovisioning), then cloud-init installs Doppler and persists the token without creating `.env`

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
| SSH connection fails during `terraform apply` | Low | Medium | Verify SSH key and firewall access before apply; the null_resource can be re-run |
| Doppler CLI install script changes format | Very Low | Low | The install URL is stable; pin to a version if needed |
| Existing `.env` file has secrets not yet in Doppler | Low | High | Audit: compare `/mnt/data/.env` keys against `doppler secrets --only-names -p soleur -c prd` before removing fallback |
| CI workflows cannot apply null_resource | Expected | None | CI uses read-only terraform plan; the null_resource is applied manually from dev machine |

## References

- Issue: #1493
- Related learning: `knowledge-base/project/learnings/2026-03-29-doppler-service-token-config-scope-mismatch.md`
- Related learning: `knowledge-base/project/learnings/2026-03-20-doppler-secrets-manager-setup-patterns.md`
- Existing infra: `apps/web-platform/infra/server.tf`, `cloud-init.yml`, `ci-deploy.sh`
- Doppler prd config secrets: verified via `doppler secrets --only-names -p soleur -c prd`
- Doppler token in prd_terraform: verified `dp.st.prd.*` prefix (scoped to prd config)
