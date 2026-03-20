# Brainstorm: Replace SSH Deploy with Cloudflare Tunnel

**Date:** 2026-03-20
**Issue:** [#749](https://github.com/jikig-ai/soleur/issues/749)
**Branch:** feat-webhook-deploy
**Status:** Decision made

## What We're Building

A Cloudflare Tunnel-based deployment architecture that eliminates all inbound firewall ports on the production server. Replaces the current SSH-based CI deploy mechanism with a webhook listener triggered through the tunnel, while preserving the existing ci-deploy.sh orchestration (version pinning, health checks, image allowlisting, deploy serialization).

### Current State

- GitHub Actions release workflows SSH into the server via `appleboy/ssh-action`
- SSH key has a forced command (`ci-deploy.sh`) that validates structured `deploy <component> <image> <tag>` input
- ci-deploy.sh handles: image allowlisting, semver tag validation, docker prune, pull, component-specific `docker run` flags, and health check loops (10-24 attempts)
- Web platform firewall opens SSH (port 22) to `0.0.0.0/0` to accommodate GitHub Actions dynamic runner IPs
- Both web-platform and telegram-bridge containers deploy to the same Hetzner server
- Web platform DNS is already Cloudflare-proxied (`app.soleur.ai`)
- No reverse proxy — Docker binds directly to `0.0.0.0:80:3000`
- Comprehensive test suite exists for ci-deploy.sh (`ci-deploy.test.sh`)

### Target State

- `cloudflared` daemon runs on the server, creating an outbound tunnel to Cloudflare
- Three tunnel routes:
  - `app.soleur.ai` → `localhost:3000` (app traffic, replaces direct port 80)
  - `deploy.soleur.ai` → `localhost:9000` (webhook endpoint, new)
  - SSH via `cloudflared access ssh` (admin access, replaces port 22)
- Webhook listener (`webhook` by adnanh, Go binary) on `localhost:9000` validates GitHub HMAC-SHA256 signatures, invokes existing `ci-deploy.sh`
- ALL inbound firewall rules removed except ICMP
- Server IP becomes irrelevant — invisible to port scanners

## Why This Approach

### Evaluated Alternatives

| Option | Verdict | Reason |
|--------|---------|--------|
| **Watchtower** | Rejected | Loses version pinning (polls `:latest`), health checks, CI audit trail, deploy serialization, and docker run flag control. Prior plans (#738 context) rejected it twice. |
| **Standalone webhook (no tunnel)** | Rejected | Solves SSH dependency but leaves server IP exposed, requires new open port. Doesn't move toward zero-trust. |
| **Partial tunnel (webhook + SSH only)** | Rejected | Two traffic paths to maintain. App still directly reachable by IP. Doesn't achieve full zero-trust. |
| **Full Cloudflare Tunnel** | **Chosen** | Strongest security posture. Zero inbound ports. Cloudflare handles TLS/DDoS for all traffic. Free tier. Already depend on Cloudflare for DNS. |

### Why Cloudflare Tunnel over alternatives

1. **Security posture (top priority):** Server becomes invisible. No ports to scan, no services to probe. Even if server IP leaks, nothing responds.
2. **CI control preserved:** Webhook + ci-deploy.sh keeps exact version pinning, health checks, audit trail, and deploy serialization — all non-negotiable.
3. **No new vendor:** Already using Cloudflare for DNS/proxy. Zero Trust free tier covers tunnels + Access for up to 50 users.
4. **Phased migration:** Tunnel runs alongside existing firewall rules. Verify each route, then remove rules. No flag day.

## Key Decisions

1. **Full tunnel, not partial.** Route all traffic (app, webhook, SSH) through the tunnel. Maximum security, single traffic path.
2. **`webhook` binary (adnanh/webhook) for listener.** Single Go binary (~5MB), supports HMAC validation natively, can invoke shell scripts. No runtime dependencies.
3. **ci-deploy.sh stays unchanged.** Only the trigger mechanism changes (HTTP POST instead of SSH). The validation logic, image allowlist, health checks, and test suite are preserved.
4. **Cloudflare Zero Trust (new setup).** Free tier. Needs: Zero Trust dashboard setup, tunnel creation, Access policies for SSH.
5. **Terraform for all infra changes.** Per AGENTS.md mandate. Firewall rule removal, new provisioning for `cloudflared` and `webhook` in cloud-init.
6. **Phased migration.** Add tunnel → verify routes → remove firewall rules. SSH stays available during transition.
7. **Both apps on same server.** Current reality for cost reasons. Eventually may split to separate servers or K8s/Nomad — this design works for both cases (one tunnel per server).

## Open Questions

1. **Cloudflare Access SSH UX:** Short-lived certificates + browser auth flow for first access. Is this acceptable for daily admin SSH usage, or should we also keep admin-IP SSH as a fallback?
2. **Tunnel token provisioning:** How to inject the tunnel token into cloud-init securely? Options: Terraform secret variable, Hetzner user data, or manual first-boot setup.
3. **Webhook listener process management:** systemd unit for `webhook` binary, or run it as a Docker container alongside the app? systemd is simpler; Docker is more consistent with existing containerized apps.
4. **GHCR auth for Telegram bridge server:** When/if the bridge moves to its own server, it will also need the tunnel setup. Keep this in mind but don't over-engineer for it now.
5. **Monitoring/alerting:** If the tunnel goes down, all traffic stops. Need Cloudflare health checks or external monitoring (e.g., Uptime Robot) to detect tunnel failures.

## Domain Assessments

### CTO Assessment
- Recommended webhook over Watchtower — ci-deploy.sh has meaningful orchestration that Watchtower can't replicate
- Highlighted 10 affected files/components for migration
- Suggested phased migration with SSH coexistence during transition
- Flagged TLS termination as key technical question (resolved by tunnel)

### COO Assessment
- Confirmed all three options cost $0 direct
- Surfaced that firewall was already admin-IP-restricted for telegram-bridge (the 0.0.0.0/0 rule is web-platform-specific)
- Identified Cloudflare Tunnel as the strongest option for solo operator
- Recommended questioning whether CI-triggered deploys are even needed (they are — release workflows already use them)

### Institutional Learnings Applied
- **Bash operator precedence in SSH deploy scripts** (critical): Use `{ ...; }` grouping around `|| true` — deploy scripts can silently proceed with stale images
- **Webhook URLs are secrets**, not GitHub Actions vars
- **SHA-pin all GitHub Actions** references
- **Sanitize `$GITHUB_OUTPUT`** values with `printf` + `tr -d '\n\r'`
- **GITHUB_TOKEN cascade limitation:** Releases created by GITHUB_TOKEN don't trigger other workflows — handle deploy in the same workflow
