# Tasks: Cloud Deploy -- Run Soleur on Hetzner via Telegram

**Plan:** `knowledge-base/plans/2026-02-10-feat-cloud-deploy-telegram-bridge-plan.md`
**Issue:** [#28](https://github.com/jikig-ai/soleur/issues/28)

[Updated 2026-02-10] Simplified to 2 phases after plan review.

## Phase 1: Build the Bridge

- [ ] 1.1 Scaffold `apps/telegram-bridge/`
  - [ ] 1.1.1 Initialize `package.json` with bun, grammy, @grammyjs/parse-mode
  - [ ] 1.1.2 Create `tsconfig.json` for Bun runtime
  - [ ] 1.1.3 Create `.env.example` with: `TELEGRAM_BOT_TOKEN`, `TELEGRAM_ALLOWED_USER_ID`, `WS_PORT`
- [ ] 1.2 Implement bridge in `src/index.ts` (~400 lines, single file)
  - [ ] 1.2.1 Config: load env vars, fail fast if missing
  - [ ] 1.2.2 WebSocket server on `127.0.0.1:WS_PORT` via Bun; wait for CLI `system/init`
  - [ ] 1.2.3 Spawn Claude CLI with `--sdk-url`; detect crash; auto-restart
  - [ ] 1.2.4 grammY bot: long polling, HTML parse mode, auth middleware (reject non-owner)
  - [ ] 1.2.5 Bridge-native commands: `/start`, `/status`, `/cancel`, `/help`
  - [ ] 1.2.6 Message relay: Telegram -> NDJSON user -> CLI; CLI assistant -> HTML -> Telegram
  - [ ] 1.2.7 Permissions: `control_request` -> inline keyboard; callback -> `control_response`; 5-min auto-deny
  - [ ] 1.2.8 Formatting: escape `&`/`<`/`>`, bold, code blocks; strip unsupported elements
  - [ ] 1.2.9 Chunking: split at 4000 chars on double-newline; hard-split if still too long
  - [ ] 1.2.10 Concurrent messages: queue serially, send "still processing" acknowledgment
  - [ ] 1.2.11 Health endpoint: `Bun.serve()` on :8080, `/health` returns bridge+CLI+bot status
  - [ ] 1.2.12 Graceful shutdown on SIGINT/SIGTERM
- [ ] 1.3 Containerize
  - [ ] 1.3.1 Create single-stage `Dockerfile` (Bun + git + Claude CLI + Soleur plugin)
  - [ ] 1.3.2 Create `.dockerignore` (node_modules, .env, infra/, .git, scripts/)
  - [ ] 1.3.3 Non-root user, VOLUME for persistent data, HEALTHCHECK
- [ ] 1.4 Operational scripts
  - [ ] 1.4.1 `scripts/deploy.sh` -- build, tag (git SHA + latest), push to GHCR, SSH pull+restart
  - [ ] 1.4.2 `scripts/remote.sh` -- SSH wrapper: status, logs, restart, health
- [ ] 1.5 Local integration test: build image, run container, send Telegram message, get response

## Phase 2: Deploy to Hetzner

- [ ] 2.1 Create `apps/telegram-bridge/infra/` Terraform config
  - [ ] 2.1.1 `main.tf` -- Hetzner provider (local state, no remote backend)
  - [ ] 2.1.2 `variables.tf` -- hcloud_token, admin_ips, ssh_key_path
  - [ ] 2.1.3 `server.tf` -- CX22, `keep_disk = true`, cloud-init
  - [ ] 2.1.4 `firewall.tf` -- SSH (restricted IPs), ICMP only
  - [ ] 2.1.5 `cloud-init.yml` -- Docker install, container pull+run, log rotation, SSH hardening
  - [ ] 2.1.6 `outputs.tf` -- Server IP, SSH command
  - [ ] 2.1.7 `.gitignore` -- terraform.tfstate*, terraform.tfvars, .terraform/
- [ ] 2.2 Create volume resource (10GB) for persistent data
- [ ] 2.3 Test: `terraform apply` provisions VM, SCP `.env`, SSH `claude login`, send Telegram message
- [ ] 2.4 Document bootstrap sequence in README.md inside `apps/telegram-bridge/`
- [ ] 2.5 Commit all artifacts, push, create PR
