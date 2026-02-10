# Spec: Cloud Deploy -- Run Soleur on Public Cloud via Telegram

**Issue:** [#28](https://github.com/jikig-ai/soleur/issues/28)
**Branch:** `feat-cloud-deploy`
**Date:** 2026-02-10
**Updated:** 2026-02-10 (simplified after plan review)

## Problem Statement

Soleur currently only runs locally in a terminal. Users cannot access it from mobile devices or messaging apps.

## Goals

1. Run Soleur headlessly on a Hetzner VM, accessible via Telegram
2. Build a lightweight bridge using Claude Code's `--sdk-url` WebSocket protocol

## Non-Goals

- Multi-user / multi-tenant support (single user only)
- Browser UI (Companion already does this)
- Multiple messaging platforms in v1 (Telegram only; others as post-launch issues)
- Custom LLM hosting (uses Claude Max subscription)
- SRE agent, deploy skill, remote session skill in v1 (deferred to post-launch issues)
- Proactive monitoring in v1 (Docker restart policy; monitoring deferred)
- Adapter pattern for future platforms (hardcode Telegram)

## Functional Requirements

| ID  | Requirement |
|-----|-------------|
| FR1 | Telegram bot receives user messages and forwards them to Claude Code CLI via WebSocket |
| FR2 | CLI responses are sent back to Telegram with HTML formatting and message chunking |
| FR3 | CLI operations that need approval are forwarded as Telegram inline keyboards (approve/deny); the bridge relays ALL `control_request` messages and relies on the CLI's own permission classification |
| FR4 | Bridge auto-restarts CLI process on crash |
| FR5 | Unauthorized Telegram users are rejected via `TELEGRAM_ALLOWED_USER_ID` |
| FR6 | Bridge-native commands (`/start`, `/status`, `/cancel`, `/help`) bypass the CLI |
| FR7 | Concurrent messages are queued serially with a "still processing" acknowledgment |

## Technical Requirements

| ID  | Requirement |
|-----|-------------|
| TR1 | Bridge server: Bun + grammY, single Docker container, single `index.ts` file |
| TR2 | WebSocket protocol: NDJSON, following Companion's reverse-engineered spec |
| TR3 | Telegram integration: Bot API via long polling, HTML formatting |
| TR4 | Infrastructure: Terraform-managed Hetzner CX22 (~$4/mo, 2 vCPU, 4GB RAM) |
| TR5 | Auth: Claude Max subscription via `claude login` (one-time interactive login via SSH) |
| TR6 | Container: Claude Code CLI + Soleur plugin pre-installed, non-root user |
| TR7 | IaC: Terraform with Hetzner provider, local state |
| TR8 | Operational scripts: `deploy.sh` and `remote.sh` (not Soleur skills) |

## Components

### 1. Telegram Bridge (`apps/telegram-bridge/`)

Standalone application. Single `index.ts` (~400 lines) that:
- Manages Claude Code CLI as a child process with `--sdk-url`
- Translates Telegram Bot API messages to/from CLI WebSocket protocol
- Forwards all `control_request` messages as Telegram inline keyboards
- Formats responses as HTML, chunks at 4000 chars on double-newline boundaries
- Queues concurrent messages serially

### 2. Operational Scripts (`apps/telegram-bridge/scripts/`)

- `deploy.sh` -- Build, tag, push to GHCR, SSH pull + restart
- `remote.sh` -- SSH wrapper: status, logs, restart, health

### 3. Terraform Config (`apps/telegram-bridge/infra/`)

Hand-crafted Terraform for Hetzner CX22 + firewall + volume. Local state.

## Milestones

1. **M1: Bridge + Container** -- Telegram sends/receives messages through Claude Code CLI in Docker
2. **M2: Deploy to Hetzner** -- Terraform provisions VM, bridge runs in production
