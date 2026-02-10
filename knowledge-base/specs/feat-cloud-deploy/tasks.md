# Tasks: Cloud Deploy -- Run Soleur on Hetzner via Telegram

**Plan:** `knowledge-base/plans/2026-02-10-feat-cloud-deploy-telegram-bridge-plan.md`
**Issue:** [#28](https://github.com/jikig-ai/soleur/issues/28)

## Phase 1: Bridge MVP

- [ ] 1.1 Scaffold `apps/telegram-bridge/` with Bun + Hono + grammY
  - [ ] 1.1.1 Initialize `package.json` with bun, hono, grammy, @grammyjs/parse-mode
  - [ ] 1.1.2 Create `tsconfig.json` for Bun runtime
  - [ ] 1.1.3 Create `.env.example` with all required env vars
  - [ ] 1.1.4 Create `src/config.ts` -- load + validate env vars, fail fast on missing
- [ ] 1.2 Implement WebSocket bridge (`src/bridge.ts`)
  - [ ] 1.2.1 Create WebSocket server on configurable localhost port
  - [ ] 1.2.2 Spawn Claude CLI as child process with `--sdk-url` flag
  - [ ] 1.2.3 Parse NDJSON messages from CLI WebSocket connection
  - [ ] 1.2.4 Handle CLI lifecycle: crash detection, auto-restart with `--resume`
  - [ ] 1.2.5 Implement health check: CLI process alive + WebSocket connected
  - [ ] 1.2.6 Add `/health` HTTP endpoint (Hono) returning bridge + CLI status
- [ ] 1.3 Implement Telegram bot (`src/telegram.ts`)
  - [ ] 1.3.1 Initialize grammY bot with long polling + HTML parse mode
  - [ ] 1.3.2 Add auth middleware: reject if `ctx.from.id !== ALLOWED_USER_ID`
  - [ ] 1.3.3 Add bridge-native commands: `/start`, `/status`, `/cancel`, `/help`
  - [ ] 1.3.4 Add message handler: forward text messages to bridge
  - [ ] 1.3.5 Add typing indicator during CLI processing
  - [ ] 1.3.6 Add graceful shutdown on SIGINT/SIGTERM
- [ ] 1.4 Implement permission forwarding (`src/permissions.ts`)
  - [ ] 1.4.1 Receive `control_request` from bridge, format as inline keyboard
  - [ ] 1.4.2 Handle callback query: send `control_response` back to bridge
  - [ ] 1.4.3 Implement 5-minute auto-deny timeout with user notification
  - [ ] 1.4.4 Update original message after approve/deny (remove buttons)
- [ ] 1.5 Implement response formatting (`src/formatter.ts` + `src/chunker.ts`)
  - [ ] 1.5.1 Convert markdown to Telegram HTML (bold, code, pre blocks)
  - [ ] 1.5.2 Escape `&`, `<`, `>` in non-formatted text
  - [ ] 1.5.3 Implement chunking: split on double-newline, re-open code blocks
  - [ ] 1.5.4 Send as file attachment if total response >20000 chars
  - [ ] 1.5.5 Add 500ms delay between chunks
- [ ] 1.6 Integration test: send message in Telegram, get CLI response

## Phase 2: Containerization

- [ ] 2.1 Create `Dockerfile` (multi-stage: builder + runtime)
  - [ ] 2.1.1 Stage 1: Bun build for bridge
  - [ ] 2.1.2 Stage 2: Install git, curl, openssh-client, Claude CLI, Soleur plugin
  - [ ] 2.1.3 Create non-root `soleur` user
  - [ ] 2.1.4 Add HEALTHCHECK instruction
  - [ ] 2.1.5 Define VOLUME for persistent data
- [ ] 2.2 Create `.dockerignore` (node_modules, .env, infra/, .git)
- [ ] 2.3 Create `docker-compose.yml` for local development
- [ ] 2.4 Test: build image, run container locally, send Telegram message

## Phase 3: Infrastructure as Code

- [ ] 3.1 Create `apps/telegram-bridge/infra/` Terraform config
  - [ ] 3.1.1 `main.tf` -- Hetzner provider + Backblaze B2 backend
  - [ ] 3.1.2 `variables.tf` -- hcloud_token, admin_ips, ssh_key_path, ghcr_token
  - [ ] 3.1.3 `server.tf` -- CX22 with cloud-init, `keep_disk = true`
  - [ ] 3.1.4 `firewall.tf` -- SSH (restricted IPs), ICMP only
  - [ ] 3.1.5 `cloud-init.yml` -- Docker install, GHCR auth, container pull + run
  - [ ] 3.1.6 `outputs.tf` -- Server IP, SSH command
  - [ ] 3.1.7 Add `terraform.tfvars` to `.gitignore`
- [ ] 3.2 Create volume resource for persistent data (10GB)
- [ ] 3.3 Add SSH hardening to cloud-init (key-only, no password)
- [ ] 3.4 Add Docker log rotation config to cloud-init (10MB, 3 files)
- [ ] 3.5 Test: `terraform apply` from scratch provisions working VM

## Phase 4: Observability

- [ ] 4.1 Add healthchecks.io heartbeat to container (cron every 5 min)
- [ ] 4.2 Configure healthchecks.io -> ntfy.sh integration for alerts
- [ ] 4.3 Add disk/memory alert cron (ntfy.sh push if >85% disk or >90% memory)
- [ ] 4.4 Ensure bridge `/health` checks: process alive, WebSocket connected, bot polling
- [ ] 4.5 Test: stop container, verify alert fires on phone within 10 minutes

## Phase 5: Soleur Plugin Components

- [ ] 5.1 Create deploy skill (`plugins/soleur/skills/deploy/`)
  - [ ] 5.1.1 Write `SKILL.md` with YAML frontmatter (third-person description)
  - [ ] 5.1.2 Write `scripts/deploy.sh` -- build, tag, push to GHCR
  - [ ] 5.1.3 Write `references/hetzner-setup.md` -- first-time setup guide
  - [ ] 5.1.4 Deploy workflow: build image -> push -> SSH -> pull -> restart -> verify health
- [ ] 5.2 Create remote session skill (`plugins/soleur/skills/remote-session/`)
  - [ ] 5.2.1 Write `SKILL.md` with YAML frontmatter
  - [ ] 5.2.2 Write `scripts/remote.sh` -- SSH wrapper: status, logs, restart, health
- [ ] 5.3 Create SRE agent (`plugins/soleur/agents/operations/sre-agent.md`)
  - [ ] 5.3.1 Write agent markdown with YAML frontmatter + examples
  - [ ] 5.3.2 Scope v1: Hetzner VMs, firewall, SSH keys, volumes, cloud-init
  - [ ] 5.3.3 Include observability guidance (healthchecks.io + ntfy.sh patterns)
  - [ ] 5.3.4 Include cost optimization recommendations

## Phase 6: Plugin Versioning and Documentation

- [ ] 6.1 Bump version in `plugins/soleur/.claude-plugin/plugin.json` (MINOR)
- [ ] 6.2 Update `plugins/soleur/CHANGELOG.md` with new components
- [ ] 6.3 Update `plugins/soleur/README.md` -- add agent/skill entries, update counts
- [ ] 6.4 Update root `README.md` version badge
- [ ] 6.5 Update `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder
- [ ] 6.6 Run `bun test` to verify markdownlint passes
- [ ] 6.7 Run `/soleur:compound` to capture learnings
- [ ] 6.8 Commit all artifacts, push, create PR
