# Learning: Cloudflare Tunnel server-side provisioning

## Problem

Completing end-to-end Cloudflare Tunnel server provisioning (#967) to replace SSH-based deploys with webhook-based deploys through Cloudflare Tunnel. The code and Terraform resources existed from #963, but the production server lacked cloudflared, the webhook binary, and systemd services. Cloudflare Access enforcement and Terraform state import were also missing. The session surfaced 10 distinct errors spanning Terraform import semantics, systemd hardening conflicts, Cloudflare product interactions, Docker disk management, and binary integrity verification.

## Solutions

### 1. Terraform import lifecycle management

When importing pre-existing infrastructure into Terraform state, several attributes are create-time-only or force-replacement: `ssh_keys`, `user_data`, `image` (Hetzner), `config_src`, `secret` (Cloudflare tunnel). Without intervention, `terraform plan` proposes destroying and recreating the production server and tunnel because the API doesn't return these values on read, so Terraform sees them as "changed."

Fix: Add `lifecycle { ignore_changes = [...] }` blocks for all create-time and import-incompatible attributes. Mark each with a `TODO: remove after clean reprovisioning` comment so they don't become permanent technical debt. This is an import-specific pattern -- clean `terraform apply` from scratch wouldn't need these blocks.

### 2. Systemd hardening vs. operational requirements

Three hardening directives in the webhook systemd unit conflicted with runtime needs:

- `NoNewPrivileges=true` blocks `sudo`, which `ci-deploy.sh` needs for `chown` operations
- `ProtectHome=true` blocks Docker config access under `$HOME/.docker/`
- `ProtectSystem=strict` without `ReadWritePaths` blocks all filesystem writes

Fix: Remove `NoNewPrivileges` (scoped sudoers for the deploy user mitigates the privilege escalation risk it guards against). Change `ProtectHome=true` to `ProtectHome=read-only` (allows reads for Docker config, blocks writes). Add `PrivateTmp=true` and `ReadWritePaths=/mnt/data` to `ProtectSystem=strict` (restricts writes to the data partition only). Document the trade-offs inline in the unit file -- each relaxation has a compensating control.

### 3. Cloudflare Bot Fight Mode blocks API/webhook traffic

Zone-level Bot Fight Mode triggers managed challenges on ALL traffic to proxied domains, including legitimate API calls from GitHub Actions runners through Cloudflare Tunnel. The challenge is injected at the edge BEFORE Cloudflare Access evaluates service token headers. This means a correctly authenticated deploy request gets a 403/challenge response and never reaches the webhook endpoint.

Fix: Disable Bot Fight Mode at the zone level. The deploy endpoint is already protected by two layers -- CF Access service token authentication and HMAC-SHA256 payload verification -- making bot detection redundant for this traffic. Bot Fight Mode is a zone-wide setting with no per-path override capability, so it cannot be scoped to exclude the deploy endpoint.

### 4. Docker image accumulation fills disk

The production server accumulated 49 Docker images (77 GB) over 4 days of deploys, filling the 75 GB root partition to 100%. `apt-get update` failed (no disk space for package lists), which blocked cloudflared installation. The failure cascaded: no cloudflared means no tunnel, no tunnel means no deploys.

Fix: Two-layer cleanup strategy. (1) Weekly cron job: `docker image prune -af --filter "until=168h"` catches image buildup during deploy-free periods. (2) Per-deploy pruning in `ci-deploy.sh`: `docker image prune -af --filter "until=24h"` runs after every successful deploy. Both layers are needed -- cron alone misses frequent-deploy bursts, per-deploy alone misses idle periods where old images accumulate.

### 5. Webhook binary checksum verification

The SHA256 checksum for webhook v2.8.2 in cloud-init didn't match the actual GitHub release binary. The checksum was likely computed from a different architecture's binary, a different version, or was fabricated by the planning agent.

Fix: Always verify checksums by downloading the actual binary from the release URL and computing `sha256sum` against the real file. Never trust checksums from plan documents, AI-generated values, or any source other than the binary itself. This reinforces the existing learning from `2026-03-20-checksum-verification-binary-downloads.md` -- embedded checksums are only trustworthy when derived from the actual artifact, not from documentation.

## Session Errors

1. **Stale Cloudflare API token in Doppler** -- The token stored in Doppler was expired or revoked. Required regeneration from the Cloudflare dashboard and updating the Doppler secret.
2. **Hetzner API token created as read-only** -- Playwright automated token creation but the radio button for read-write permission didn't select correctly. The read-only token caused Terraform operations to fail silently on write operations. Had to recreate with correct permissions.
3. **Server 100% disk full from Docker images** -- 49 images / 77 GB on a 75 GB partition. Blocked all package operations and service installations. Required emergency `docker image prune` before any provisioning could proceed.
4. **Webhook checksum mismatch** -- SHA256 in cloud-init template didn't match the actual webhook v2.8.2 linux-amd64 binary from GitHub releases. Caught during server provisioning when the checksum verification step failed.
5. **hooks.json permissions blocked deploy user** -- The hooks.json file was owned by root with restrictive permissions. The deploy user running the webhook process couldn't read the webhook configuration, causing all deploy requests to fail.
6. **Terraform force-replacement on imported resources** -- `terraform plan` proposed destroying the production server and tunnel after import because create-time-only attributes (ssh_keys, user_data, image, secret) showed as "changed." Required lifecycle ignore_changes blocks.
7. **Cloudflare Bot Fight Mode blocked webhook** -- Zone-level bot protection intercepted legitimate deploy webhook calls from GitHub Actions, returning challenges before CF Access could evaluate service token headers.
8. **NoNewPrivileges blocked sudo** -- Systemd hardening directive prevented `ci-deploy.sh` from running `sudo chown`, breaking the deploy script's file ownership management.
9. **ProtectSystem=strict blocked writes to /mnt/data** -- Without explicit ReadWritePaths, the systemd hardening made the entire filesystem read-only, preventing the deploy script from writing to the data partition.
10. **New Docker images crash on startup** -- Pre-existing issue with the security-headers module in the Next.js application. Not caused by tunnel provisioning but surfaced during deploy testing. Separate from this session's scope.

## Key Insight

Infrastructure import into Terraform is fundamentally different from greenfield provisioning. The import path requires defensive lifecycle management because cloud APIs don't round-trip every attribute -- create-time-only fields like SSH keys, user data, and tunnel secrets are write-once values that the API never returns on read. Treating import as "just run `terraform import`" leads to plan-time destruction of production resources. The correct pattern is: import, run plan, identify every force-replacement attribute, add targeted lifecycle ignores with removal TODOs, then verify plan shows zero destructive changes before applying.

A secondary insight: systemd hardening directives are not composable by default. Each directive (NoNewPrivileges, ProtectHome, ProtectSystem) is designed for the simplest case and immediately conflicts with real-world operational needs (sudo, Docker config reads, data partition writes). The right approach is to start with maximum hardening and relax selectively with documented compensating controls, rather than starting permissive and trying to add hardening later.

## Tags

category: infrastructure
module: web-platform, ci
