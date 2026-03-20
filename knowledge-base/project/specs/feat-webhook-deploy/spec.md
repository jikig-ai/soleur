# Spec: Cloudflare Tunnel Deploy Migration

**Issue:** [#749](https://github.com/jikig-ai/soleur/issues/749)
**Branch:** feat-webhook-deploy
**Date:** 2026-03-20
**Brainstorm:** [2026-03-20-cloudflare-tunnel-deploy-brainstorm.md](../../../brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md)

[Updated 2026-03-20] Scope reduced after plan review — tunnel webhook only, keep admin SSH and app traffic on existing paths.

## Problem Statement

The web-platform CI deploy opens SSH (port 22) to `0.0.0.0/0` because GitHub Actions runners use 5000+ dynamic IPs. This exposes the server to SSH brute-force attacks from the entire internet. The current forced-command restriction (`ci-deploy.sh`) limits what the SSH key can do, but the port itself is unnecessarily exposed.

## Goals

- G1: Eliminate the `0.0.0.0/0` SSH firewall rule used for CI deploy
- G2: Preserve existing deploy orchestration (version pinning, health checks, image allowlisting, audit trail)
- G3: Route deploy webhook through Cloudflare Tunnel (no new open ports)

## Non-Goals

- Tunneling app traffic (already Cloudflare-proxied via A record)
- Tunneling admin SSH (already restricted to admin IPs)
- Container orchestration (K8s, Nomad)
- Splitting web-platform and telegram-bridge to separate servers
- Changes to the Docker build/push pipeline
- Changes to ci-deploy.sh validation logic or test suite

## Functional Requirements

- **FR1:** `cloudflared` daemon installed and running on the server, connecting to a Cloudflare Tunnel
- **FR2:** Webhook endpoint (`deploy.soleur.ai`) routed through tunnel to `localhost:9000`
- **FR3:** Webhook listener validates GitHub HMAC-SHA256 signatures before invoking ci-deploy.sh
- **FR4:** Cloudflare Access service token protects deploy endpoint (defense in depth)
- **FR5:** GitHub Actions release workflows trigger deploy via HTTP POST instead of SSH
- **FR6:** `0.0.0.0/0` SSH firewall rule removed; admin-IP SSH rules retained

## Technical Requirements

- **TR1:** All infrastructure changes via Terraform (per AGENTS.md mandate)
- **TR2:** `cloudflared` and `webhook` binary provisioned via cloud-init
- **TR3:** Tunnel token injected securely via Terraform templatefile variable
- **TR4:** Webhook listener runs as hardened systemd unit (NoNewPrivileges, ProtectSystem)
- **TR5:** Webhook binary installed with version pin and SHA256 checksum verification
- **TR6:** Webhook secret stored as GitHub Actions secret, not variable
- **TR7:** ci-deploy.sh and ci-deploy.test.sh preserved unchanged

## Acceptance Criteria

- [ ] Cloudflare Tunnel active with route for `deploy.soleur.ai`
- [ ] Deploy triggered via webhook from GitHub Actions (not SSH)
- [ ] ci-deploy.sh health checks pass through webhook trigger path
- [ ] `0.0.0.0/0` SSH firewall rule removed
- [ ] Admin SSH works from admin IPs (unchanged)
- [ ] App accessible via `app.soleur.ai` (unchanged)
- [ ] Existing ci-deploy.test.sh passes unchanged
- [ ] Cloudflare Access rejects unauthenticated requests to deploy endpoint
