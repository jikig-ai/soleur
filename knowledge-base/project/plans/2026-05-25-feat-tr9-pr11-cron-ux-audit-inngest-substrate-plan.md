---
title: "TR9 PR-11: migrate scheduled-ux-audit to Inngest cron (2-stage substrate extension)"
date: 2026-05-25
type: enhancement
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_issue: 4464
umbrella: 3948
---

# Plan: TR9 PR-11 — Migrate scheduled-ux-audit to Inngest cron substrate

## Overview

Two-PR rollout migrating `.github/workflows/scheduled-ux-audit.yml` (monthly `0 9 1 * *`) to the Inngest cron substrate. Unlike TR9 PR-1..PR-10, this is a **substrate extension** — adds Playwright Chromium + Playwright MCP to the Hetzner Docker image and introduces bot-fixture lifecycle + Supabase findings-upload.

**PR-1 (substrate + fixtures):** Dockerfile adds Playwright Chromium, bot-fixture/bot-signin gain `export` keywords, Supabase `ux-audit-artifacts` bucket migration, ADR-033 I4 amendment.

**PR-2 (handler + GHA delete):** `cron-ux-audit.ts` handler with all lifecycle steps, `.mcp.json` per-fire overlay, Supabase upload, delete `scheduled-ux-audit.yml` atomically. Sentry monitors for both PRs.

**Brainstorm:** `knowledge-base/project/brainstorms/2026-05-25-cron-ux-audit-inngest-substrate-brainstorm.md` (11 key decisions, CTO+CPO+CLO triad signed off).

**Spec:** `knowledge-base/project/specs/feat-cron-ux-audit-inngest-substrate/spec.md`.

**Reference handler:** `apps/web-platform/server/inngest/functions/cron-legal-audit.ts` (closest side-effect class: claude-eval + issue-creator).

**Plan Review Applied [2026-05-25]:** DHH (5 findings), Kieran (7 findings), Code Simplicity (7 findings). Consolidated: killed smoke handler (YAGNI — the real handler IS the smoke test), collapsed 3 PRs to 2, inlined workspace helpers, fixed broken Dockerfile approach (`npx playwright@1.58.2 install` vs broken COPY-from-deps), fixed JWT TTL (3600s not 600s — 10min expires mid-50min audit), fixed `process.exit(1)` (kills worker — use best-effort teardown), fixed RLS policy (hardcode UUID, not subquery on auth.users), fixed Playwright layer cache ordering (BEFORE npm ci), fixed bot-signin export shape (signIn returns Session; separate writeStorageState), deferred I7 ADR until Phase 0 proves orphans exist.

## User-Brand Impact

*Carried from brainstorm Phase 0.1.*

**If this lands broken, the user experiences:** monthly UX audit silently stops — founder loses visibility into UI quality decay for 1-2 cycles before noticing missing findings artifact.

**If this leaks, the user's data is exposed via:** storageState JWT for `ux-audit-bot@jikigai.com` lingering in `/tmp` of the Hetzner container after a silent teardown failure; adjacent cron handlers sharing the same UID read the token and can make authenticated API calls until JWT expiry.

**Brand-survival threshold:** single-user incident (single founder-tenant data flow; shapes precedent for all future authenticated cron-Playwright handlers).

## Research Reconciliation — Spec vs. Codebase

| Spec Claim | Codebase Reality | Plan Response |
|------------|-----------------|---------------|
| `@anthropic-ai/claude-code@2.1.79` (Dockerfile L45) is canonical | `package.json:25` pins `2.1.142`; Dockerfile is global-install bootstrap. I4 module-load uses `createRequire`. | No version bump needed. |
| `.mcp.json` just-works from cloned repo | `.mcp.json` IS cloned unaltered, BUT `--user-data-dir=/home/jean/.cache/playwright-mcp-profile` (operator home) doesn't exist in container. | Handler writes per-fire `.mcp.json` overlay. |
| Dual-key concurrency needed | `cron-platform` already enforces limit=1 across ALL cron-* handlers. | Single key; defer dual-key until non-cron consumer. |
| `@playwright/test` version `^1.58.2` | Confirmed at `apps/web-platform/package.json:54`. | Pin Chromium bake to `1.58.2`. |
| Next Supabase migration is 071 | Latest is `070_action_sends_realtime_publication.sql`. | Use `071_ux_audit_artifacts_bucket.sql`. |
| Inngest functions registered in route.ts | Confirmed — flat import + `functions: [...]` array at L46-64. 15 entries. | Add `cronUxAudit` in PR-2. |
| `bot-fixture.ts` seed/reset exportable | `async function seed()` at L195, `async function reset()` at L228. Just needs `export` keyword. | 2-line change per function. |
| `bot-signin.ts` runs at module-eval time | **Wrong** — `signIn()` is already a named async function at L66, returns `Session`. File-writing lives in `main()` at L96. `if (import.meta.main)` guard at L126. | Export `signIn()` as-is + new `writeStorageState(session, path)`. |

## Implementation Phases

### PR-1: Substrate + Bot-Fixture Exports + Migration

**Goal:** Playwright runs in the container; bot-fixture/signin callable from handler; findings bucket exists.

#### Phase 0: I3 Verification Gate

Before merging PR-1, verify Chromium process-group reaping:

1. Build Docker image with the Playwright layer (Phase 1 below).
2. Inside the container, spawn `claude-code --print` with Playwright MCP active.
3. Send an AbortSignal after 10s.
4. Run `ps -ef --forest` and confirm zero orphan `chrome --type=zygote` / `chrome --type=renderer` after the 5s SIGKILL window.
5. **If orphans found:** implement a `pkill` reaper in the handler and add ADR-033 I7 amendment. **If clean:** note "I7 not needed" in the PR body; skip I7 amendment entirely.

#### Phase 1: Dockerfile — Playwright Browser Deps

Edit `apps/web-platform/Dockerfile` runner stage. Place the Playwright layer **BEFORE** `npm ci --omit=dev` (L77) so the ~500MB browser layer is cached independently of npm dependency changes:

```dockerfile
# Playwright Chromium system deps + browser binary (TR9 PR-11).
# Baked at image-build time — bwrap sandbox blocks apt at handler runtime.
# Version pinned to apps/web-platform/package.json @playwright/test devDep.
# The @playwright/test package itself is a devDep (omitted from runner's
# npm ci --omit=dev); only the browser binary + system libs persist.
RUN npx playwright@1.58.2 install --with-deps chromium
```

Insert after the existing apt-get block (L57-59), before `WORKDIR /app` (L61).

**Verification:** `docker build --target runner -t test-pw . && docker run --rm test-pw npx playwright@1.58.2 --version`

#### Phase 2: Add `export` to bot-fixture + bot-signin

Edit `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts`:
- L195: `async function seed()` → `export async function seed()`
- L228: `async function reset()` → `export async function reset()`
- CLI entry (`process.argv[2]` at L261) unchanged — backward compat.

Edit `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts`:
- Export existing `signIn()` at L66 (already returns `Session`, no refactor needed).
- Extract file-writing from `main()` (L96-L123) into a new exported function: `export function writeStorageState(session: Session, outPath: string, supabaseUrl: string, siteUrl: string)`.
- `if (import.meta.main)` guard unchanged.

#### Phase 3: Supabase Artifact Bucket Migration

New file: `apps/web-platform/supabase/migrations/071_ux_audit_artifacts_bucket.sql`

```sql
-- Look up the bot user's UUID at migration time to avoid runtime subquery
-- on auth.users (which RLS policies on storage.objects cannot reliably access).
DO $$
DECLARE
  bot_id uuid;
BEGIN
  SELECT id INTO bot_id FROM auth.users WHERE email = 'ux-audit-bot@jikigai.com';
  IF bot_id IS NULL THEN
    RAISE EXCEPTION 'ux-audit-bot@jikigai.com not found in auth.users — run bot-fixture.ts seed first';
  END IF;

  INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  VALUES (
    'ux-audit-artifacts',
    'ux-audit-artifacts',
    false,
    10485760,
    ARRAY['image/png', 'application/json']
  );

  EXECUTE format(
    'CREATE POLICY "ux-audit-bot tenant read/write"
      ON storage.objects FOR ALL
      USING (bucket_id = ''ux-audit-artifacts'' AND auth.uid() = %L)
      WITH CHECK (bucket_id = ''ux-audit-artifacts'' AND auth.uid() = %L)',
    bot_id, bot_id
  );
END $$;
```

Down migration: `071_ux_audit_artifacts_bucket.down.sql` — `DROP POLICY` + `DELETE FROM storage.buckets`.

#### Phase 4: ADR-033 I4 Amendment + Sentry Monitor

Edit `ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md`:

Add `[Refined 2026-MM-DD post TR9 PR-11]`: I4 binary pin surface now includes Chromium, pinned **transitively** via `@playwright/test` devDep at `docker build` time (not at handler runtime — the runner stage omits devDeps). The Chromium revision is frozen in the image; drift between image-baked Chromium and any future `@playwright/test` bump is caught by the existing lockfile-sync CI gate.

**I7:** Deferred — added only if Phase 0 verification finds orphan Chromium processes.

Add Sentry monitor to `apps/web-platform/infra/sentry/cron-monitors.tf`:

```hcl
resource "sentry_cron_monitor" "scheduled_ux_audit" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-ux-audit"
  schedule                = { crontab = "0 9 1 * *" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 55
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

---

### PR-2: cron-ux-audit + GHA Delete (Atomic)

**Goal:** The handler itself + delete the source workflow in the same commit.

#### Phase 5: cron-ux-audit.ts Handler

New file: `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`

Structure mirrors `cron-legal-audit.ts`:
- Header comment citing TR9 PR-11, ADR-033 invariants, shape diff vs cron-legal-audit.
- Constants: `SENTRY_MONITOR_SLUG = "scheduled-ux-audit"`, `MAX_TURN_DURATION_MS = 50 * 60 * 1000`, `KILL_ESCALATION_MS = 5_000`.
- `CLAUDE_CODE_FLAGS`: `--print --model claude-opus-4-7 --max-turns 60 --allowedTools Bash,Read,Write,Edit,Glob,Grep,Task,mcp__playwright__browser_navigate,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_resize,mcp__playwright__browser_close,mcp__playwright__browser_wait_for`.
- Verbatim prompt extracted from `scheduled-ux-audit.yml:170-191` (anchor-string assertions in test).

**Bot-fixture lifecycle as `step.run` steps (inline in handler, no separate file):**

1. `step.run('bot-fixture-seed', ...)` — import `seed()` from bot-fixture.ts.
2. `step.run('bot-signin', ...)` — import `signIn()` + `writeStorageState()` from bot-signin.ts. Write to `mkdtemp('/tmp/ux-audit-')` with `chmod(0o700)` on dir, `chmod(0o600)` on file. Use **default Supabase JWT TTL (3600s)** — NOT the brainstorm's 600s, which expires mid-50-min audit.
3. `step.run('claude-eval', ...)` — spawn claude-code with `UX_AUDIT_DRY_RUN=true`, `UX_AUDIT_STORAGE_STATE=<workspace>/storage-state.json` in env. Per-fire `.mcp.json` overlay with `--user-data-dir=<mkdtemp>/playwright-mcp-profile/` (NOT operator home, NOT `--isolated`).
4. `step.run('upload-findings', ...)` — upload `findings.json` + screenshots to Supabase `ux-audit-artifacts` bucket via `@supabase/supabase-js`, generate 5-min signed URLs, post URLs (not bytes) to PRIVATE monitoring issue via `gh api`.
5. `step.run('bot-fixture-reset', ...)` — import `reset()`.
6. **Cleanup in finally block** — single-attempt `rm(workspaceDir, {recursive: true, force: true})`. On failure: mirror to Sentry via `reportSilentFallback`, log warning, continue. Do NOT `process.exit(1)` — that kills the Node worker. Match `cron-legal-audit.ts:358-372` best-effort teardown pattern.

**Other handler concerns:**
- Per-fire `.mcp.json` overlay (same pattern as cron-legal-audit `.claude/settings.json` overlay at L333-340, but writing Playwright MCP entry with container-appropriate `--user-data-dir`).
- `cron-platform` concurrency key, limit=1.
- Sentry heartbeat at `scheduled-ux-audit`.
- GH installation token via `createProbeOctokit()` → `generateInstallationToken()` with 60-min TTL.
- `detached: true` spawn with SIGTERM→SIGKILL 5s escalation per ADR-033 I3.

#### Phase 6: GHA Workflow Delete + Registration

- **Delete** `.github/workflows/scheduled-ux-audit.yml` in the **same commit** as `cron-ux-audit.ts`.
- Register in `apps/web-platform/app/api/inngest/route.ts`: import `cronUxAudit`, add to `functions` array.
- Update `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` to include `cron-ux-audit.ts`.

#### Phase 7: Test

New file: `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts`
- Registration shape smoke test (import loads without throwing).
- Prompt anchor-string assertions: `MILESTONE RULE`, `Run /soleur:ux-audit`, `CAP_OPEN_ISSUES = 20`, `CAP_PER_RUN     = 5`.
- Timing constants exported (`MAX_TURN_DURATION_MS`, `KILL_ESCALATION_MS`).

## Files to Edit

| File | PR | Change |
|------|-----|--------|
| `apps/web-platform/Dockerfile` | 1 | Add `RUN npx playwright@1.58.2 install --with-deps chromium` before L61 |
| `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` | 1 | Add `export` to `seed()` L195 and `reset()` L228 |
| `plugins/soleur/skills/ux-audit/scripts/bot-signin.ts` | 1 | Export `signIn()`, extract + export `writeStorageState()` |
| `knowledge-base/engineering/architecture/decisions/ADR-033-inngest-cron-functions-invoke-claude-code-via-child-process-spawn.md` | 1 | I4 amendment (Chromium pin surface). I7 conditional on Phase 0. |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | 1 | Add `scheduled_ux_audit` monitor |
| `apps/web-platform/app/api/inngest/route.ts` | 2 | Import + register `cronUxAudit` |
| `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` | 2 | Add `cron-ux-audit.ts` to sweep |

## Files to Create

| File | PR | Purpose |
|------|-----|---------|
| `apps/web-platform/supabase/migrations/071_ux_audit_artifacts_bucket.sql` | 1 | Private Supabase bucket for findings + screenshots |
| `apps/web-platform/supabase/migrations/071_ux_audit_artifacts_bucket.down.sql` | 1 | Down migration |
| `apps/web-platform/server/inngest/functions/cron-ux-audit.ts` | 2 | UX audit Inngest handler |
| `apps/web-platform/test/server/inngest/cron-ux-audit.test.ts` | 2 | Handler test |

## Files to Delete

| File | PR | Reason |
|------|-----|--------|
| `.github/workflows/scheduled-ux-audit.yml` | 2 | TR9 I-13: GHA workflow deleted in same commit as Inngest handler |

## Acceptance Criteria

### Pre-merge (PR-1)

- [ ] AC1: `docker build --target runner` succeeds; `npx playwright@1.58.2 --version` inside the container returns `1.58.2`.
- [ ] AC2: I3 verification gate passes — zero orphan `chrome` processes after SIGKILL window.
- [ ] AC3: `bot-fixture.ts` exports `seed` and `reset`; CLI `bun bot-fixture.ts seed` unchanged.
- [ ] AC4: `bot-signin.ts` exports `signIn()` (returns Session) and `writeStorageState(session, path, ...)`.
- [ ] AC5: `supabase db push --dry-run` succeeds for migration 071. RLS policy uses hardcoded bot UUID (not auth.users subquery).
- [ ] AC6: ADR-033 `[Refined]` block present for I4 (dual binary pin, transitively at build-time).
- [ ] AC7: `terraform validate` passes on `apps/web-platform/infra/sentry/` with `scheduled_ux_audit` monitor.

### Pre-merge (PR-2)

- [ ] AC8: `cron-ux-audit.ts` loads without throwing. Registration cron = `0 9 1 * *`.
- [ ] AC9: Prompt anchor-string assertions pass: `MILESTONE RULE`, `Run /soleur:ux-audit`, `CAP_OPEN_ISSUES = 20`, `CAP_PER_RUN     = 5`.
- [ ] AC10: `UX_AUDIT_DRY_RUN` env var passed to spawn env as `'true'`.
- [ ] AC11: `.github/workflows/scheduled-ux-audit.yml` deleted in same commit as `cron-ux-audit.ts` — `git log -1 --name-status` shows both A and D.
- [ ] AC12: Per-fire `.mcp.json` overlay uses `--user-data-dir=<mkdtemp>/playwright-mcp-profile/` (NOT `--isolated`, NOT operator home).
- [ ] AC13: Workspace cleanup is single-attempt `rm` + Sentry mirror on failure (no `process.exit(1)`).
- [ ] AC14: `cron-no-byok-lease-sweep.test.ts` includes `cron-ux-audit.ts` and passes.

### Post-merge (operator)

- [ ] AC15: After PR-2 deploy, check `#3948` umbrella checkbox: `gh issue edit 3948 --body "$(gh issue view 3948 --json body --jq '.body' | sed 's/\[ \] \x60scheduled-ux-audit\x60/[x] \x60scheduled-ux-audit\x60/')"`. Automation: `gh` CLI.
- [ ] AC16: After first monthly fire, confirm Sentry `scheduled-ux-audit` check-in received. Automation: `gh api /api/v0/organizations/{org}/monitors/ --jq '.[] | select(.slug=="scheduled-ux-audit") | .lastCheckIn'` via `/soleur:postmerge`.

## Test Scenarios

| # | Scenario | Assertion |
|---|----------|-----------|
| T1 | UX audit handler loads | `typeof cronUxAudit === "object"` |
| T2 | Timing constants exported | `MAX_TURN_DURATION_MS === 3_000_000`, `KILL_ESCALATION_MS === 5_000` |
| T3 | Prompt anchors | 4 anchor strings present in `UX_AUDIT_PROMPT` |
| T4 | No BYOK import | `cron-no-byok-lease-sweep` passes |
| T5 | Bot-fixture export | `typeof seed === "function" && typeof reset === "function"` |
| T6 | Bot-signin export | `typeof signIn === "function" && typeof writeStorageState === "function"` |

## Domain Review

*Carried from brainstorm Phase 0.5.*

**Domains relevant:** Engineering, Product, Legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Image-bake Playwright with ADR-033 I4 amendment. I3 verification gate at Phase 0. Same-PR GHA delete in PR-2. Net-new bwrap+Chromium+Inngest stacking risk — I7 deferred until Phase 0 proves orphans exist.

### Product (CPO)

**Status:** reviewed
**Assessment:** Mirror permanent-dry-run. Calibration unlock is separate issue #4465. Supabase storage for findings. Monthly cadence stays.

### Legal (CLO)

**Status:** reviewed
**Assessment:** StorageState hardening: mkdtemp 0o700, file 0o600, default 3600s JWT TTL (covers 50-min audit window), best-effort teardown with Sentry mirror. Screenshots to Supabase private bucket + 5min signed URLs. Public GH + user-images rejected.

### Product/UX Gate

**Tier:** none
No user-facing UI changes — internal CI substrate migration.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor check-in at handler exit
  cadence: monthly (1st of month, 09:00 UTC)
  alert_target: Sentry issue -> ops email via alert rule
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf

error_reporting:
  destination: Sentry (via reportSilentFallback + cron-monitor miss)
  fail_loud: Sentry error on spawn failure; best-effort teardown mirrors cleanup failures to Sentry

failure_modes:
  - mode: Playwright Chromium crash or OOM
    detection: Sentry cron-monitor miss (no check-in within 55 min)
    alert_route: Sentry issue -> ops email
  - mode: Bot-fixture race (concurrency key mis-wired)
    detection: Supabase 409 / duplicate key error -> Sentry error
    alert_route: Sentry error event
  - mode: StorageState JWT leak (workspace cleanup fails)
    detection: Sentry error via reportSilentFallback; stale /tmp/ux-audit-* visible in next fire's warning log
    alert_route: Sentry error event
  - mode: Supabase upload failure (bucket RLS / network)
    detection: handler try/catch -> Sentry error
    alert_route: Sentry error event

logs:
  where: Hetzner systemd journal (docker container stdout)
  retention: 30 days (Hetzner default) + Sentry breadcrumbs 90 days

discoverability_test:
  command: |
    curl -s https://<host>/api/inngest | jq '[.functions[] | select(.name | test("ux-audit"))] | length'
  expected_output: "1"
```

## Open Code-Review Overlap

None — 0 open code-review issues touch any planned file.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|------|----------|------------|
| Playwright adds ~500MB to Docker image; deploy pull slows | Low | Pull cost paid once per deploy. Monitor deploy time post-PR-1. |
| Chromium grandchild process groups orphan after SIGKILL | Medium | I3 verification gate (Phase 0) before PR-1 merge. I7 reaper only if orphans proven. |
| Bot-fixture seed/reset touching prd Supabase during migration window | Low | `cron-platform` serializes all cron-* handlers; GHA delete is atomic with PR-2. |
| Supabase migration 071 conflicts with concurrent PR | Low | Standard numbering; resolve at merge time. |
| `.mcp.json` overlay Playwright version drifts from image-baked Chromium | Medium | Both derive from `@playwright/test` `1.58.2`. Lockfile-sync CI catches drift. |
| JWT TTL (3600s default) outlasts handler MAX_TURN_DURATION_MS (50min) by 10min | Low | Acceptable margin — JWT expires naturally; workspace `rm -rf` is the primary control. |

## Sharp Edges

- Do NOT re-number ADR-033 during the I4 amendment — three files at slot 033 is a pre-existing collision. Use `[Refined YYYY-MM-DD]` inline blocks.
- Playwright layer in Dockerfile MUST come **BEFORE** `npm ci --omit=dev` (L77) so the ~500MB browser layer is cached independently of npm dependency changes.
- `bot-fixture.ts` and `bot-signin.ts` live in `plugins/soleur/skills/ux-audit/scripts/` — vendored into Docker image at `/opt/soleur/plugin` (Dockerfile L105). Handler imports from the vendored path. Verify `getPluginPath()` resolves for the new exports.
- Per-fire `.mcp.json` overlay must NOT use `--isolated` flag — kills cookies on every browser respawn. Use per-handler `--user-data-dir` subdirs.
- GHA delete + Inngest handler MUST be same `git commit` (AC11). Otherwise both substrates fire simultaneously.
- `bunfig.toml` `minimumReleaseAge=259200` (3-day) may block recent `@playwright/mcp` versions — check `npm view @playwright/mcp time --json` before pinning.
- Workspace cleanup: single-attempt `rm` + Sentry mirror per `cron-legal-audit.ts:358-372`. No `process.exit(1)` — that kills the entire Node worker, not just the handler.
- Supabase RLS policy uses bot UUID hardcoded at migration time (via `DO $$` block). Subquery on `auth.users` inside RLS policies on `storage.objects` is unreliable.
- The `@playwright/test` devDep is NOT in the runner's `node_modules` (omitted by `npm ci --omit=dev`). The baked Chromium binary persists independently. ADR-033 I4 amendment must clarify this is build-time transitive pinning.
