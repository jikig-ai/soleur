---
title: "TR9 PR-11: migrate scheduled-ux-audit to Inngest cron (substrate extension)"
date: 2026-05-25
lane: cross-domain
brand_survival_threshold: single-user incident
parent_issue: 3948
brainstorm: knowledge-base/project/brainstorms/2026-05-25-cron-ux-audit-inngest-substrate-brainstorm.md
---

# Spec: TR9 PR-11 — Migrate scheduled-ux-audit to Inngest cron substrate

## Problem Statement

`scheduled-ux-audit.yml` is the last group-(c) agent-loop cron workflow that requires **substrate-level changes** (Playwright Chromium + Playwright MCP) beyond the clean-port template established by PR-1..PR-10. The Hetzner Docker image (`apps/web-platform/Dockerfile`) currently installs only `ca-certificates git bubblewrap socat qpdf` — no browser runtime, no browser-specific system libraries. The ux-audit skill needs Playwright Chromium to screenshot authenticated routes via the Playwright MCP server.

Additionally, the ux-audit workflow has a unique bot-fixture lifecycle (shared `ux-audit-bot@jikigai.com` Supabase state, short-TTL storageState JWT) and a findings-upload requirement (GHA's `actions/upload-artifact` has no Inngest equivalent) that no prior cron handler addressed.

## Goals

1. Port `scheduled-ux-audit.yml` to `cron-ux-audit.ts` on the Inngest substrate with full ADR-033 invariant compliance.
2. Extend the Hetzner Docker image with Playwright Chromium + browser deps (image-bake, not runtime-install).
3. Amend ADR-033 to acknowledge the extended binary-pin surface (I4) and codify Chromium process-group reaping (new I7).
4. Ship a deterministic smoke handler (`cron-playwright-smoke.ts`) proving the Playwright substrate before the full cron-ux-audit lands.
5. Implement CLO-mandated storage-state hardening controls (short JWT TTL, entry sentinel, finally-unlink).
6. Create a Supabase private bucket (`ux-audit-artifacts`) for findings + screenshot upload with RLS and 5-min signed URLs.
7. Mirror permanent-dry-run policy (`UX_AUDIT_DRY_RUN=true`) from the source workflow.
8. Delete `.github/workflows/scheduled-ux-audit.yml` atomically in the same commit as `cron-ux-audit.ts`.

## Non-Goals

- **Calibration unlock.** No attempt to flip `UX_AUDIT_DRY_RUN=false`. Filed as separate follow-up issue.
- **Cadence change.** Monthly `0 9 1 * *` stays. No weekly option.
- **ADR-033 ID collision fix.** Three files at slot 033 — reconciliation is out-of-scope.
- **`bot-fixture-shared-state` dual-key concurrency.** YAGNI — `cron-platform` already serializes all cron-* handlers. Add dual-key only when a non-cron event-fn touches bot-fixture.
- **claude-code version bump.** `package.json:25` already pins `2.1.142`; Dockerfile L45 global-install is a separate concern.
- **`/soleur:migrate-cron-to-inngest` skill update.** PR-11 is substrate-extending; fold into skill only if a future substrate-extension reuses ≥60% of the template.

## Functional Requirements

| ID | Requirement | PR |
|----|-------------|-----|
| FR1 | Dockerfile bakes Playwright Chromium + system deps (`libnss3`, `libdbus-1-3`, `libatk1.0-0`, `libcups2`, `libxkbcommon0`, etc.) via `npx playwright install --with-deps chromium`. Chromium revision pinned to `apps/web-platform/package.json` Playwright devDep. | A |
| FR2 | `cron-playwright-smoke.ts` opens `https://example.com` via claude-code + Playwright MCP (full-stack roundtrip: substrate→bwrap→claude-code→MCP→Chromium), screenshots, returns `{ok: true}`. Monthly `0 9 15 * *` (mid-month, offset from ux-audit's 1st-of-month). | A |
| FR3 | Sentry cron monitor `scheduled-playwright-smoke` with heartbeat. Terraform resource in `cron-monitors.tf`. | A |
| FR4 | ADR-033 `[Refined 2026-MM-DD]` amendment: I4 extends binary-pin surface to include Chromium revision; new I7 codifies Chromium process-group reaping requirement (handler MUST assert zero orphan chrome processes after SIGKILL window). | A |
| FR5 | Bot-fixture seed + Supabase signin extracted as library functions importable from the Inngest handler (not CLI spawn). `step.run('bot-fixture-seed', ...)` + `step.run('bot-signin', ...)`. | B |
| FR6 | storageState convention: `mkdtemp('/tmp/ux-audit-')` + `chmod(dir, 0o700)` + `chmod(file, 0o600)`. JWT TTL = 10 min (`expiresIn: 600`). `try/finally` unlink with 3× retry (100ms backoff); on final failure → Sentry `error` + handler exits non-zero. Entry sentinel asserting `find /tmp -maxdepth 1 -name 'ux-audit-*' \| wc -l == 0` at handler entry. | B |
| FR7 | Supabase migration: `ux-audit-artifacts` private bucket. RLS scoped to ux-audit-bot tenant. Path convention: `{inngest_run_id}/{route_slug}.png` + `{inngest_run_id}/findings.json`. | B |
| FR8 | `cron-ux-audit.ts` handler: monthly `0 9 1 * *`, verbatim-extracted prompt (with anchor-string assertions per existing test convention), `--model claude-opus-4-7`, `--max-turns 80`, `--allowedTools` including `mcp__playwright__*` tools. `UX_AUDIT_DRY_RUN=true` in spawn env. | C |
| FR9 | Per-fire `.mcp.json` overlay materialised by the handler (mirrors `.claude/settings.json` overlay pattern). Playwright MCP entry points at `<mkdtemp>/playwright-mcp-profile/` as `--user-data-dir` (NOT `--isolated`; NOT operator home path). MCP Playwright version must match baked Chromium revision. | C |
| FR10 | Findings + screenshot upload to Supabase `ux-audit-artifacts` bucket after claude-code returns. 5-min signed URL generated per artifact. URLs (not image bytes) posted as a comment to PRIVATE monitoring repo issue. | C |
| FR11 | Delete `.github/workflows/scheduled-ux-audit.yml` in the SAME commit as `cron-ux-audit.ts` lands (TR9 I-13 hygiene). Sentry monitor `scheduled-ux-audit` atomic swap (old GHA monitor retired, new Inngest monitor created). | C |
| FR12 | `cron-platform` account-scope concurrency key (limit=1), matching all existing cron-* handlers. No new `bot-fixture-shared-state` key. | C |
| FR13 | GH installation token minted via `createProbeOctokit()` → `generateInstallationToken(installation.id)` with 60-min TTL. Injected as `GH_TOKEN` for `gh` CLI use inside the spawned claude-code. | C |

## Technical Requirements

| ID | Requirement | PR |
|----|-------------|-----|
| TR1 | I3 verification gate (plan-time Phase 0.3): spawn claude-code with Playwright MCP, trigger AbortSignal, `ps -ef --forest` count check after 5s escalation. Refuse PR-A merge if orphan `chrome --type=zygote/renderer` processes survive. If orphans found, add `pkill` reaper (I7) before landing. | A |
| TR2 | Dockerfile Playwright layer cached independently (multi-stage layer ordering) so non-Playwright image rebuilds don't re-pull ~500MB. | A |
| TR3 | Test: `cron-playwright-smoke.test.ts` — anchor-string assertion + deterministic `step.run` return shape per ADR-033 I5. | A |
| TR4 | Test: `cron-ux-audit.test.ts` — anchor-string assertions, no-BYOK sweep (I2), concurrency key assertion, prompt verbatim diff. | C |
| TR5 | `cron-no-byok-lease-sweep.test.ts` updated to include `cron-playwright-smoke.ts` and `cron-ux-audit.ts`. | A+C |
| TR6 | Dual-lockfile sync (`bun.lock` + `package-lock.json`) regenerated atomically. Check `bunfig.toml` `minimumReleaseAge=259200` for `@playwright/mcp` version (must be ≥3 days old). | A |
| TR7 | Supabase migration passes `supabase db push --dry-run` and does not regress existing RLS policies. | B |

## Rollout Sequence

```
PR-A (substrate-gap closure)
├── Dockerfile + Playwright deps
├── cron-playwright-smoke.ts + test
├── Sentry monitor
├── ADR-033 I4 amend + I7 new
├── I3 verification gate
└── SHIP → deploy → validate smoke fire

PR-B (bot-fixture lifecycle)
├── bot-fixture seed/signin library extraction
├── storageState hardening (CLO controls)
├── Supabase ux-audit-artifacts bucket migration
└── SHIP → deploy → validate bucket access

PR-C (cron-ux-audit + GHA delete)
├── cron-ux-audit.ts + prompt file
├── .mcp.json per-fire overlay
├── Supabase upload + signed URL post
├── DELETE scheduled-ux-audit.yml (atomic)
├── Sentry monitor swap
└── SHIP → deploy → validate first monthly fire
```
