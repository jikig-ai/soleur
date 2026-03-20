# Spec: Cloudflare Tunnel Deploy Migration

**Issue:** [#749](https://github.com/jikig-ai/soleur/issues/749)
**Branch:** feat-webhook-deploy
**Date:** 2026-03-20
**Brainstorm:** [2026-03-20-cloudflare-tunnel-deploy-brainstorm.md](../../../brainstorms/2026-03-20-cloudflare-tunnel-deploy-brainstorm.md)

## Problem Statement

The web-platform CI deploy opens SSH (port 22) to `0.0.0.0/0` because GitHub Actions runners use 5000+ dynamic IPs. This exposes the server to SSH brute-force attacks from the entire internet. The current forced-command restriction (`ci-deploy.sh`) limits what the SSH key can do, but the port itself is unnecessarily exposed.

## Goals

- G1: Eliminate all inbound SSH firewall rules for CI deploy
- G2: Preserve existing deploy orchestration (version pinning, health checks, image allowlisting, audit trail)
- G3: Route all server traffic through Cloudflare Tunnel (app, webhook, SSH) for zero inbound port exposure
- G4: Phased migration with no downtime or flag-day cutover

## Non-Goals

- Container orchestration (K8s, Nomad) — separate future initiative
- Splitting web-platform and telegram-bridge to separate servers
- Changes to the Docker build/push pipeline (GHCR workflow stays as-is)
- Changes to ci-deploy.sh validation logic or test suite

## Functional Requirements

- **FR1:** `cloudflared` daemon installed and running on the server, connecting to a Cloudflare Tunnel
- **FR2:** App traffic (`app.soleur.ai`) routed through tunnel to `localhost:3000`
- **FR3:** Webhook endpoint (`deploy.soleur.ai`) routed through tunnel to `localhost:9000`
- **FR4:** Admin SSH accessible via `cloudflared access ssh` with short-lived certificates
- **FR5:** Webhook listener validates GitHub HMAC-SHA256 signatures before invoking ci-deploy.sh
- **FR6:** GitHub Actions release workflows trigger deploy via HTTP POST instead of SSH
- **FR7:** All inbound firewall rules removed except ICMP after tunnel verification

## Technical Requirements

- **TR1:** All infrastructure changes via Terraform (per AGENTS.md mandate)
- **TR2:** `cloudflared` and `webhook` binary provisioned via cloud-init
- **TR3:** Tunnel token injected securely (Terraform variable, not hardcoded)
- **TR4:** Webhook listener runs as systemd unit with restart-on-failure
- **TR5:** GitHub Actions references SHA-pinned (per learnings)
- **TR6:** Webhook secret stored as GitHub Actions secret, not variable (per learnings)
- **TR7:** `$GITHUB_OUTPUT` values sanitized with `printf` + `tr -d '\n\r'` (per learnings)
- **TR8:** ci-deploy.sh and ci-deploy.test.sh preserved unchanged — only trigger mechanism changes

## Acceptance Criteria

- [ ] Cloudflare Tunnel active with routes for app, webhook, and SSH
- [ ] Deploy triggered via webhook from GitHub Actions (not SSH)
- [ ] ci-deploy.sh health checks pass through webhook trigger path
- [ ] All inbound firewall rules removed except ICMP
- [ ] Server IP not reachable on any port (verified via external port scan)
- [ ] Admin SSH works via `cloudflared access ssh`
- [ ] Existing ci-deploy.test.sh passes unchanged
- [ ] Phased migration: tunnel coexists with existing rules during verification
