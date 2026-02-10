# Spec: Cloud Deploy -- Run Soleur on Public Cloud via Telegram

**Issue:** [#28](https://github.com/jikig-ai/soleur/issues/28)
**Branch:** `feat-cloud-deploy`
**Date:** 2026-02-10

## Problem Statement

Soleur currently only runs locally in a terminal. Users cannot access it from mobile devices or messaging apps. There is no infrastructure-as-code support for deploying projects, and no remote session management.

## Goals

1. Run Soleur headlessly on a Hetzner VM, accessible via Telegram
2. Build a lightweight bridge using Claude Code's `--sdk-url` WebSocket protocol
3. Create a generic SRE agent for Terraform IaC with observability
4. Add deploy and remote session management skills to Soleur

## Non-Goals

- Multi-user / multi-tenant support (single user only)
- Browser UI (Companion already does this)
- Multiple messaging platforms in v1 (Telegram only; others later)
- Custom LLM hosting (uses Claude Max subscription)

## Functional Requirements

| ID  | Requirement |
|-----|-------------|
| FR1 | Telegram bot receives user messages and forwards them to Claude Code CLI via WebSocket |
| FR2 | CLI responses stream back to Telegram with proper formatting (code blocks, chunking) |
| FR3 | Write operations (file edits, git commits, deployments) require user confirmation via Telegram inline keyboards |
| FR4 | Read operations (file reads, searches, grep) auto-approve without user interaction |
| FR5 | `/soleur:deploy` skill builds Docker image, pushes to registry, and triggers Terraform apply |
| FR6 | `/soleur:remote` skill provides status, logs, restart, and health check commands |
| FR7 | SRE agent generates Terraform configurations for any project targeting Hetzner |
| FR8 | SRE agent includes observability: health checks, alerting, log aggregation |
| FR9 | Bridge auto-restarts CLI process on crash |
| FR10 | Session can be resumed after restart using `--resume` flag |

## Technical Requirements

| ID  | Requirement |
|-----|-------------|
| TR1 | Bridge server: Bun + Hono, single Docker container |
| TR2 | WebSocket protocol: NDJSON, following Companion's reverse-engineered spec |
| TR3 | Telegram integration: Bot API via long-polling (dev) or webhook (prod) |
| TR4 | Infrastructure: Terraform-managed Hetzner CX22 (~$4/mo, 2 vCPU, 4GB RAM) |
| TR5 | Auth: Claude Max subscription via `claude login` (one-time interactive login) |
| TR6 | Container: Claude Code CLI + Soleur plugin pre-installed |
| TR7 | IaC: Terraform with Hetzner provider, state stored remotely (Terraform Cloud or S3-compatible) |
| TR8 | Observability: Lightweight stack suitable for small VM (no full Prometheus/Grafana) |

## Components

### 1. Telegram Bridge (`apps/telegram-bridge/`)

New standalone application. Bun + Hono server that:
- Manages Claude Code CLI as a child process with `--sdk-url`
- Translates Telegram Bot API messages to/from CLI WebSocket protocol
- Handles permission forwarding via inline keyboards
- Formats responses for Telegram (code blocks, message chunking)

### 2. Deploy Skill (`plugins/soleur/skills/deploy/`)

New Soleur skill. Handles:
- Docker image building and registry push
- Terraform plan/apply for target infrastructure
- Rolling updates and rollback
- Environment management (staging/production)

### 3. Remote Session Skill (`plugins/soleur/skills/remote-session/`)

New Soleur skill. Provides:
- Instance status and resource monitoring
- Log tailing from remote services
- Service restart capabilities
- Health check execution

### 4. SRE Agent (`plugins/soleur/agents/operations/sre-agent.md`)

New Soleur agent. Capabilities:
- Generate Terraform configurations from project requirements
- Manage compute, networking, storage, and DNS
- Configure observability (health checks, alerts, log rotation)
- Cost optimization recommendations
- Infrastructure drift detection

## Milestones

1. **M1: Bridge MVP** -- Telegram sends/receives messages through Claude Code CLI
2. **M2: Permissions** -- Hybrid permission model with inline keyboards
3. **M3: Dockerize** -- Single container with CLI + bridge + Soleur
4. **M4: Terraform** -- SRE agent generates Hetzner IaC, deploy skill applies it
5. **M5: Observability** -- Health checks, alerting, log management
6. **M6: Remote Management** -- `/soleur:remote` skill for monitoring and control
