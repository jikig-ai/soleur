# Cloud Deploy Brainstorm

**Date:** 2026-02-10
**Issue:** [#28 - Ability to Run Soleur Plugin on Public Cloud](https://github.com/jikig-ai/soleur/issues/28)
**Branch:** `feat-cloud-deploy`
**Status:** Active

## What We're Building

A system to run Soleur on a public cloud provider (Hetzner) and interact with it through Telegram, enabling mobile-first access to Claude Code + Soleur's full agent/skill ecosystem.

### Four Components

1. **Telegram Bridge** -- A lightweight Bun + Hono server (~600 lines) that connects Claude Code CLI (via the `--sdk-url` WebSocket protocol) to the Telegram Bot API. Single user, hybrid permissions (auto-approve reads, confirm writes via Telegram inline buttons).

2. **Deploy Skill** (`/soleur:deploy`) -- Containerize any Soleur project and deploy to Hetzner with one command. Builds Docker images, provisions infrastructure, and handles the full deployment lifecycle.

3. **Remote Session Skill** (`/soleur:remote`) -- Manage and monitor cloud instances: check status, tail logs, restart services, SSH access.

4. **SRE Agent** -- A generic Terraform IaC agent that provisions infrastructure for any project (not just the bridge). Includes observability as a first-class concern: health checks, alerting, log aggregation, auto-restart.

## Why This Approach

### Custom Bridge Over Forking Companion

We studied [The Vibe Company's Companion](https://github.com/The-Vibe-Company/companion) project, which reverse-engineered Claude Code's hidden `--sdk-url` WebSocket protocol. Key insight: the CLI becomes a WebSocket *client* connecting to your server via:

```bash
claude --sdk-url ws://localhost:PORT --print --output-format stream-json --input-format stream-json
```

The Companion is a full browser UI (~50+ files). We only need the protocol knowledge, not the codebase. Building a purpose-built bridge gives us:

- Minimal code to maintain (~600 lines vs thousands)
- No fork debt -- Companion can evolve independently
- Exactly the features we need, nothing more
- Single Docker container deployment

### Hetzner Over PaaS

- Cheapest always-on option (~$4/mo for CX22: 2 vCPU, 4GB RAM)
- Persistent WebSocket connections (no cold starts)
- Full control for Docker, Terraform, monitoring
- EU + US datacenters

### Telegram First

- Simplest bot API (HTTP-based, no OAuth)
- Great for single-user: no server/workspace setup needed
- Supports code blocks, file sharing, inline keyboards (for permission prompts)
- Free, works on all platforms

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| User scope | Single user | Simplest architecture, no auth/multi-tenancy needed |
| First platform | Telegram | Easiest bot API, perfect for single-user mobile access |
| Cloud provider | Hetzner | Cheapest always-on VMs (~$4/mo), full Docker control |
| CLI auth | Claude Max subscription | Uses existing subscription, `claude login` once on VM |
| Interaction model | Hybrid | Auto-approve reads/searches, confirm writes/commits via Telegram |
| Architecture | Custom bridge | ~600 lines, purpose-built, no fork debt from Companion |
| Stack | Bun + Hono | Proven by Companion for WebSocket handling, lightweight |
| IaC | Terraform (generic) | SRE agent manages any project's infra, not just bridge |
| Observability | Built into SRE agent | Health checks, alerting, log aggregation from day one |
| Deployment | Docker on Hetzner | Single container, Terraform-managed |

## Architecture Overview

```
[Telegram App]
    |
    | (Telegram Bot API - HTTPS)
    v
[Bridge Server (Bun + Hono)]  <-- Hetzner VM, Docker container
    |
    | (WebSocket - NDJSON protocol)
    v
[Claude Code CLI + Soleur Plugin]  <-- Same container, headless
    |
    | (reads/writes)
    v
[Project Files / Git Repos]  <-- Mounted volume
```

### Message Flow

1. User sends message in Telegram
2. Bridge receives via Bot API webhook/polling
3. Bridge forwards as `user` message over WebSocket to CLI
4. CLI processes with Soleur agents/skills
5. CLI streams `assistant` responses back over WebSocket
6. Bridge formats and sends to Telegram (chunked for long responses)
7. For write operations: CLI sends `control_request`, bridge forwards as Telegram inline keyboard, user approves/denies

### WebSocket Protocol (from Companion research)

- CLI connects to bridge via `--sdk-url ws://localhost:PORT`
- Auth: Bearer token from `CLAUDE_CODE_SESSION_ACCESS_TOKEN`
- Messages: NDJSON (newline-delimited JSON)
- Key message types: `system/init`, `user`, `assistant`, `control_request`/`control_response`
- 13 control subtypes for permission management
- Ping/pong keepalive every 10 seconds

## New Soleur Components

### 1. Telegram Bridge (standalone app, not a plugin component)

- Lives in a new top-level directory: `apps/telegram-bridge/`
- Bun + Hono server
- Telegram Bot API integration (long-polling for dev, webhook for prod)
- WebSocket client management (spawn/restart CLI process)
- Message formatting (markdown to Telegram, chunking long responses)
- Permission forwarding (inline keyboards for approve/deny)
- Docker container with Claude Code CLI + Soleur pre-installed

### 2. Deploy Skill (`/soleur:deploy`)

- Builds Docker image from project
- Pushes to container registry (GitHub Container Registry)
- Triggers Terraform apply for infrastructure
- Handles rolling updates
- Supports multiple environments (staging, production)

### 3. Remote Session Skill (`/soleur:remote`)

- `status` -- Show running services, resource usage
- `logs` -- Tail logs from remote instance
- `restart` -- Restart services
- `ssh` -- Open SSH tunnel to instance
- `health` -- Run health checks

### 4. SRE Agent

- Generates Terraform configurations for any project
- Manages: compute (Hetzner VMs), networking (DNS, firewall), storage (volumes)
- Observability stack: Prometheus metrics, Grafana dashboards, alerting rules
- Log aggregation (Loki or similar lightweight solution)
- Auto-restart and health check configuration
- Cost-aware: recommends cheapest viable configuration

## Open Questions

1. **Session persistence:** When the CLI process restarts, should we resume the previous conversation or start fresh? Companion supports `--resume <id>`.
2. **File sharing:** How should we handle files the CLI generates? Upload to Telegram? Store on the VM and share a link?
3. **Rate limiting:** Should we add any protection against accidental message floods from Telegram?
4. **Future platforms:** After Telegram, should Discord/Slack/WhatsApp share the same bridge server or be separate adapters?
5. **Monitoring stack weight:** For a $4/mo VM, Prometheus + Grafana + Loki might be too heavy. Consider lighter alternatives (healthchecks.io, ntfy.sh for alerts, simple log rotation).

## Success Criteria

- [ ] Can send a message in Telegram and get a response from Soleur
- [ ] Soleur skills and agents work (e.g., `/soleur:plan` via Telegram)
- [ ] Write operations require Telegram confirmation before executing
- [ ] Bridge auto-restarts on failure
- [ ] Infrastructure is fully Terraform-managed
- [ ] Deployment is a single command (`/soleur:deploy`)
- [ ] Observability: can see health status and logs remotely
