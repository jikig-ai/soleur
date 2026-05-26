---
title: "refactor: extract shared cron-substrate helpers into _cron-shared.ts + _cron-claude-eval-substrate.ts"
type: refactor
date: 2026-05-26
lane: single-domain
closes: "#4472"
refs: "#3948"
brand_survival_threshold: none
semver: patch
---

# Extract shared cron-substrate helpers

Mechanical extraction of duplicated helpers across 14 cron-\*.ts Inngest handlers into two shared modules. No behavior change.

## Enhancement Summary

**Deepened on:** 2026-05-26
**Sections enhanced:** Research Insights, Implementation Phases, Risks
**Research agents used:** repo-research-analyst, learnings-researcher, verify-the-negative

### Key Improvements

1. Precise symbol-count verification: all 14 cron-\*.ts files confirmed to have Sentry regexes (14/14), HandlerArgs (14/14), REPO_OWNER (9/14), SpawnResult (9/14), resolveClaudeBin (9/14).
2. Verified glob exclusion claim: `_cron-shared.ts` does NOT match the `{cron,oneshot}-*.ts` glob in the byok-lease-sweep test.
3. Confirmed 3 new pure-TS handlers (oauth-probe, stale-deferred-scope-outs, github-app-drift-guard) share ONLY Sentry regexes + inline heartbeat (no mintInstallationToken, buildAuthenticatedCloneUrl, or redactToken) -- import surface is smaller than strategy-review/compound-promote.
4. Learning `2026-05-25-tr9-pr7-roadmap-review-claude-code-spawn-pattern-reuse.md` directly confirms the duplication pattern and enumerates the per-helper reuse table.

## Overview

The TR9 migration (umbrella #3948) ported 10+ GHA cron workflows to Inngest handlers. Each handler was ported independently (PR-1 through PR-11), copy-pasting the same substrate helpers. Now that all handlers are on main, the duplication is pure tech debt:

- **9 claude-eval handlers** (cron-daily-triage, cron-roadmap-review, cron-competitive-analysis, cron-bug-fixer, cron-follow-through-monitor, cron-agent-native-audit, cron-legal-audit, cron-community-monitor, cron-ux-audit) share: `resolveClaudeBin`, `buildSpawnEnv` (signature varies), `buildAuthenticatedCloneUrl`, `redactToken`, `mintInstallationToken`, `spawnSimple`, `setupEphemeralWorkspace`, `teardownEphemeralWorkspace`, `spawnClaudeEval`, `postSentryHeartbeat`, `SpawnResult` interface, `HandlerArgs` interface, Sentry validator regexes, `KILL_ESCALATION_MS` constant.

- **5 pure-TS handlers** (cron-strategy-review, cron-compound-promote, cron-oauth-probe, cron-stale-deferred-scope-outs, cron-github-app-drift-guard) share with the above: `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `postSentryHeartbeat`, Sentry regexes, `REPO_OWNER`/`REPO_NAME` constants.

[Plan-review P1 fix: the original plan enumerated 10 handlers; grepping for SENTRY_DOMAIN_RE across all cron-*.ts surfaced 4 additional handlers (cron-ux-audit, cron-oauth-probe, cron-stale-deferred-scope-outs, cron-github-app-drift-guard) that duplicate the same helpers. All 14 are now in scope.]

**Two-tier extraction:**

1. `_cron-shared.ts` -- helpers common to ALL cron handlers (claude-eval + pure-TS): `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `postSentryHeartbeat`, Sentry regexes, `REPO_OWNER`/`REPO_NAME`, `HandlerArgs` interface.

2. `_cron-claude-eval-substrate.ts` -- helpers specific to the 9 claude-eval handlers (imports from `_cron-shared.ts`): `resolveClaudeBin`, `spawnSimple`, `setupEphemeralWorkspace`, `teardownEphemeralWorkspace`, `spawnClaudeEval`, `SpawnResult` interface, `KILL_ESCALATION_MS`. Does NOT re-export from `_cron-shared.ts` -- handlers import from both files explicitly for clear dependency direction (plan-review P2 fix).

**Estimated saving:** ~1400 LoC across 14 files.

**Side tasks in the same PR:**

- Delete `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` (missed deletion from PR #4461; the Inngest handler `oneshot-gdpr-gate-50d-eval.ts` already exists on main).
- Tick the community-monitor and gdpr-gate checkboxes on umbrella #3948 (both already shipped via PR #4468 and #4461 respectively).

## User-Brand Impact

- **If this lands broken, the user experiences:** zero impact -- extraction is import-path-only; all 14 cron handlers continue to function identically.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A -- no new data surfaces or credential handling introduced.
- **Brand-survival threshold:** `none`

threshold: none, reason: pure refactor of internal import paths; no new user-facing surface, no credential handling change, no schema change.

## Observability

```yaml
liveness_signal:
  what: "Existing Sentry cron monitors for all 14 handlers (scheduled-daily-triage, scheduled-follow-through, etc.)"
  cadence: "per-handler cron schedule (daily/weekly)"
  alert_target: "Sentry issue → operator email"
  configured_in: "apps/web-platform/infra/sentry/cron-monitors.tf"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN"
  fail_loud: "reportSilentFallback emits Sentry event; postSentryHeartbeat sends status=error check-in"

failure_modes:
  - mode: "Import path broken after extraction → handler throws at registration"
    detection: "Inngest SDK POST /api/inngest returns 500; Sentry 'missed' alert fires within 2x cron period"
    alert_route: "Sentry cron monitor missed alert → operator email"
  - mode: "Signature mismatch after extraction → runtime TypeError in step.run"
    detection: "Sentry captureException; postSentryHeartbeat status=error"
    alert_route: "Sentry issue → operator email"

logs:
  where: "journalctl -u webapp.service on Hetzner VM"
  retention: "systemd default (journal rotation)"

discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts --reporter=verbose 2>&1 | tail -5"
  expected_output: "Tests passed (all cron-*.ts files discovered, no byok-lease violations)"
```

## Research Insights

### Duplication Inventory

Per-handler helper line counts (claude-eval cohort, representative sample):

| Handler | Shared helpers LoC (approx.) |
|---------|-----|
| cron-daily-triage | ~140 (resolveClaudeBin + buildSpawnEnv + Sentry regexes + inline heartbeat in handler) |
| cron-roadmap-review | ~200 (full set: resolveClaudeBin, buildSpawnEnv, buildAuthenticatedCloneUrl, redactToken, mintInstallationToken, spawnSimple, setupEphemeralWorkspace, teardownEphemeralWorkspace, spawnClaudeEval, postSentryHeartbeat) |
| cron-community-monitor | ~200 (same full set; buildSpawnEnv is wider -- adds 7 community-platform env vars) |
| cron-competitive-analysis | ~200 (same full set) |
| cron-bug-fixer | ~200 (same full set; spawnClaudeEval has minor additions) |
| cron-legal-audit | ~200 (same full set) |
| cron-agent-native-audit | ~200 (same full set) |
| cron-follow-through-monitor | ~100 (resolveClaudeBin + buildSpawnEnv + Sentry regexes + inline heartbeat -- no ephemeral workspace) |

Claude-eval cohort (additional):

| Handler | Shared helpers LoC (approx.) |
|---------|-----|
| cron-ux-audit | ~200 (full set: resolveClaudeBin, buildSpawnEnv, buildAuthenticatedCloneUrl, redactToken, mintInstallationToken, spawnSimple, setupEphemeralWorkspace, teardownEphemeralWorkspace, spawnClaudeEval, postSentryHeartbeat) |

Pure-TS cohort:

| Handler | Shared helpers LoC (approx.) |
|---------|-----|
| cron-strategy-review | ~120 (mintInstallationToken, buildAuthenticatedCloneUrl, redactToken, setupEphemeralWorkspace, teardownEphemeralWorkspace, postSentryHeartbeat, Sentry regexes) |
| cron-compound-promote | ~100 (mintInstallationToken, buildAuthenticatedCloneUrl, redactToken, teardownEphemeralWorkspace, postSentryHeartbeat, Sentry regexes) |
| cron-oauth-probe | ~60 (Sentry regexes, postSentryHeartbeat pattern) |
| cron-stale-deferred-scope-outs | ~60 (Sentry regexes, postSentryHeartbeat pattern) |
| cron-github-app-drift-guard | ~60 (Sentry regexes, postSentryHeartbeat pattern) |

### Signature Variations

Key variations that the shared module must accommodate:

1. **`buildSpawnEnv`**: Two signatures exist:
   - `buildSpawnEnv(): NodeJS.ProcessEnv` (cron-daily-triage, cron-follow-through-monitor) -- uses `process.env.GH_TOKEN ?? process.env.GITHUB_TOKEN`
   - `buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv` (6 other claude-eval handlers) -- uses `GH_TOKEN: installationToken`
   - Some handlers add extra env vars (cron-community-monitor adds 7 platform vars)
   - **Decision:** `buildSpawnEnv` stays per-handler because the env-var allowlist is security-critical and differs per handler. The substrate does NOT extract `buildSpawnEnv`.

2. **`setupEphemeralWorkspace`**: Two shapes:
   - Claude-eval shape (6 handlers): creates tmpdir, clones, symlinks plugin, writes .claude/settings.json, sentinel-checks plugin manifest. Returns `{ ephemeralRoot, spawnCwd }`.
   - Pure-TS shape (strategy-review, compound-promote): creates tmpdir, clones, sentinel-checks domain-specific directories. Returns `{ ephemeralRoot, repoRoot }`. No plugin symlink, no settings overlay.
   - **Decision:** extract the claude-eval shape into `_cron-claude-eval-substrate.ts` parameterized by `cronName: string` (for tmpdir prefix). Pure-TS handlers keep their own `setupEphemeralWorkspace` (too different to share).

3. **`spawnClaudeEval`**: Identical across 6 handlers except for:
   - `CLAUDE_CODE_FLAGS` array (per-handler)
   - Prompt string (per-handler)
   - `MAX_TURN_DURATION_MS` (per-handler)
   - `fn:` string in logger/reportSilentFallback calls
   - **Decision:** parameterize with `{ flags, prompt, maxTurnDurationMs, cronName }`.

4. **`postSentryHeartbeat`**: Identical across all 14 handlers except for:
   - `SENTRY_MONITOR_SLUG` (per-handler)
   - `fn:` string in log messages
   - Some handlers use `SENTRY_HEARTBEAT_TIMEOUT_MS` constant; others use inline `10_000`.
   - **Decision:** parameterize with `{ sentryMonitorSlug, cronName }`.

5. **`mintInstallationToken`**: Identical across 8 handlers except for `TOKEN_MIN_LIFETIME_MS` value.
   - **Decision:** parameterize with `{ tokenMinLifetimeMs }`.

6. **`teardownEphemeralWorkspace`**: Identical except for `feature:` and `fn:` strings in reportSilentFallback.
   - **Decision:** parameterize with `{ cronName }`.

7. **`resolveClaudeBin`**: Identical across all 8 claude-eval handlers. No parameters needed.

8. **`spawnSimple`**: Identical across 6 handlers. No parameters needed.

9. **`redactToken`**, **`buildAuthenticatedCloneUrl`**: Identical across all handlers that use them. No parameters needed.

10. **`SENTRY_DOMAIN_RE`**, **`SENTRY_PROJECT_RE`**, **`SENTRY_PUBLIC_KEY_RE`**: Identical across all 14 handlers. No parameters needed.

11. **`REPO_OWNER`**, **`REPO_NAME`**: Identical across 8 handlers (all except daily-triage and follow-through-monitor which don't use them).

### Deepen-pass: Precise Symbol Counts (verified 2026-05-26)

| Symbol | Definition count | Files |
|--------|-----------------|-------|
| `SENTRY_DOMAIN_RE` | 14 | all cron-\*.ts |
| `SENTRY_PROJECT_RE` | 14 | all cron-\*.ts |
| `SENTRY_PUBLIC_KEY_RE` | 14 | all cron-\*.ts |
| `HandlerArgs` interface | 14 | all cron-\*.ts |
| `resolveClaudeBin` | 9 | 9 claude-eval handlers |
| `SpawnResult` interface | 9 | 9 claude-eval handlers |
| `REPO_OWNER` | 9 | 9 handlers (all except daily-triage, follow-through-monitor, oauth-probe, stale-deferred-scope-outs, github-app-drift-guard) |
| `mintInstallationToken` | 9 | 9 handlers (same set as REPO_OWNER) |
| `buildAuthenticatedCloneUrl` | 9 | 9 handlers (same set) |
| `redactToken` | 9 | 9 handlers (same set) |
| `postSentryHeartbeat` (named fn) | 9 | 6 claude-eval + 2 pure-TS + cron-ux-audit; 5 others have inline heartbeat |
| `spawnSimple` | 7 | 7 claude-eval handlers with ephemeral workspace |
| `setupEphemeralWorkspace` | 9 | 7 claude-eval + 2 pure-TS (different shapes) |
| `teardownEphemeralWorkspace` | 9 | 7 claude-eval + 2 pure-TS |
| `spawnClaudeEval` | 7 | 7 claude-eval handlers with ephemeral workspace |
| `KILL_ESCALATION_MS` | 9 (def + use) | 9 claude-eval handlers |

### Deepen-pass: Three-Tier Handler Classification

After verification, the 14 handlers break into 3 tiers for extraction purposes:

**Tier A -- Full claude-eval with ephemeral workspace (7 handlers):**
cron-roadmap-review, cron-competitive-analysis, cron-bug-fixer, cron-agent-native-audit, cron-legal-audit, cron-community-monitor, cron-ux-audit.
Import from BOTH `_cron-shared.ts` and `_cron-claude-eval-substrate.ts`.

**Tier B -- Claude-eval without ephemeral workspace (2 handlers):**
cron-daily-triage, cron-follow-through-monitor.
Import `resolveClaudeBin`, `SpawnResult`, `KILL_ESCALATION_MS` from `_cron-claude-eval-substrate.ts`. Import Sentry regexes, `HandlerArgs`, `postSentryHeartbeat` from `_cron-shared.ts`. Refactor inline heartbeat to shared function.

**Tier C -- Pure-TS with full shared set (2 handlers):**
cron-strategy-review, cron-compound-promote.
Import `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `postSentryHeartbeat`, Sentry regexes, `REPO_OWNER`, `REPO_NAME`, `HandlerArgs` from `_cron-shared.ts`.

**Tier D -- Pure-TS with Sentry-only shared set (3 handlers):**
cron-oauth-probe, cron-stale-deferred-scope-outs, cron-github-app-drift-guard.
Import `postSentryHeartbeat`, Sentry regexes, `HandlerArgs` from `_cron-shared.ts`. Do NOT use `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`, `REPO_OWNER`, `REPO_NAME` (these handlers have their own auth patterns or no clone).

### Handlers NOT using ephemeral workspace

Two claude-eval handlers do NOT use the ephemeral workspace pattern:
- **cron-daily-triage** -- spawns claude directly (no repo clone needed; uses gh CLI only).
- **cron-follow-through-monitor** -- spawns claude directly (no repo clone needed; uses gh CLI + curl/dig only).

These two use only: `resolveClaudeBin`, `buildSpawnEnv` (local variant), Sentry regexes, and inline heartbeat code. They will import from `_cron-shared.ts` (Sentry regexes, `SpawnResult` type, `HandlerArgs` type) and `_cron-claude-eval-substrate.ts` (resolveClaudeBin).

### Existing Test Coverage

- `cron-no-byok-lease-sweep.test.ts` -- globs `server/inngest/functions/{cron,oneshot}-*.ts` and asserts no BYOK imports. Will auto-discover the new `_cron-*.ts` files since they don't match the `{cron,oneshot}-*.ts` glob pattern (prefixed with `_`).
- `cron-strategy-review-graymatter.test.ts` -- tests gray-matter YAML 1.1 coercion. Not affected by this refactor.

### gray-matter trap test (AC10)

The compound-promote handler uses `gray-matter` for frontmatter parsing. The substrate modules (`_cron-shared.ts`, `_cron-claude-eval-substrate.ts`) do NOT read frontmatter -- gray-matter is only used in per-handler business logic. No gray-matter trap test is needed for the substrate files.

## Open Code-Review Overlap

None. No open code-review issues touch the files this plan intends to modify.

## Implementation Phases

### Phase 0: Preconditions

- [x] Verify all 14 cron-\*.ts files exist and compile: `cd apps/web-platform && npx tsc --noEmit`
- [x] Run existing test suite: `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts`

### Phase 1: Create `_cron-shared.ts`

Create `apps/web-platform/server/inngest/functions/_cron-shared.ts` exporting:

- `REPO_OWNER` constant (`"jikig-ai"`)
- `REPO_NAME` constant (`"soleur"`)
- `SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE` regexes
- `HandlerArgs` interface (the `{ step, logger }` shape used by all handlers)
- `redactToken(s: string, token: string): string`
- `buildAuthenticatedCloneUrl(token: string): string` (uses REPO_OWNER/REPO_NAME)
- `mintInstallationToken(opts: { tokenMinLifetimeMs: number }): Promise<string>`
- `postSentryHeartbeat(args: { ok: boolean; sentryMonitorSlug: string; cronName: string; logger: HandlerArgs["logger"] }): Promise<void>`

Imports from existing project modules: `createProbeOctokit`, `generateInstallationToken`, `reportSilentFallback`.

### Phase 2: Create `_cron-claude-eval-substrate.ts`

Create `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` importing from `_cron-shared.ts` and exporting:

- `SpawnResult` interface
- `KILL_ESCALATION_MS` constant (5000)
- `resolveClaudeBin(): string`
- `spawnSimple(cmd, args, opts): Promise<{ exitCode, signal }>`
- `setupEphemeralWorkspace(args: { installationToken: string; cronName: string }): Promise<{ ephemeralRoot: string; spawnCwd: string }>`
- `teardownEphemeralWorkspace(ephemeralRoot: string | null, cronName: string): Promise<void>`
- `spawnClaudeEval(args: { spawnCwd: string; installationToken: string; flags: string[]; prompt: string; maxTurnDurationMs: number; cronName: string; buildSpawnEnv: (token: string) => NodeJS.ProcessEnv; logger: HandlerArgs["logger"] }): Promise<SpawnResult>`

Does NOT re-export from `_cron-shared.ts` (plan-review P2: barrel re-exports create two valid import paths per symbol, adding maintenance cost for zero semantic value). Claude-eval handlers import from both `_cron-shared.ts` and `_cron-claude-eval-substrate.ts` explicitly.

### Phase 3: Migrate 7 claude-eval handlers (ephemeral-workspace cohort)

For each of: cron-roadmap-review, cron-competitive-analysis, cron-bug-fixer, cron-agent-native-audit, cron-legal-audit, cron-community-monitor, cron-ux-audit:

1. Replace local helper definitions with imports from `_cron-claude-eval-substrate.ts`.
2. Keep per-handler: `SENTRY_MONITOR_SLUG`, `CLAUDE_CODE_FLAGS`, prompt string, `MAX_TURN_DURATION_MS`, `TOKEN_MIN_LIFETIME_MS`, `buildSpawnEnv`, `DEFAULT_CLAUDE_SETTINGS`, handler-specific business logic.
3. Update `spawnClaudeEval` calls to pass the parameterized form.
4. Update `postSentryHeartbeat` calls to pass `sentryMonitorSlug` and `cronName`.
5. Update `mintInstallationToken` calls to pass `tokenMinLifetimeMs`.
6. Update `setupEphemeralWorkspace` / `teardownEphemeralWorkspace` calls to pass `cronName`.

### Phase 4: Migrate 2 no-workspace claude-eval handlers

For cron-daily-triage and cron-follow-through-monitor:

1. Import `resolveClaudeBin`, `SpawnResult`, `KILL_ESCALATION_MS` from `_cron-claude-eval-substrate.ts`.
2. Import `SENTRY_DOMAIN_RE`, `SENTRY_PROJECT_RE`, `SENTRY_PUBLIC_KEY_RE`, `HandlerArgs`, `postSentryHeartbeat` from `_cron-shared.ts`.
3. Delete local definitions of the imported symbols.
4. Refactor inline Sentry heartbeat code to use the shared `postSentryHeartbeat` function (plan-review P3 fix: the inline code is identical modulo `fn:` string and `SENTRY_MONITOR_SLUG`, both already parameters on the shared function).
5. Keep per-handler: `buildSpawnEnv`, spawn logic specific to the handler.

### Phase 5: Migrate 5 pure-TS handlers

For cron-strategy-review, cron-compound-promote, cron-oauth-probe, cron-stale-deferred-scope-outs, cron-github-app-drift-guard:

1. Import from `_cron-shared.ts`: `postSentryHeartbeat`, Sentry regexes, `REPO_OWNER`, `REPO_NAME`, `HandlerArgs`. For handlers that also use them: `mintInstallationToken`, `buildAuthenticatedCloneUrl`, `redactToken`.
2. Delete local definitions of the imported symbols.
3. Keep per-handler: `setupEphemeralWorkspace` (different shape where present), `teardownEphemeralWorkspace`, all business logic, handler-specific types.

### Phase 6: Delete stale GHA workflow

Delete `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml`. This was supposed to be deleted in PR #4461 (gdpr-gate one-shot conversion) but was missed. The Inngest handler `oneshot-gdpr-gate-50d-eval.ts` already exists on main.

### Phase 7: Guard test

Create `apps/web-platform/test/server/cron-substrate-imports.test.ts`:

A vitest test that asserts every `cron-*.ts` file (except `_cron-*.ts` substrate files) imports from `_cron-shared.ts` and does NOT locally redefine the extracted symbols.

**Test shape:**
1. Glob `server/inngest/functions/cron-*.ts` (excludes `_cron-*.ts` by glob pattern).
2. For each file, read source and strip comments.
3. Assert: file contains `from "./_cron-shared"` OR `from "./_cron-claude-eval-substrate"` (at least one shared import).
4. Assert: file does NOT contain local `function redactToken`, `function buildAuthenticatedCloneUrl`, `const SENTRY_DOMAIN_RE`, `const SENTRY_PROJECT_RE`, `const SENTRY_PUBLIC_KEY_RE`, `const REPO_OWNER = "jikig-ai"`, `const REPO_NAME = "soleur"` (the symbols extracted to `_cron-shared.ts`).
5. For claude-eval handlers (those importing `_cron-claude-eval-substrate`): assert file does NOT contain local `function resolveClaudeBin`, `function spawnSimple`.

**Fixture proof tests:** Include positive and negative fixture proofs (synthetic source strings) to ensure the regexes are correct.

### Phase 8: Tick umbrella checkboxes

Update umbrella issue #3948 body to tick:
- [x] community-monitor (shipped via PR #4468)
- [x] gdpr-gate (shipped via PR #4461)

Via Octokit `PATCH /repos/{owner}/{repo}/issues/{issue_number}` to update the body with the checkboxes ticked.

### Phase 9: Verify

- [x] `cd apps/web-platform && npx tsc --noEmit` passes
- [x] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-no-byok-lease-sweep.test.ts` passes
- [x] `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/cron-substrate-imports.test.ts` passes
- [x] `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` is deleted
- [x] LoC delta is net negative (actual: -2784 lines)

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `_cron-shared.ts` exports: `REPO_OWNER`, `REPO_NAME`, 3 Sentry regexes, `redactToken`, `buildAuthenticatedCloneUrl`, `mintInstallationToken`, `postSentryHeartbeat`, `HandlerArgs`.
- [x] AC2: `_cron-claude-eval-substrate.ts` exports: `resolveClaudeBin`, `spawnSimple`, `setupEphemeralWorkspace`, `teardownEphemeralWorkspace`, `spawnClaudeEval`, `SpawnResult`, `KILL_ESCALATION_MS`. Does NOT re-export from `_cron-shared.ts`.
- [x] AC3: All 14 cron-\*.ts files import from `_cron-shared.ts` or `_cron-claude-eval-substrate.ts` (verified by guard test).
- [x] AC4: No cron-\*.ts file locally redefines any extracted symbol (verified by guard test).
- [x] AC5: `npx tsc --noEmit` passes with zero errors.
- [x] AC6: `vitest run test/server/cron-no-byok-lease-sweep.test.ts` passes (existing guard).
- [x] AC7: `vitest run test/server/cron-substrate-imports.test.ts` passes (new guard).
- [x] AC8: `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml` does not exist in the tree.
- [x] AC9: Net LoC delta is negative (actual: -2784 lines).
- [x] AC10: No behavior change -- each handler's `SENTRY_MONITOR_SLUG`, `CLAUDE_CODE_FLAGS`, prompt, `MAX_TURN_DURATION_MS`, `buildSpawnEnv`, and business logic remain per-handler.
- [x] AC11: `buildSpawnEnv` is NOT extracted (security: per-handler env-var allowlist must remain explicit and auditable per handler).

- [x] AC12: Umbrella #3948 community-monitor and gdpr-gate checkboxes are ticked (Phase 8, pre-merge via `gh api`).

## Files to Create

- `apps/web-platform/server/inngest/functions/_cron-shared.ts`
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts`
- `apps/web-platform/test/server/cron-substrate-imports.test.ts`

## Files to Edit

- `apps/web-platform/server/inngest/functions/cron-daily-triage.ts`
- `apps/web-platform/server/inngest/functions/cron-roadmap-review.ts`
- `apps/web-platform/server/inngest/functions/cron-competitive-analysis.ts`
- `apps/web-platform/server/inngest/functions/cron-bug-fixer.ts`
- `apps/web-platform/server/inngest/functions/cron-follow-through-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-agent-native-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-legal-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-community-monitor.ts`
- `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`
- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`
- `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`
- `apps/web-platform/server/inngest/functions/cron-oauth-probe.ts`
- `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`
- `apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts`

## Files to Delete

- `.github/workflows/scheduled-gdpr-gate-preflight-eval-50d.yml`

## Test Scenarios

- Given a cron-*.ts file, when it defines `function redactToken` locally, then `cron-substrate-imports.test.ts` fails.
- Given a cron-*.ts file, when it imports `redactToken` from `_cron-shared.ts`, then the test passes.
- Given the substrate modules, when `tsc --noEmit` runs, then zero type errors.
- Given the refactored handlers, when the existing `cron-no-byok-lease-sweep.test.ts` runs, then all assertions still pass (glob still finds all cron-*.ts files; _cron-*.ts files are excluded by the {cron,oneshot}-*.ts glob pattern).
- Given a new cron-*.ts file added without importing from `_cron-shared.ts`, then `cron-substrate-imports.test.ts` fails.

## Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| Import path typo breaks handler registration at startup | `tsc --noEmit` in Phase 9 catches all import errors at compile time. |
| `_cron-*.ts` files accidentally matched by `cron-no-byok-lease-sweep.test.ts` glob | The glob is `{cron,oneshot}-*.ts`, which does NOT match `_cron-*.ts`. Verified by reading the test file. |
| Parameterized `spawnClaudeEval` signature change introduces subtle behavior diff | Each handler passes its existing constants unchanged; the substrate function body is a verbatim copy of the current `spawnClaudeEval` from cron-roadmap-review.ts (the canonical shape). |
| `buildSpawnEnv` extracted despite security sensitivity | Explicitly NOT extracted (AC11). Per-handler allowlist remains the only acceptable pattern. |
| Pure-TS handlers' `setupEphemeralWorkspace` has different return shape | NOT extracted for pure-TS handlers. Only the claude-eval shape (7 handlers) is extracted. |
| Tier D handlers (oauth-probe, stale-deferred-scope-outs, github-app-drift-guard) have inline heartbeat, not a named `postSentryHeartbeat` function | Phase 5 refactors them to call the shared `postSentryHeartbeat` (same pattern as Phase 4 for daily-triage/follow-through-monitor). The inline code is identical modulo the monitor slug and function name strings. |
| `_cron-shared.ts` imports `createProbeOctokit` and `generateInstallationToken` -- Tier D handlers that do NOT use `mintInstallationToken` would have an unused transitive dependency | Tree-shaking handles this at bundle time. The import is in `_cron-shared.ts`, not in the handler. Handlers that do not call `mintInstallationToken` never invoke the code path. No runtime cost. |

## Domain Review

**Domains relevant:** none

No cross-domain implications detected -- internal refactoring of duplicated TypeScript helpers.

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|-------------|
| Single shared module (`_cron-substrate.ts`) | Pure-TS and claude-eval handlers share only ~50% of helpers; a single module would force claude-eval imports on pure-TS handlers (unnecessary coupling). |
| Extract `buildSpawnEnv` into substrate | Security-critical: per-handler env-var allowlists must remain explicit and auditable. Extraction would obscure which secrets each handler can access. |
| Extract `setupEphemeralWorkspace` for pure-TS handlers too | Signatures differ meaningfully (different return types, different sentinel checks, no plugin symlink). Not worth the abstraction cost. |
| Leave duplication as-is | 14 handlers x ~100-200 LoC shared = ~1800 LoC of pure duplication. Any bug fix (e.g., resolveClaudeBin candidate path change) must be applied 9+ times. |

## Sharp Edges

- `buildSpawnEnv` is intentionally NOT extracted. Each handler's env-var allowlist is its security boundary. A shared function would obscure this.
- The `_` prefix on substrate files is a convention to signal "not a standalone Inngest function" -- the `cron-no-byok-lease-sweep.test.ts` glob relies on the `{cron,oneshot}-*.ts` pattern to exclude them.
- cron-daily-triage and cron-follow-through-monitor had inline Sentry heartbeat code. Phase 4 refactors both to use the shared `postSentryHeartbeat` for consistency (plan-review P3 fix).
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.

## Plan Review (Applied)

3-agent panel (DHH, Kieran, Code Simplicity). All findings applied:

- **P1 (Kieran, Code Simplicity):** Plan missed 4 cron handlers (cron-ux-audit, cron-oauth-probe, cron-stale-deferred-scope-outs, cron-github-app-drift-guard) that also duplicate extracted helpers. Scope widened from 10 to 14 handlers.
- **P2 (DHH, Code Simplicity):** Re-export barrel from `_cron-claude-eval-substrate.ts` creates unnecessary coupling. Dropped re-exports; handlers import from both files explicitly.
- **P3 (Kieran):** Phase 4 contradicted Sharp Edges on inline heartbeat. Resolved: both daily-triage and follow-through-monitor refactored to use shared `postSentryHeartbeat`.
- **P3b (Kieran):** Phase 8 (tick umbrella checkboxes) moved from post-merge to pre-merge (automatable via `gh api`).

## References

- Issue: #4472
- Umbrella: #3948
- Learning: `knowledge-base/project/learnings/2026-05-19-inngest-substrate-five-bug-cascade.md`
- Learning: `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md`
- Learning: `knowledge-base/project/learnings/2026-05-25-tr9-pr7-roadmap-review-claude-code-spawn-pattern-reuse.md`
- Learning: `knowledge-base/project/learnings/2026-05-26-tr9-pr11-compound-promote-pure-ts-port-pattern.md`
- ADR-033: Inngest cron migration architecture
