---
title: Cloudflare Tunnel Deployment
status: superseded-in-part
date: 2026-03-27
superseded_by: [ADR-114]
---

# ADR-008: Cloudflare Tunnel Deployment

> **Status: superseded-in-part by [ADR-114](./ADR-114-one-tunnel-many-connectors-ingress-must-be-origin-relative.md) (2026-07-15, #6416).**
> The zero-trust posture below — outbound-only tunnel, all inbound firewall rules removed
> except ICMP, HMAC-validated webhook — **remains in force**. What is superseded is this ADR's
> **single-host assumption**, visible in the `localhost:` routes of its Decision.
>
> Two independent staleness proofs, both measured:
>
> 1. **The `localhost:` framing predates multi-host.** Written 2026-03-27, when exactly one
>    host ran cloudflared. There are now **2 connector replicas** on the one tunnel, and
>    ADR-114 establishes that `localhost:` in a multi-replica tunnel does not mean *"this
>    host"* — it means *"whichever replica answers."*
> 2. **The `app.soleur.ai → localhost:3000` route does not exist.**
>    `grep -c 'hostname = "app\.' apps/web-platform/infra/tunnel.tf` → **0**. `app.soleur.ai`
>    is a **direct CF-proxied A record** to web-1 (`dns.tf:13-20`), never through the tunnel.
>    The tunnel is purely a management plane: its only ingress rules are `deploy.`, `ssh.`
>    and `registry.` (the last added by ADR-096).
>
> Read the Decision below as historical. For current tunnel topology and the normative rules
> on ingress addressing, see ADR-114.

## Context

SSH-based CI deploy exposed server IP with 0.0.0.0/0 firewall rule. Need zero-trust network architecture.

## Decision

cloudflared daemon creates outbound tunnel to Cloudflare. Three routes: app.soleur.ai → localhost:3000, deploy.soleur.ai (webhook) → localhost:9000, SSH via cloudflared access. Webhook listener validates GitHub HMAC signatures, invokes existing ci-deploy.sh. ALL inbound firewall rules removed except ICMP.

## Consequences

Server becomes invisible to port scanners. Zero-trust access via Cloudflare. Preserved exact version pinning, health checks, deploy serialization through ci-deploy.sh. Adds Cloudflare as infrastructure dependency.
