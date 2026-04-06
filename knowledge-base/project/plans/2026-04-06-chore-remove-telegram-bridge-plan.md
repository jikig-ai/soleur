---
title: "chore: remove Telegram bridge entirely"
type: chore
date: 2026-04-06
---

# Remove Telegram Bridge

## Overview

Remove the Telegram bridge application, its infrastructure, CI pipelines, knowledge-base artifacts, and all references. The bridge architecture is incorrect after the cloud platform pivot -- it will be reconsidered later as a proxy channel using the same backend as other platforms (web, mobile, desktop). See roadmap line 1.12 (already deferred).

## Problem Statement / Motivation

The Telegram bridge (`apps/telegram-bridge/`) was the original mobile interface to Soleur, bridging Telegram messages to Claude Code CLI via stdin/stdout. After the pivot to a cloud-first PWA platform (app.soleur.ai), the bridge is:

1. **Architecturally wrong** -- it spawns a local Claude Code CLI process per message, while the cloud platform uses the Agent SDK with WebSocket streaming. Rebuilding as a "channel connector" (#1286) would use the same backend as web/mobile/desktop.
2. **Adding complexity** -- separate Dockerfile, separate release workflow, separate Cloudflare tunnel, separate deploy handler in `ci-deploy.sh`, separate CI steps, 30+ knowledge-base files.
3. **Costing money for no users** -- the `soleur-bridge` Docker container runs on the CX33 server alongside web-platform but serves only the founder (who now uses the web platform).

## Current State (Research Findings)

### Infrastructure

- **Server**: Telegram bridge container (`soleur-bridge`) runs on the **same CX33 server** as web-platform (135.181.45.178). There is NO separate CX22 server -- the expenses.md entry is stale.
- **Terraform** (`apps/telegram-bridge/infra/`): Manages only Cloudflare resources -- tunnel (`soleur-telegram-bridge`), DNS CNAME (`deploy-bridge.soleur.ai`), Access application + service token, Access policy. No Hetzner resources.
- **Docker**: `soleur-bridge` container running `ghcr.io/jikig-ai/soleur-telegram-bridge:v0.1.28`

### Secrets to Remove

**GitHub repo secrets** (6):

- `TELEGRAM_ALLOWED_USER_ID`
- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_BRIDGE_HOST`
- `CF_ACCESS_CLIENT_ID_BRIDGE`
- `CF_ACCESS_CLIENT_SECRET_BRIDGE`
- `WEBHOOK_DEPLOY_SECRET_BRIDGE`

**Doppler secrets** (2 keys across 3 configs):

- `TELEGRAM_ALLOWED_USER_ID` in `prd`, `prd_terraform`, `ci`
- `TELEGRAM_BOT_TOKEN` in `prd`, `prd_terraform`, `ci`

### CI Workflows Affected

| Workflow | Change |
|----------|--------|
| `telegram-bridge-release.yml` | Delete entirely |
| `ci.yml` | Remove "Install telegram-bridge dependencies" step (lines 68-70) and "Enforce telegram-bridge coverage" step (lines 77-79) |
| `main-health-monitor.yml` | Remove "Install telegram-bridge dependencies" step (lines 44-46) |
| `scheduled-terraform-drift.yml` | Remove `apps/telegram-bridge/infra` from matrix (line 33) and the comment about telegram-bridge (line 83) |

### Scripts Affected

| Script | Change |
|--------|--------|
| `scripts/test-all.sh` | Remove line 56: `run_suite "apps/telegram-bridge" bun test apps/telegram-bridge/` |
| `apps/web-platform/infra/ci-deploy.sh` | Remove `telegram-bridge` from `ALLOWED_IMAGES` map, remove `telegram-bridge)` case handler (lines 217-247) |
| `apps/web-platform/infra/ci-deploy.test.sh` | Remove telegram-bridge test cases and mock curl handler |

### AGENTS.md References (2)

1. Line 26: "Existing Terraform patterns live in `apps/telegram-bridge/infra/` and `apps/web-platform/infra/`" -- update to reference only `apps/web-platform/infra/`
2. Line 28: "Copy the backend block from `apps/telegram-bridge/infra/main.tf`" -- update to reference `apps/web-platform/infra/main.tf`

### Architecture Docs

| File | Change |
|------|--------|
| `knowledge-base/engineering/architecture/diagrams/container.md` | Remove Telegram Bot container, Telegram API external system, related relations |
| `knowledge-base/engineering/architecture/diagrams/system-context.md` | Remove Telegram external system and relations |
| `knowledge-base/engineering/architecture/nfr-register.md` | Remove all "Telegram Bot" rows (~30 rows across all NFR categories) |
| `knowledge-base/project/components/telegram-bridge.md` | Delete |
| `knowledge-base/legal/compliance-posture.md` | Update Hetzner DPA row to remove "and CX22 (telegram-bridge)" |
| `knowledge-base/operations/expenses.md` | Remove CX22 line (stale -- server already gone), update last_updated date |
| `knowledge-base/engineering/ops/runbooks/disk-monitoring.md` | Remove "(telegram-bridge CX22 deferred)" reference |
| `knowledge-base/product/roadmap.md` | Line 113 already says "Deferred" -- update to note removal/archive |

### Knowledge-Base Files to Archive

**Plans** (4 active, 1 already archived):

- `2026-03-02-feat-telegram-streamed-responses-plan.md`
- `2026-03-19-fix-telegram-bridge-deploy-health-check-plan.md`
- `2026-03-20-fix-telegram-bridge-health-endpoint-early-start-plan.md`

**Brainstorms** (1):

- `2026-03-02-telegram-streaming-brainstorm.md`

**Specs** (2 directories):

- `feat-telegram-streaming/`
- `fix-tg-health-864/`

**Learnings** (3):

- `runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md`
- `technical-debt/2026-03-03-telegram-bridge-index-ts-mixed-concerns.md`
- `2026-03-02-telegram-streaming-repurpose-status-message.md`

**Component doc** (1):

- `knowledge-base/project/components/telegram-bridge.md`

### GitHub Issues to Close (11)

| Issue | Title | Action | Rationale |
|-------|-------|--------|-----------|
| #1503 | review: telegram-bridge docs still reference /mnt/data/.env | Close | Moot -- bridge removed |
| #1061 | feat: Telegram bridge integration for cloud platform workspaces | Close | Bridge removed; will be redesigned as channel connector |
| #1530 | feat(observability): add disk monitoring to telegram-bridge CX22 | Close | No CX22 server exists |
| #381 | feat: Add sendMessageDraft native streaming to Telegram bridge | Close | Bridge removed |
| #42 | feat: Proactive monitoring with healthchecks.io + ntfy.sh | Close | Originally scoped to telegram bridge |
| #1286 | feat: channel connectors (Telegram, Discord, WhatsApp) | Keep open | Broader scope -- update body to note bridge removal, re-scope as green-field |
| #43 | feat: Multiple messaging platform adapters | Close | Superseded by #1286 (channel connectors) |
| #1569 | review: move seccomp to per-container --security-opt | Keep open | Web-platform-specific; update body to remove telegram-bridge references |
| #1497 | arch: move Doppler secrets into Docker containers | Keep open | Architectural pattern applies to web-platform; update body to remove bridge refs |
| #1215 | docs: BYOM guide for Ollama | Keep open | No telegram dependency; update body to remove bridge model reference |
| #1055 | feat: per-workflow LLM cost observability | Keep open | Broader scope; update body to remove bridge references |

**Net: Close 7 issues, update 4 issues, keep 0 unchanged.**

## Proposed Solution

### Phase 1: Infrastructure Teardown (Before Code Changes)

Order matters: destroy infra first, then remove code.

1. **Stop the bridge container** on the CX33 server via SSH:
   `ssh root@135.181.45.178 "docker stop soleur-bridge && docker rm soleur-bridge && docker image prune -af"`
   (Read-only exception: this is a one-time teardown, not ongoing server management)

2. **Run `terraform destroy`** in `apps/telegram-bridge/infra/` to remove Cloudflare tunnel, DNS CNAME, Access application, service token, and Access policy:

   ```text
   cd apps/telegram-bridge/infra
   terraform init
   doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform destroy
   ```

3. **Remove GitHub repo secrets** (6 secrets via `gh secret delete`)

4. **Remove Doppler secrets** (`TELEGRAM_ALLOWED_USER_ID`, `TELEGRAM_BOT_TOKEN` from `prd`, `prd_terraform`, `ci` configs)

5. **Clean up R2 state**: After `terraform destroy`, the state file at `telegram-bridge/terraform.tfstate` in R2 can be left (empty state) or deleted.

### Phase 2: Code and Config Removal

1. **Delete** `apps/telegram-bridge/` directory entirely
2. **Delete** `.github/workflows/telegram-bridge-release.yml`
3. **Edit** `.github/workflows/ci.yml` -- remove telegram-bridge install and coverage steps
4. **Edit** `.github/workflows/main-health-monitor.yml` -- remove telegram-bridge install step
5. **Edit** `.github/workflows/scheduled-terraform-drift.yml` -- remove telegram-bridge from matrix and comment
6. **Edit** `scripts/test-all.sh` -- remove telegram-bridge test suite line
7. **Edit** `apps/web-platform/infra/ci-deploy.sh` -- remove telegram-bridge from ALLOWED_IMAGES and case handler
8. **Edit** `apps/web-platform/infra/ci-deploy.test.sh` -- remove telegram-bridge test cases

### Phase 3: Documentation Updates

1. **Edit** `AGENTS.md` -- update Terraform pattern references from telegram-bridge to web-platform
2. **Edit** architecture diagrams (container.md, system-context.md) -- remove Telegram elements
3. **Edit** `nfr-register.md` -- remove all Telegram Bot rows
4. **Edit** `compliance-posture.md` -- update Hetzner DPA line
5. **Edit** `expenses.md` -- remove CX22 line, update date
6. **Edit** `disk-monitoring.md` -- remove bridge reference
7. **Edit** `roadmap.md` -- note removal (already deferred)

### Phase 4: Knowledge-Base Archival

Archive telegram-specific plans, brainstorms, specs, learnings, and component doc using the archive-kb skill.

### Phase 5: GitHub Issue Cleanup

1. Close 7 telegram-specific issues with comment explaining removal
2. Update 4 broader issues to remove telegram-bridge references

## Acceptance Criteria

- [ ] No `soleur-bridge` container running on CX33 server
- [ ] Cloudflare tunnel `soleur-telegram-bridge` destroyed (no `deploy-bridge.soleur.ai` DNS)
- [ ] `apps/telegram-bridge/` directory deleted
- [ ] `.github/workflows/telegram-bridge-release.yml` deleted
- [ ] CI workflows (`ci.yml`, `main-health-monitor.yml`, `scheduled-terraform-drift.yml`) have no telegram references
- [ ] `scripts/test-all.sh` has no telegram references
- [ ] `ci-deploy.sh` and `ci-deploy.test.sh` have no telegram-bridge references
- [ ] `AGENTS.md` references `apps/web-platform/infra/main.tf` instead of `apps/telegram-bridge/infra/main.tf`
- [ ] Architecture diagrams have no Telegram elements
- [ ] `nfr-register.md` has no Telegram Bot rows
- [ ] `expenses.md` has no CX22 line
- [ ] 6 GitHub secrets removed
- [ ] Doppler telegram secrets removed from prd, prd_terraform, ci configs
- [ ] 7 GitHub issues closed, 4 updated
- [ ] Telegram-specific knowledge-base files archived
- [ ] `bun test` and `scripts/test-all.sh` pass without telegram-bridge
- [ ] `ci-deploy.test.sh` passes without telegram-bridge test cases

## Test Scenarios

- Given the bridge container is stopped, when `ssh root@135.181.45.178 "docker ps"`, then `soleur-bridge` is NOT listed
- Given `terraform destroy` succeeded, when resolving `deploy-bridge.soleur.ai`, then DNS returns NXDOMAIN
- Given the code changes, when `bash scripts/test-all.sh` runs, then all suites pass
- Given the code changes, when `bash apps/web-platform/infra/ci-deploy.test.sh` runs, then all tests pass
- Given the code changes, when `grep -r "telegram" .github/workflows/ scripts/test-all.sh apps/web-platform/infra/ci-deploy.sh` runs, then no matches found

## Domain Review

**Domains relevant:** Engineering, Operations, Finance

### Engineering

**Status:** reviewed
**Assessment:** Straightforward removal. The Terraform state manages only Cloudflare resources (no Hetzner -- the CX22 is already gone). CI changes are mechanical deletions. Architecture diagrams and NFR register need row removals. The `ci-deploy.sh` telegram-bridge case handler removal is the only code change requiring test verification. Risk: low.

### Operations

**Status:** reviewed
**Assessment:** Removes stale CX22 expense line (server already decommissioned). Reduces operational surface: fewer Docker containers, fewer secrets, fewer CI jobs, one less Terraform state to drift-check. Net cost reduction: EUR 5.83/mo (the CX22 line, though already stale). Actual cost reduction: 0 (server already gone). Complexity reduction is the real value.

### Finance

**Status:** reviewed
**Assessment:** The CX22 line in expenses.md shows EUR 5.83/mo but the server no longer exists -- the expense is already zero. This change corrects the record. No budget impact.

## References

- Roadmap line 1.12: "Telegram bridge -- Deferred to a later phase"
- Channel connectors issue: #1286
- Hetzner server list: only `soleur-web-platform` (CX33) exists
- Docker containers on CX33: `soleur-web-platform` + `soleur-bridge`
- Terraform state: `telegram-bridge/terraform.tfstate` in R2 bucket `soleur-terraform-state`
