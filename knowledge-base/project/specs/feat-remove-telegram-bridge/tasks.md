# Tasks: Remove Telegram Bridge

## Phase 1: Infrastructure Teardown

- [ ] 1.1 Stop and remove `soleur-bridge` Docker container on CX33 server
  - `ssh root@135.181.45.178 "docker stop soleur-bridge && docker rm soleur-bridge"`
  - Verify: `ssh root@135.181.45.178 "docker ps"` shows no `soleur-bridge`
- [ ] 1.2 Run `terraform destroy` in `apps/telegram-bridge/infra/`
  - Initialize: `terraform init` in `apps/telegram-bridge/infra/`
  - Destroy: `doppler run -p soleur -c prd_terraform --name-transformer tf-var -- terraform destroy`
  - Resources destroyed: Cloudflare tunnel, DNS CNAME, Access app, service token, Access policy
- [ ] 1.3 Remove 6 GitHub repo secrets
  - `gh secret delete TELEGRAM_ALLOWED_USER_ID`
  - `gh secret delete TELEGRAM_BOT_TOKEN`
  - `gh secret delete TELEGRAM_BRIDGE_HOST`
  - `gh secret delete CF_ACCESS_CLIENT_ID_BRIDGE`
  - `gh secret delete CF_ACCESS_CLIENT_SECRET_BRIDGE`
  - `gh secret delete WEBHOOK_DEPLOY_SECRET_BRIDGE`
- [ ] 1.4 Remove Doppler secrets (TELEGRAM_ALLOWED_USER_ID, TELEGRAM_BOT_TOKEN)
  - From configs: `prd`, `prd_terraform`, `ci`
- [ ] 1.5 Prune Docker images on server
  - `ssh root@135.181.45.178 "docker image prune -af"`

## Phase 2: Code and Config Removal

- [ ] 2.1 Delete `apps/telegram-bridge/` directory
- [ ] 2.2 Delete `.github/workflows/telegram-bridge-release.yml`
- [ ] 2.3 Edit `.github/workflows/ci.yml`
  - Remove "Install telegram-bridge dependencies" step (lines 68-70)
  - Remove "Enforce telegram-bridge coverage" step (lines 77-79)
- [ ] 2.4 Edit `.github/workflows/main-health-monitor.yml`
  - Remove "Install telegram-bridge dependencies" step (lines 44-46)
- [ ] 2.5 Edit `.github/workflows/scheduled-terraform-drift.yml`
  - Remove `apps/telegram-bridge/infra` from matrix (line 33)
  - Remove comment about telegram-bridge (line 83)
- [ ] 2.6 Edit `scripts/test-all.sh`
  - Remove line: `run_suite "apps/telegram-bridge" bun test apps/telegram-bridge/`
- [ ] 2.7 Edit `apps/web-platform/infra/ci-deploy.sh`
  - Remove `[telegram-bridge]="ghcr.io/jikig-ai/soleur-telegram-bridge"` from ALLOWED_IMAGES
  - Remove `telegram-bridge)` case handler (lines 217-247)
- [ ] 2.8 Edit `apps/web-platform/infra/ci-deploy.test.sh`
  - Remove telegram-bridge test cases and mock curl handler

## Phase 3: Documentation Updates

- [ ] 3.1 Edit `AGENTS.md`
  - Line 26: Change `apps/telegram-bridge/infra/` reference to `apps/web-platform/infra/` only
  - Line 28: Change R2 backend template reference from `apps/telegram-bridge/infra/main.tf` to `apps/web-platform/infra/main.tf`
- [ ] 3.2 Edit `knowledge-base/engineering/architecture/diagrams/container.md`
  - Remove `System_Ext(telegram_api, ...)` external system
  - Remove `Container_Boundary(tgbridge, ...)` and `Container(tgbot, ...)` elements
  - Remove `Rel(tgbot, telegram_api, ...)` relation
  - Remove telegram bullet from notes
  - Update `Container(hetzner, ...)` description to remove "and telegram bridge"
- [ ] 3.3 Edit `knowledge-base/engineering/architecture/diagrams/system-context.md`
  - Remove `System_Ext(telegram, ...)` external system
  - Remove `Rel(founder, telegram, ...)` and `Rel(telegram, engine, ...)` relations
  - Remove telegram bullet from notes
- [ ] 3.4 Edit `knowledge-base/engineering/architecture/nfr-register.md`
  - Remove all rows containing "Telegram Bot"
- [ ] 3.5 Edit `knowledge-base/legal/compliance-posture.md`
  - Update Hetzner DPA row: remove "and CX22 (telegram-bridge)"
- [ ] 3.6 Edit `knowledge-base/operations/expenses.md`
  - Remove CX22 line
  - Update `last_updated` frontmatter to 2026-04-06
- [ ] 3.7 Edit `knowledge-base/engineering/ops/runbooks/disk-monitoring.md`
  - Remove "(telegram-bridge CX22 deferred)" from servers line
- [ ] 3.8 Edit `knowledge-base/product/roadmap.md`
  - Update line 113 to note removal/archival, not just deferral

## Phase 4: Knowledge-Base Archival

- [ ] 4.1 Archive telegram-specific plans (3 files)
  - `2026-03-02-feat-telegram-streamed-responses-plan.md`
  - `2026-03-19-fix-telegram-bridge-deploy-health-check-plan.md`
  - `2026-03-20-fix-telegram-bridge-health-endpoint-early-start-plan.md`
- [ ] 4.2 Archive telegram-specific brainstorm (1 file)
  - `2026-03-02-telegram-streaming-brainstorm.md`
- [ ] 4.3 Archive telegram-specific specs (2 directories)
  - `feat-telegram-streaming/`
  - `fix-tg-health-864/`
- [ ] 4.4 Archive telegram-specific learnings (3 files)
  - `runtime-errors/2026-02-11-async-status-message-lifecycle-telegram.md`
  - `technical-debt/2026-03-03-telegram-bridge-index-ts-mixed-concerns.md`
  - `2026-03-02-telegram-streaming-repurpose-status-message.md`
- [ ] 4.5 Delete `knowledge-base/project/components/telegram-bridge.md`

## Phase 5: GitHub Issue Cleanup

- [ ] 5.1 Close 7 telegram-specific issues with removal comment
  - #1503 (bridge docs reference /mnt/data/.env)
  - #1061 (bridge integration for cloud platform)
  - #1530 (disk monitoring for CX22)
  - #381 (sendMessageDraft streaming)
  - #42 (healthchecks.io monitoring)
  - #43 (multiple messaging adapters -- superseded by #1286)
  - #1286 is kept open but re-scoped
- [ ] 5.2 Update 4 broader issues to remove telegram references
  - #1286 (channel connectors -- update body, note bridge removed)
  - #1569 (seccomp per-container -- update body, remove bridge refs)
  - #1497 (Doppler per-container -- update body, remove bridge refs)
  - #1055 (LLM cost observability -- update body, remove bridge refs)
  - Note: #1215 (BYOM guide) has only a passing mention; update is optional

## Phase 6: Verification

- [ ] 6.1 Run `bash scripts/test-all.sh` -- all suites pass
- [ ] 6.2 Run `bash apps/web-platform/infra/ci-deploy.test.sh` -- all tests pass
- [ ] 6.3 Verify `grep -r "telegram" .github/workflows/ scripts/test-all.sh` returns no matches
- [ ] 6.4 Verify `grep -ri "telegram" AGENTS.md` returns no matches
- [ ] 6.5 Verify `ssh root@135.181.45.178 "docker ps"` shows only `soleur-web-platform`
- [ ] 6.6 Verify `dig deploy-bridge.soleur.ai` returns NXDOMAIN
