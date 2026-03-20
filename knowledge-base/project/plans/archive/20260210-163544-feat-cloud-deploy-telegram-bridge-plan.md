---
title: "Cloud Deploy: Run Soleur on Hetzner via Telegram"
type: feat
date: 2026-02-10
updated: 2026-02-10
---

# Cloud Deploy: Run Soleur on Hetzner via Telegram

[Updated 2026-02-10] Simplified after plan review by DHH, Kieran, and Simplicity reviewers. Cut SRE agent, deploy skill, remote session skill, Hono framework, Backblaze B2, and proactive monitoring from v1. Deferred items tracked as GitHub issues.

## Overview

Run Soleur headlessly on a Hetzner VPS (~$4/mo), accessible through a Telegram bot. A lightweight bridge server (~400 lines in a single file) connects Claude Code CLI (via its `--sdk-url` WebSocket protocol) to the Telegram Bot API. Infrastructure is Terraform-managed. Deploy and remote management handled by shell scripts, promoted to Soleur skills post-launch if the pattern proves useful.

**Issue:** [#28](https://github.com/jikig-ai/soleur/issues/28)
**Branch:** `feat-cloud-deploy`
**Brainstorm:** `knowledge-base/brainstorms/2026-02-10-cloud-deploy-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-cloud-deploy/spec.md`
**Version bump intent:** None in v1 (no plugin components; bridge is a standalone app)

## Problem Statement

Soleur only runs locally in a terminal. There is no way to access it from mobile devices or messaging apps.

## Non-Goals

- Multi-user / multi-tenant support
- Browser UI (Companion project covers this)
- Multiple messaging platforms in v1 (Telegram only)
- Custom LLM hosting (uses Claude Max subscription)
- Full Prometheus/Grafana/Loki observability stack
- SRE agent, deploy skill, remote session skill in v1 (deferred to post-launch issues)
- Adapter pattern for future platforms (hardcode Telegram; refactor when platform #2 arrives)
- Remote Terraform state backend (local state for single developer)
- Proactive monitoring in v1 (Docker restart policy + bot silence is the alert)

## Architecture

```
+------------------+
|   Telegram App   |
|   (your phone)   |
+--------+---------+
         | HTTPS (Bot API)
         v
+--------+---------+     Docker Container on Hetzner CX22
|  Bridge Server   |     --------------------------------
|  (Bun + grammY)  |
+--------+---------+
         | WebSocket (NDJSON, localhost only)
         v
+--------+---------+
|  Claude Code CLI |
|  + Soleur Plugin |
+--------+---------+
         | reads/writes
         v
+--------+---------+
|  Project Files   |     Hetzner Volume (persistent)
|  + Git Repos     |
+------------------+

External Services:
  - GHCR (container images)
```

### Message Flow

```
User types in Telegram
  -> Telegram Bot API delivers to bridge (long polling)
  -> Bridge serializes as NDJSON { type: "user", content: "..." }
  -> Sends over WebSocket to CLI child process
  -> CLI processes (Soleur agents, skills, tools)
  -> CLI streams { type: "assistant", content: "..." } back
  -> Bridge waits for complete response (no edit-in-place streaming)
  -> Bridge converts markdown to HTML (escape &, <, > only)
  -> Bridge chunks if >4096 chars (split on double-newline at 4000 chars)
  -> Sends to Telegram
```

### Permission Flow

```
CLI encounters operation requiring approval
  -> CLI sends { type: "control_request", subtype: "can_use_tool", ... }
  -> Bridge formats as Telegram inline keyboard:
     "Soleur wants to: Edit file app/main.ts"
     [Approve] [Deny]
  -> User taps button
  -> Bridge sends { type: "control_response", approved: true/false }
  -> CLI proceeds or aborts
  -> If no response in 5 minutes: auto-deny + notify user
```

Note: The bridge forwards ALL `control_request` messages to Telegram. The CLI's own permission model decides which operations require approval. The bridge does not classify read vs write -- the CLI does.

### Concurrent Message Handling

If the user sends a message while the CLI is processing a previous one, the bridge queues it and sends a reply: "Still processing previous request. Your message is queued." Messages are processed serially. No message cancellation in v1.

### WebSocket Protocol Details

The bridge implements the subset of the Claude Code WebSocket protocol documented in the [Companion project's WEBSOCKET_PROTOCOL_REVERSED.md](https://github.com/The-Vibe-Company/companion/blob/main/WEBSOCKET_PROTOCOL_REVERSED.md):

**Startup sequence:**
1. Bridge starts WebSocket server on `127.0.0.1:PORT` (localhost only)
2. Bridge spawns CLI: `claude --sdk-url ws://127.0.0.1:PORT --print --output-format stream-json --input-format stream-json`
3. CLI connects as WebSocket client with Bearer token from `CLAUDE_CODE_SESSION_ACCESS_TOKEN`
4. CLI sends `system/init` message (capabilities, tools, model info)
5. Bridge is now ready to relay messages

**Message types the bridge handles:**
- `system/init` -- CLI handshake; bridge acknowledges
- `user` -- Bridge sends user's Telegram message to CLI
- `assistant` -- CLI response; bridge relays to Telegram
- `control_request` / `control_response` -- Permission prompts; bridge relays via inline keyboards

**Keepalive:** Ping/pong every 10 seconds (handled by WebSocket library).

**Race condition mitigation:** The WebSocket server MUST be listening before spawning the CLI process. The bridge waits for the `system/init` message before accepting Telegram messages, sending a "Connecting to Claude..." status in the meantime.

## Technical Approach

### Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Bridge runtime | Bun | Proven by Companion for WebSocket handling; runs TypeScript directly |
| HTTP health check | Bun.serve() | Native, no framework needed for a single `/health` endpoint |
| Telegram library | grammY | Best TypeScript support, inline keyboards, auto-retry, Bun-compatible |
| Telegram format | HTML (not MarkdownV2) | Only 3 chars to escape vs 18; safer for arbitrary CLI output |
| Telegram mode | Long polling | One-liner setup, no TLS/domain needed, fine for single user |
| Cloud provider | Hetzner CX22 | ~EUR 3.49/mo, 2 vCPU, 4GB RAM, 40GB disk |
| IaC | Terraform + Hetzner provider | Declarative, repeatable, local state |
| Container registry | GitHub Container Registry | Free for public repos, integrated with GitHub Actions |
| Docker restart | `unless-stopped` policy | Auto-recovers from crashes + reboots, respects manual stop |

### Security Model

| Concern | Mitigation |
|---------|------------|
| Unauthorized Telegram access | `TELEGRAM_ALLOWED_USER_ID` env var; reject all other users |
| Secrets in container | Env vars via `.env` file on volume, never baked into image |
| WebSocket exposure | Bind to `127.0.0.1` only; not exposed outside container |
| SSH access | Key-only auth, firewall restricts to admin IPs |
| Container privileges | Run as non-root user; CLI does not need root |
| Git credentials | SSH key scoped to specific repos, stored on volume |
| Hetzner API token | Terraform variable, never committed; `.tfvars` in `.gitignore` |

### Bootstrap Sequence (First-Time Setup)

```
1. User creates Telegram bot via @BotFather -> gets BOT_TOKEN
2. User gets their Telegram user ID via @userinfobot
3. User creates Hetzner API token
4. User fills in apps/telegram-bridge/infra/terraform.tfvars (git-ignored)
5. User runs: cd apps/telegram-bridge/infra && terraform init && terraform apply
6. Terraform provisions: VM, firewall, SSH key, volume
7. cloud-init installs Docker, pulls container image, starts bridge
8. User SCPs .env file to VM: scp .env root@<IP>:/mnt/data/.env
9. User SSHes in: ssh root@<IP>
10. User runs: docker exec -it soleur-bridge claude login
    (one-time interactive OAuth; session persists on volume)
11. User restarts container: docker restart soleur-bridge
12. User sends first message in Telegram -> gets response
```

### Session Expiry Detection

When the Claude Max session expires, the CLI process will exit with a non-zero code or send an error over the WebSocket. The bridge detects this and sends a Telegram message: "Claude session expired. SSH in and run `docker exec -it soleur-bridge claude login` to re-authenticate." The bridge continues running and retries spawning the CLI every 60 seconds until it succeeds.

## Implementation Phases

### Phase 1: Build the Bridge

Build the bridge server, containerize it, and include operational scripts.

**Directory:** `apps/telegram-bridge/`

```
apps/telegram-bridge/
  src/
    index.ts          # Everything: bot, CLI spawn, WebSocket, permissions, formatting (~400 lines)
  package.json
  tsconfig.json
  Dockerfile
  .dockerignore
  .env.example
  scripts/
    deploy.sh         # Build, push, SSH pull+restart (~15 lines)
    remote.sh         # SSH wrapper: status, logs, restart, health (~30 lines)
```

**`src/index.ts` responsibilities:**

1. **Config:** Load env vars (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USER_ID`, `WS_PORT`); fail fast if missing
2. **WebSocket server:** `Bun.serve()` on `127.0.0.1:WS_PORT`; accept CLI connection; parse NDJSON
3. **CLI process:** Spawn `claude --sdk-url ws://127.0.0.1:WS_PORT ...`; detect crashes; auto-restart
4. **Telegram bot:** grammY with long polling + HTML parse mode; auth middleware
5. **Bridge-native commands:** `/start`, `/status`, `/cancel`, `/help` (bypass CLI)
6. **Message relay:** Telegram text -> NDJSON user message -> CLI; CLI assistant response -> format HTML -> Telegram
7. **Permissions:** `control_request` -> inline keyboard [Approve][Deny]; callback -> `control_response`; 5-min auto-deny
8. **Formatting:** Escape `&`, `<`, `>` in text; convert `**bold**` to `<b>`; convert backtick code to `<code>`/`<pre>`
9. **Chunking:** Split at 4000 chars on double-newline boundaries; hard-split if still too long; no tag tracking (Telegram handles malformed HTML gracefully)
10. **Health:** `Bun.serve()` on port 8080; `/health` returns JSON with bridge + CLI + bot status
11. **Graceful shutdown:** Stop bot + kill CLI on SIGINT/SIGTERM

**`Dockerfile` (single stage):**

```dockerfile
FROM oven/bun:latest
RUN apt-get update && apt-get install -y git curl openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | sh

# Install Soleur plugin
RUN claude plugin install soleur

WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY src/ ./src/

RUN useradd -m soleur
USER soleur

VOLUME /home/soleur/data
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["bun", "run", "src/index.ts"]
```

**`scripts/deploy.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
IMAGE="ghcr.io/<owner>/soleur-telegram-bridge"
TAG=$(git rev-parse --short HEAD)
docker build -t "$IMAGE:$TAG" -t "$IMAGE:latest" .
docker push "$IMAGE:$TAG" && docker push "$IMAGE:latest"
ssh root@"$BRIDGE_HOST" "docker pull $IMAGE:latest && docker restart soleur-bridge"
echo "Deployed $TAG to $BRIDGE_HOST"
```

**`scripts/remote.sh`:**

```bash
#!/usr/bin/env bash
set -euo pipefail
HOST="${BRIDGE_HOST:?Set BRIDGE_HOST}"
case "${1:-help}" in
  status)  ssh "root@$HOST" "docker ps; echo '---'; free -h; df -h /" ;;
  logs)    ssh "root@$HOST" "docker logs --tail ${2:-100} soleur-bridge" ;;
  restart) ssh "root@$HOST" "docker restart soleur-bridge" ;;
  health)  ssh "root@$HOST" "curl -s localhost:8080/health | jq ." ;;
  *)       echo "Usage: remote.sh {status|logs [N]|restart|health}" ;;
esac
```

### Phase 2: Deploy to Hetzner

Terraform configuration for the bridge infrastructure. Local state, no remote backend.

**Directory:** `apps/telegram-bridge/infra/`

```
apps/telegram-bridge/infra/
  main.tf             # Hetzner provider config
  server.tf           # CX22 with cloud-init, keep_disk = true
  firewall.tf         # SSH (restricted IPs), ICMP only
  variables.tf        # hcloud_token, admin_ips, ssh_key_path
  outputs.tf          # Server IP, SSH command
  cloud-init.yml      # Docker install, container pull + run, log rotation, SSH hardening
  .gitignore          # terraform.tfstate, terraform.tfvars, .terraform/
```

**Key Terraform resources:**

| Resource | Purpose |
|----------|---------|
| `hcloud_ssh_key` | Deploy key for SSH access |
| `hcloud_firewall` | SSH (restricted IPs), ICMP only; no HTTP needed (long polling) |
| `hcloud_server` (CX22) | 2 vCPU, 4GB RAM, `keep_disk = true`, cloud-init |
| `hcloud_volume` (10GB) | Persistent data: Claude session, git repos, .env |
| `hcloud_volume_attachment` | Attach volume to server |

**cloud-init.yml** handles:
- Docker install via official convenience script
- Docker log rotation config (10MB, 3 files) in `/etc/docker/daemon.json`
- Pull container from GHCR
- Start container with `--restart unless-stopped`, volume mount at `/mnt/data`
- SSH hardening (key-only, no password auth)
- Create `.env` placeholder on volume (user fills via SCP)

**Local state:** `terraform.tfstate` stays on disk, added to `.gitignore`. For a single developer with 5 resources, this is sufficient. Back up manually or add remote state when collaboration is needed.

**Cost breakdown:**

| Item | Monthly Cost |
|------|-------------|
| Hetzner CX22 | EUR 3.49 |
| Primary IPv4 | EUR 0.50 |
| 10GB Volume | EUR 0.44 |
| **Total** | **~EUR 4.43 (~$4.80 USD)** |

## Acceptance Criteria

### Functional

- [ ] Send a message in Telegram, get a response from Soleur
- [ ] Soleur skills work via Telegram (e.g., send "run /soleur:help")
- [ ] CLI operations that need approval show inline keyboard for approve/deny
- [ ] Unanswered permission prompts auto-deny after 5 minutes
- [ ] Responses >4096 chars are chunked correctly
- [ ] Bridge-native `/status`, `/cancel`, `/help` commands work
- [ ] Unauthorized Telegram users are rejected
- [ ] Second message while processing is queued with acknowledgment
- [ ] `docker logs` shows clean message flow

### Infrastructure

- [ ] `terraform apply` provisions a working Hetzner VM from scratch
- [ ] Container auto-restarts on crash (Docker `unless-stopped`)
- [ ] Claude session persists across container restarts (volume mount)
- [ ] `scripts/deploy.sh` builds, pushes, and updates the running container
- [ ] `scripts/remote.sh status` shows VM health via SSH

### Quality Gates

- [ ] `bun test` passes
- [ ] No secrets committed (`.env`, tokens, keys, `.tfstate`)
- [ ] `.gitignore` covers: `terraform.tfstate*`, `terraform.tfvars`, `.terraform/`, `.env`

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `--sdk-url` flag changes in Claude CLI update | Medium | High | Pin CLI version in Dockerfile if possible; test after CLI updates |
| Claude Max session expires on VM | Medium | Medium | Bridge detects exit, sends Telegram message with re-login instructions |
| Telegram message formatting breaks | High | Low | Use HTML mode; escape only 3 chars; accept some formatting loss gracefully |
| 4GB RAM insufficient for CLI + bridge | Low | High | Monitor with `remote.sh status`; CX22 can scale up with `keep_disk = true` |
| Disk fills with logs/repos | Medium | Medium | Docker log rotation (10MB x 3 files); periodic `remote.sh status` check |
| WebSocket protocol changes | Low | High | Test against Companion's protocol docs; bridge is <400 lines, easy to adapt |

## Rollback Plan

- **Bridge code:** Revert git commit, rebuild + push Docker image, `deploy.sh`
- **Infrastructure:** `terraform destroy` removes all Hetzner resources; volume preserved separately
- **Full rollback:** Remove `apps/telegram-bridge/` directory, close issue

## Dependencies

- Claude Code CLI with `--sdk-url` support (currently undocumented but functional)
- Telegram Bot API (stable, versioned)
- Hetzner Cloud API + Terraform provider (stable)
- GitHub Container Registry (for Docker images)

## Open Questions Resolved

| Question | Resolution |
|----------|-----------|
| Session persistence | Deferred to post-launch; fresh sessions on restart for v1 |
| File sharing | Deferred to post-launch issue |
| Rate limiting | grammY auto-retry handles 429s; single-user unlikely to hit limits |
| Future platforms | Hardcode Telegram; refactor when platform #2 arrives |
| Monitoring stack weight | Docker restart policy + bot silence is the alert; proactive monitoring deferred |
| Headless login | SSH in once after first deploy, run `claude login` interactively |
| Permission classification | Forward all `control_request` messages; rely on CLI's built-in categorization |
| Message formatting | HTML mode (not MarkdownV2); 3 chars to escape |
| Self-update | Deploy from local CLI only via `deploy.sh` |
| Concurrent messages | Queue serially; send "still processing" acknowledgment |
| Streaming strategy | Wait for complete response, then send (no edit-in-place) |
| Chunking complexity | Simple split at 4000 chars on double-newline; no tag tracking |

## Deferred to Post-Launch (GitHub Issues)

These items were in the original plan but cut during review. Each has a separate GitHub issue:

1. **SRE Agent** -- Generic Terraform IaC agent with multi-cloud support and observability guidance
2. **Deploy Skill** -- Promote `deploy.sh` to `/soleur:deploy` with full skill infrastructure
3. **Remote Session Skill** -- Promote `remote.sh` to `/soleur:remote` with full skill infrastructure
4. **Proactive Monitoring** -- healthchecks.io + ntfy.sh for push alerts when bridge goes down
5. **Multiple Messaging Platforms** -- Discord, Slack, WhatsApp adapters with shared bridge architecture

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-02-10-cloud-deploy-brainstorm.md`
- Spec: `knowledge-base/specs/feat-cloud-deploy/spec.md`
- Constitution: `knowledge-base/overview/constitution.md`

### External

- [Companion project (WebSocket protocol)](https://github.com/The-Vibe-Company/companion)
- [Companion WebSocket protocol docs](https://github.com/The-Vibe-Company/companion/blob/main/WEBSOCKET_PROTOCOL_REVERSED.md)
- [grammY Telegram bot framework](https://grammy.dev/)
- [Hetzner Terraform provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)
