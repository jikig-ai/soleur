---
title: "TR9 PR-11: tasks"
date: 2026-05-25
plan: knowledge-base/project/plans/2026-05-25-feat-tr9-pr11-cron-ux-audit-inngest-substrate-plan.md
---

# Tasks: TR9 PR-11 — cron-ux-audit-inngest-substrate

## PR-1: Substrate + Bot-Fixture Exports + Migration

### 0. I3 Verification Gate
- [ ] 0.1 Build Docker image with Playwright layer (Phase 1 below)
- [ ] 0.2 Inside container: spawn claude-code --print with Playwright MCP, trigger AbortSignal after 10s
- [ ] 0.3 ps -ef --forest: assert zero orphan chrome processes after 5s SIGKILL window
- [ ] 0.4 If orphans found: implement pkill reaper + ADR-033 I7. If clean: note in PR body.

### 1. Dockerfile — Playwright Browser Deps
- [ ] 1.1 Add `RUN npx playwright@1.58.2 install --with-deps chromium` to runner stage BEFORE `npm ci --omit=dev` (after apt-get block L57-59)
- [ ] 1.2 Verify: `docker build --target runner` succeeds
- [ ] 1.3 Verify: `npx playwright@1.58.2 --version` inside container returns 1.58.2

### 2. Bot-Fixture + Bot-Signin Exports
- [ ] 2.1 `bot-fixture.ts` L195: add `export` to `seed()`
- [ ] 2.2 `bot-fixture.ts` L228: add `export` to `reset()`
- [ ] 2.3 Verify CLI `bun bot-fixture.ts seed` still works
- [ ] 2.4 `bot-signin.ts`: export `signIn()` (already returns Session)
- [ ] 2.5 `bot-signin.ts`: extract file-writing from `main()` L96-L123 into `export function writeStorageState(session, outPath, supabaseUrl, siteUrl)`
- [ ] 2.6 Verify `if (import.meta.main)` CLI entry unchanged

### 3. Supabase Migration
- [ ] 3.1 Create `071_ux_audit_artifacts_bucket.sql` with DO $$ block (hardcode bot UUID at migration time)
- [ ] 3.2 Create `071_ux_audit_artifacts_bucket.down.sql`
- [ ] 3.3 `supabase db push --dry-run` passes

### 4. ADR-033 + Sentry + Commit
- [ ] 4.1 ADR-033: add `[Refined]` block for I4 (Chromium build-time transitive pin)
- [ ] 4.2 Conditionally add I7 (only if Phase 0 found orphans)
- [ ] 4.3 `cron-monitors.tf`: add `scheduled_ux_audit` resource
- [ ] 4.4 `terraform validate` passes
- [ ] 4.5 Commit and push PR-1

## PR-2: cron-ux-audit Handler + GHA Delete

### 5. Handler Implementation
- [ ] 5.1 Create `cron-ux-audit.ts` mirroring cron-legal-audit.ts structure
- [ ] 5.2 Constants: SENTRY_MONITOR_SLUG, MAX_TURN_DURATION_MS (50min), KILL_ESCALATION_MS (5s)
- [ ] 5.3 CLAUDE_CODE_FLAGS with Playwright MCP tools in --allowedTools
- [ ] 5.4 Verbatim prompt from scheduled-ux-audit.yml:170-191
- [ ] 5.5 step.run('bot-fixture-seed'): import seed() from bot-fixture.ts
- [ ] 5.6 step.run('bot-signin'): import signIn() + writeStorageState(), mkdtemp 0o700, file 0o600, default 3600s JWT TTL
- [ ] 5.7 step.run('claude-eval'): spawn with UX_AUDIT_DRY_RUN=true, UX_AUDIT_STORAGE_STATE env
- [ ] 5.8 Per-fire .mcp.json overlay: --user-data-dir=<mkdtemp>/playwright-mcp-profile/ (NOT --isolated)
- [ ] 5.9 step.run('upload-findings'): upload to ux-audit-artifacts bucket, 5-min signed URLs, post to PRIVATE monitoring issue
- [ ] 5.10 step.run('bot-fixture-reset'): import reset()
- [ ] 5.11 Finally block: single-attempt rm + reportSilentFallback on failure (NO process.exit)
- [ ] 5.12 cron-platform concurrency key, limit=1
- [ ] 5.13 Sentry heartbeat + GH installation token via createProbeOctokit()
- [ ] 5.14 detached:true spawn with SIGTERM->SIGKILL 5s escalation (I3)

### 6. GHA Delete + Registration
- [ ] 6.1 Delete .github/workflows/scheduled-ux-audit.yml in SAME commit as cron-ux-audit.ts
- [ ] 6.2 app/api/inngest/route.ts: import cronUxAudit, add to functions array
- [ ] 6.3 cron-no-byok-lease-sweep.test.ts: add cron-ux-audit.ts

### 7. Test
- [ ] 7.1 Create cron-ux-audit.test.ts: registration shape smoke
- [ ] 7.2 Prompt anchor-string assertions (4 anchors)
- [ ] 7.3 Timing constant assertions
- [ ] 7.4 All tests pass: `./node_modules/.bin/vitest run test/server/inngest/cron-ux-audit.test.ts`

### 8. AC Verification + Ship
- [ ] 8.1 AC8-AC14 all pass
- [ ] 8.2 Commit and push PR-2
