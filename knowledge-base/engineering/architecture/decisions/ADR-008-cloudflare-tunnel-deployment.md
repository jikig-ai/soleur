---
adr: ADR-008
title: Cloudflare Tunnel Deployment
status: active
date: 2026-03-27
---

# ADR-008: Cloudflare Tunnel Deployment

## Context

SSH-based CI deploy exposed server IP with 0.0.0.0/0 firewall rule. Need zero-trust network architecture.

## Decision

cloudflared daemon creates outbound tunnel to Cloudflare. Three routes: app.soleur.ai → localhost:3000, deploy.soleur.ai (webhook) → localhost:9000, SSH via cloudflared access. Webhook listener validates GitHub HMAC signatures, invokes existing ci-deploy.sh. ALL inbound firewall rules removed except ICMP.

## Consequences

Server becomes invisible to port scanners. Zero-trust access via Cloudflare. Preserved exact version pinning, health checks, deploy serialization through ci-deploy.sh. Adds Cloudflare as infrastructure dependency.
