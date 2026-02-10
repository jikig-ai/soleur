---
title: "Cloud Deploy: Run Soleur on Hetzner via Telegram"
type: feat
date: 2026-02-10
---

# Cloud Deploy: Run Soleur on Hetzner via Telegram

## Overview

Run Soleur headlessly on a Hetzner VPS (~$4/mo), accessible through a Telegram bot. A lightweight bridge server connects Claude Code CLI (via its `--sdk-url` WebSocket protocol) to the Telegram Bot API. Infrastructure is Terraform-managed with lightweight observability. Three new Soleur plugin components (deploy skill, remote session skill, SRE agent) support the deployment lifecycle.

**Issue:** [#28](https://github.com/jikig-ai/soleur/issues/28)
**Branch:** `feat-cloud-deploy`
**Brainstorm:** `knowledge-base/brainstorms/2026-02-10-cloud-deploy-brainstorm.md`
**Spec:** `knowledge-base/specs/feat-cloud-deploy/spec.md`
**Version bump intent:** MINOR (new skills + agent)

## Problem Statement

Soleur only runs locally in a terminal. There is no way to access it from mobile devices or messaging apps. No infrastructure-as-code support exists for deploying projects, and no remote session management capabilities exist in the plugin.

## Non-Goals

- Multi-user / multi-tenant support
- Browser UI (Companion project covers this)
- Multiple messaging platforms in v1 (Telegram only)
- Custom LLM hosting (uses Claude Max subscription)
- Full Prometheus/Grafana/Loki observability stack (too heavy for a $4/mo VM)
- Generic multi-cloud SRE agent in v1 (Hetzner-focused; generic interface designed for v2)
- Self-update from Telegram in v1 (deploy from local CLI only)

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
|  (Bun + Hono +   |
|   grammY)        |
+--------+---------+
         | WebSocket (NDJSON, localhost)
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
  - healthchecks.io  (heartbeat monitoring, free)
  - ntfy.sh          (push alerts to phone, free)
  - Backblaze B2     (Terraform state, free <10GB)
  - GHCR             (container images)
```

### Message Flow

```
User types in Telegram
  -> Telegram Bot API delivers to bridge (long polling)
  -> Bridge serializes as NDJSON { type: "user", content: "..." }
  -> Sends over WebSocket to CLI child process
  -> CLI processes (Soleur agents, skills, tools)
  -> CLI streams { type: "assistant", content: "..." } back
  -> Bridge converts markdown to HTML (3 chars to escape)
  -> Bridge chunks if >4096 chars (split on double-newline)
  -> Sends to Telegram
```

### Permission Flow

```
CLI encounters write operation
  -> CLI sends { type: "control_request", subtype: "can_use_tool", ... }
  -> Bridge formats as Telegram inline keyboard:
     "Soleur wants to: Edit file app/main.ts"
     [Approve] [Deny]
  -> User taps button
  -> Bridge sends { type: "control_response", approved: true/false }
  -> CLI proceeds or aborts
  -> If no response in 5 minutes: auto-deny + notify user
```

## Technical Approach

### Technology Choices

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Bridge runtime | Bun | Proven by Companion project for WebSocket handling |
| Bridge framework | Hono | Lightweight, works with Bun, minimal overhead |
| Telegram library | grammY | Best TypeScript support, inline keyboards, auto-retry, Bun-compatible |
| Telegram format | HTML (not MarkdownV2) | Only 3 chars to escape vs 18; safer for arbitrary CLI output |
| Telegram mode | Long polling | One-liner setup, no TLS/domain needed, fine for single user |
| Cloud provider | Hetzner CX22 | ~EUR 3.49/mo, 2 vCPU, 4GB RAM, 40GB disk |
| IaC | Terraform + Hetzner provider | Declarative, repeatable, state stored in Backblaze B2 |
| Container registry | GitHub Container Registry | Free for public repos, integrated with GitHub Actions |
| Monitoring | healthchecks.io + ntfy.sh | Free tiers, zero infrastructure, push alerts to phone |
| Terraform state | Backblaze B2 (S3-compatible) | Free <10GB, durable, no state locking needed for single dev |
| Docker restart | `unless-stopped` policy | Auto-recovers from crashes + reboots, respects manual stop |

### Security Model

| Concern | Mitigation |
|---------|------------|
| Unauthorized Telegram access | `TELEGRAM_ALLOWED_USER_ID` env var; reject all other users |
| Secrets in container | Env vars via Docker, never baked into image; `.env` file on volume |
| WebSocket exposure | Bind to `127.0.0.1` only; not exposed outside container |
| SSH access | Key-only auth, firewall restricts to admin IPs |
| Container privileges | Run as non-root user; CLI does not need root |
| Git credentials | SSH key scoped to specific repos, stored on volume |
| Hetzner API token | Terraform variable, never committed; stored in B2 backend |

### Bootstrap Sequence (First-Time Setup)

```
1. User creates Telegram bot via @BotFather -> gets BOT_TOKEN
2. User gets their Telegram user ID via @userinfobot
3. User creates Hetzner API token
4. User creates Backblaze B2 bucket + app key
5. User fills in apps/telegram-bridge/infra/terraform.tfvars (git-ignored)
6. User runs: cd apps/telegram-bridge/infra && terraform init && terraform apply
7. Terraform provisions: VM, firewall, SSH key, volume
8. cloud-init installs Docker, pulls container, starts bridge
9. User SSHes in: ssh root@<IP>
10. User runs: docker exec -it soleur-bridge claude login
    (one-time interactive OAuth; session persists on volume)
11. User sends first message in Telegram -> gets response
```

## Implementation Phases

### Phase 1: Bridge MVP

Build the core bridge server that connects Telegram to Claude Code CLI.

**Directory:** `apps/telegram-bridge/`

```
apps/telegram-bridge/
  src/
    index.ts          # Entry point, starts bridge + bot
    bridge.ts         # WebSocket server, CLI process management
    telegram.ts       # grammY bot setup, message handling
    permissions.ts    # Inline keyboard for approve/deny
    formatter.ts      # Markdown -> Telegram HTML conversion
    chunker.ts        # Message chunking for 4096 char limit
    config.ts         # Environment variable loading + validation
  package.json
  tsconfig.json
  .env.example        # Template with all required env vars
```

**Key files:**

#### `src/config.ts`

```typescript
// Load and validate required environment variables
// TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_ID, CLI_WEBSOCKET_PORT
// Fail fast with clear error messages if any are missing
```

#### `src/bridge.ts`

```typescript
// 1. Create WebSocket server on localhost:CLI_WEBSOCKET_PORT
// 2. Spawn Claude CLI as child process:
//    claude --sdk-url ws://localhost:PORT --print \
//      --output-format stream-json --input-format stream-json
// 3. Handle CLI lifecycle: spawn, crash detection, auto-restart
// 4. Parse NDJSON messages from CLI
// 5. Route messages to telegram.ts or permissions.ts
// 6. Forward user messages from telegram.ts to CLI
// 7. Health check: is CLI process alive + WebSocket connected?
// 8. Session resume: pass --resume <id> on restart
```

#### `src/telegram.ts`

```typescript
// 1. Initialize grammY bot with long polling
// 2. Auth middleware: reject if ctx.from.id !== ALLOWED_USER_ID
// 3. Bridge-native commands (bypass CLI):
//    /start  - Welcome message + status
//    /status - Bridge health, CLI state, uptime
//    /cancel - Kill current CLI operation
//    /help   - List available commands
// 4. Message handler: forward text to bridge.ts
// 5. Typing indicator: send "typing..." during long operations
// 6. Response handler: receive from bridge.ts, format, chunk, send
```

#### `src/permissions.ts`

```typescript
// 1. Receive control_request from bridge.ts
// 2. Format as Telegram inline keyboard:
//    "Soleur wants to: [tool_name] [summary]"
//    [Approve] [Deny]
// 3. Handle callback: send control_response back to bridge.ts
// 4. Timeout: auto-deny after 5 minutes, notify user
// 5. Permission classification:
//    - Default: forward ALL control_requests to Telegram
//    - The CLI's own permission model handles read/write classification
```

#### `src/formatter.ts`

```typescript
// Convert Claude CLI markdown output to Telegram HTML
// - Escape &, <, > (only 3 chars)
// - Convert **bold** to <b>bold</b>
// - Convert `code` to <code>code</code>
// - Convert ```lang\ncode\n``` to <pre><code class="language-lang">code</code></pre>
// - Strip unsupported elements (tables, mermaid diagrams) gracefully
// - For mermaid/tables: send as plain text in <pre> block
```

#### `src/chunker.ts`

```typescript
// Split messages exceeding 4096 chars for Telegram
// Strategy:
//   1. Split on double-newline boundaries (paragraph breaks)
//   2. If a single paragraph > 4096, split on single newlines
//   3. If still too long, split at 4000 chars (leave room for formatting)
//   4. Track open <pre>/<code> tags; re-open if split mid-block
//   5. 500ms delay between chunks to avoid rate limits
//   6. If total response > 20000 chars, send as file attachment instead
```

### Phase 2: Containerization

Package the bridge + Claude Code CLI + Soleur into a single Docker image.

**Directory:** `apps/telegram-bridge/`

```
apps/telegram-bridge/
  Dockerfile
  .dockerignore
  docker-compose.yml  # For local development
```

#### `Dockerfile`

```dockerfile
# Multi-stage build
# Stage 1: Build bridge
FROM oven/bun:latest AS builder
WORKDIR /app
COPY package.json bun.lock ./
RUN bun install --frozen-lockfile
COPY src/ ./src/
COPY tsconfig.json ./

# Stage 2: Runtime
FROM oven/bun:latest
RUN apt-get update && apt-get install -y \
    git curl openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN curl -fsSL https://claude.ai/install.sh | sh

# Install Soleur plugin
RUN claude plugin install soleur

# Copy built bridge
WORKDIR /app
COPY --from=builder /app ./

# Create non-root user
RUN useradd -m soleur
USER soleur

# Volume for persistent data (Claude session, git repos, .env)
VOLUME /home/soleur/data

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

CMD ["bun", "run", "src/index.ts"]
```

#### `docker-compose.yml` (local dev)

```yaml
services:
  bridge:
    build: .
    ports:
      - "8080:8080"
    volumes:
      - ./data:/home/soleur/data
    env_file:
      - .env
    restart: unless-stopped
```

### Phase 3: Infrastructure as Code

Hand-crafted Terraform configuration for the bridge's own infrastructure.

**Directory:** `apps/telegram-bridge/infra/`

```
apps/telegram-bridge/infra/
  main.tf             # Provider config, Backblaze B2 backend
  server.tf           # Hetzner VM with cloud-init
  firewall.tf         # Ingress rules (SSH restricted, ICMP)
  variables.tf        # hcloud_token, admin_ips, ssh_key_path
  outputs.tf          # Server IP, SSH command
  cloud-init.yml      # Docker install, container pull + run
  terraform.tfvars    # (git-ignored) actual values
  .terraform.lock.hcl # Provider lock file (committed)
```

**Key Terraform resources:**

| Resource | Purpose |
|----------|---------|
| `hcloud_ssh_key` | Deploy key for SSH access |
| `hcloud_firewall` | SSH (restricted IPs), ICMP only; no HTTP needed (long polling) |
| `hcloud_server` (CX22) | 2 vCPU, 4GB RAM, `keep_disk = true`, cloud-init |
| `hcloud_volume` (10GB) | Persistent data: Claude session, git repos, .env |
| `hcloud_volume_attachment` | Attach volume to server |

**cloud-init.yml** installs Docker, pulls image from GHCR, starts container with:
- Volume mount for persistent data
- `.env` file on volume for secrets
- `--restart unless-stopped`
- Docker log rotation (10MB, 3 files)
- SSH hardening (key-only, no password)

**Cost breakdown:**

| Item | Monthly Cost |
|------|-------------|
| Hetzner CX22 | EUR 3.49 |
| Primary IPv4 | EUR 0.50 |
| 10GB Volume | EUR 0.44 |
| healthchecks.io | Free |
| ntfy.sh | Free |
| Backblaze B2 | Free (<10GB) |
| **Total** | **~EUR 4.43 (~$4.80 USD)** |

### Phase 4: Observability and Remote Management

Lightweight monitoring suitable for a 4GB VM.

**Observability stack:**

| Layer | Tool | Purpose |
|-------|------|---------|
| Heartbeat | healthchecks.io | Detects if container stops pinging (cron every 5 min) |
| Alerts | ntfy.sh | Push notifications to phone when heartbeat fails |
| Logs | Docker json-file + journald | Log rotation, `docker logs` for inspection |
| Health check | Bridge `/health` endpoint | Checks: process alive, WebSocket connected, Telegram polling |
| Disk/memory | Cron + ntfy.sh | Alert if disk >85% or memory >90% |

**No Prometheus, Grafana, or Loki.** For a single $4/mo VM, `docker logs` + `journalctl` + healthchecks.io covers all failure modes.

### Phase 5: Soleur Plugin Components

Three new components added to the Soleur plugin.

#### 5a. Deploy Skill (`/soleur:deploy`)

**Path:** `plugins/soleur/skills/deploy/`

```
deploy/
  SKILL.md
  scripts/
    deploy.sh         # Build, push, apply workflow
  references/
    hetzner-setup.md  # First-time setup guide
```

**SKILL.md scope (v1):**
- Build Docker image from `apps/telegram-bridge/`
- Tag with git SHA + `:latest`
- Push to GHCR
- SSH into Hetzner VM
- Pull new image + restart container (`docker compose pull && docker compose up -d`)
- Verify health check passes
- Notify user of success/failure

**Not in v1:** Terraform apply from skill (manual via CLI), rolling updates, multi-environment.

#### 5b. Remote Session Skill (`/soleur:remote`)

**Path:** `plugins/soleur/skills/remote-session/`

```
remote-session/
  SKILL.md
  scripts/
    remote.sh         # SSH wrapper with subcommands
```

**SKILL.md scope (v1):**
- `status` -- SSH + `docker ps`, uptime, disk/memory usage
- `logs` -- SSH + `docker logs --tail 100`
- `restart` -- SSH + `docker compose restart`
- `health` -- SSH + `curl localhost:8080/health`

**Not in v1:** SSH tunnel, interactive shell, log streaming.

#### 5c. SRE Agent

**Path:** `plugins/soleur/agents/operations/sre-agent.md`

New agent category: `operations/` (alongside existing `review/`, `research/`, `design/`, `workflow/`).

**Agent scope (v1):**
- Generate Terraform configurations for Hetzner VMs
- Understand: server types, firewall rules, SSH keys, volumes, cloud-init
- Recommend cheapest viable configuration
- Include observability setup (healthchecks.io + ntfy.sh)
- Review existing Terraform configs for issues

**Interface designed for v2 (generic multi-cloud):**
- The agent prompt accepts a cloud provider parameter
- v1 only implements Hetzner; v2 adds AWS, GCP, Fly.io
- v1 only generates Terraform; v2 could add Pulumi, CloudFormation

## Alternative Approaches Considered

| Approach | Why Rejected |
|----------|-------------|
| Fork Companion project | Too much code to maintain (~50+ files), fork debt, carries unused browser UI |
| Companion as upstream proxy | Extra hop, more moving parts, Companion not designed as middleware |
| Webhook instead of long polling | Requires HTTPS endpoint, TLS cert, domain -- unnecessary complexity for single user |
| MarkdownV2 for Telegram | 18 chars to escape vs 3 for HTML; fragile with arbitrary CLI output |
| Prometheus + Grafana | Too heavy for 4GB VM; healthchecks.io + ntfy.sh covers the same failure modes |
| Terraform Cloud for state | Free tier being sunset March 2026; Backblaze B2 is simpler and free |
| Generic SRE agent in v1 | Scope explosion; design interface generically, implement Hetzner only |

## Acceptance Criteria

### Functional

- [ ] Send a message in Telegram, get a response from Soleur
- [ ] Soleur skills work via Telegram (e.g., send "run /soleur:help")
- [ ] Write operations show inline keyboard for approve/deny
- [ ] Unanswered permission prompts auto-deny after 5 minutes
- [ ] Responses >4096 chars are chunked or sent as files
- [ ] Bridge-native `/status`, `/cancel`, `/help` commands work
- [ ] Unauthorized Telegram users are rejected
- [ ] `docker logs` shows clean message flow

### Infrastructure

- [ ] `terraform apply` provisions a working Hetzner VM from scratch
- [ ] Container auto-restarts on crash (Docker `unless-stopped`)
- [ ] healthchecks.io alerts fire when container stops pinging
- [ ] ntfy.sh delivers push notification to phone on alert
- [ ] Claude session persists across container restarts (volume mount)
- [ ] `/soleur:deploy` builds, pushes, and updates the running container
- [ ] `/soleur:remote status` shows VM health via SSH

### Quality Gates

- [ ] All markdown files pass markdownlint
- [ ] `bun test` passes (existing + new tests)
- [ ] Plugin version bumped (MINOR), CHANGELOG updated, README counts match
- [ ] No secrets committed (`.env`, tokens, keys)

## Risk Analysis

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| `--sdk-url` flag changes in Claude CLI update | Medium | High | Pin CLI version in Dockerfile; monitor Claude Code releases |
| Claude Max session expires on VM | Medium | Medium | Document re-login process; alert via healthchecks.io when CLI fails |
| Telegram message formatting breaks | High | Low | Use HTML mode; comprehensive test suite for formatter |
| 4GB RAM insufficient for CLI + bridge | Low | High | Monitor memory; CX22 can scale up temporarily with `keep_disk = true` |
| Disk fills with logs/repos | Medium | Medium | Docker log rotation; cron alert at 85%; periodic cleanup |
| WebSocket protocol changes | Low | High | Pin Companion-compatible protocol version; integration test suite |

## Rollback Plan

- **Bridge code:** Revert git commit, rebuild + push Docker image, restart container
- **Infrastructure:** `terraform destroy` removes all Hetzner resources; volume preserved separately
- **Plugin components:** Revert skill/agent files, bump PATCH version
- **Full rollback:** Remove `apps/telegram-bridge/` directory, revert plugin changes, close issue

## Dependencies

- Claude Code CLI with `--sdk-url` support (currently undocumented but functional)
- Telegram Bot API (stable, versioned)
- Hetzner Cloud API + Terraform provider (stable)
- Backblaze B2 (for Terraform state)
- healthchecks.io + ntfy.sh (for observability)
- GitHub Container Registry (for Docker images)

## Open Questions Resolved

| Question | Resolution |
|----------|-----------|
| Session persistence | Resume via `--resume <id>` flag; session files on Docker volume |
| File sharing | Files <50KB sent as Telegram documents; larger get path-only message |
| Rate limiting | grammY auto-retry handles 429s; single-user unlikely to hit limits |
| Future platforms | Design bridge with adapter pattern; v1 = Telegram only |
| Monitoring stack weight | healthchecks.io + ntfy.sh + Docker log rotation; no Prometheus |
| Headless login | SSH in once after first deploy, run `claude login` interactively |
| Permission classification | Forward all `control_request` messages; rely on CLI's built-in categorization |
| Message formatting | HTML mode (not MarkdownV2); 3 chars to escape |
| Self-update | v1: deploy from local CLI only; v2: Telegram-triggered updates |

## References

### Internal

- Brainstorm: `knowledge-base/brainstorms/2026-02-10-cloud-deploy-brainstorm.md`
- Spec: `knowledge-base/specs/feat-cloud-deploy/spec.md`
- Constitution: `knowledge-base/overview/constitution.md`
- Plugin versioning: `plugins/soleur/AGENTS.md`

### External

- [Companion project (WebSocket protocol)](https://github.com/The-Vibe-Company/companion)
- [Companion WebSocket protocol docs](https://github.com/The-Vibe-Company/companion/blob/main/WEBSOCKET_PROTOCOL_REVERSED.md)
- [grammY Telegram bot framework](https://grammy.dev/)
- [Hetzner Terraform provider](https://registry.terraform.io/providers/hetznercloud/hcloud/latest/docs)
- [healthchecks.io](https://healthchecks.io/)
- [ntfy.sh](https://docs.ntfy.sh/)
- [Backblaze B2 Terraform backend](https://thegeeklab.de/posts/2022/09/store-terraform-state-on-backblaze-s3/)
