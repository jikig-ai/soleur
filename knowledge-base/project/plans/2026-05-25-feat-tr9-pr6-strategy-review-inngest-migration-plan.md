---
title: "TR9 PR-6 — Migrate scheduled-strategy-review to Inngest cron"
date: 2026-05-25
type: feat
status: ready-for-work
branch: feat-one-shot-inngest-strategy-review-3948
issue: 4416
umbrella: 3948
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
predecessors:
  - 3985 # PR-1 daily-triage (substrate proof-of-pattern)
  - 4062 # PR-2 follow-through (closest reference; also shell-only)
  - 4227 # PR-3 oauth-probe
  - 4303 # PR-4 drift-guard
  - 4377 # PR-5 bug-fixer (most recent; ephemeral workspace + GH App token)
---

# TR9 PR-6 — Migrate `scheduled-strategy-review` to Inngest cron

## Overview

Migrate `.github/workflows/scheduled-strategy-review.yml` (weekly `0 8 * * 1`, 5-min budget, issue-creator shell-only side-effect class, CLO bucket i — operator-only) to an Inngest cron function as the next child of umbrella #3948 (TR9 group-(c) agent-loop crons).

This is the **simplest migration** in the TR9 umbrella to date: the GHA workflow runs a pure bash script (`scripts/strategy-review-check.sh`, 164 lines — YAML frontmatter parse + date math + `gh issue create`) with no `claude-code-action` invocation. The Inngest function spawns the script directly inside `step.run` — no claude-eval, no `--allowedTools`, no SSRF surface, no auto-merge gate, no `RESEND_API_KEY`.

Closest precedent: **PR-2 #4062** (`scheduled-follow-through`) — also shell-only side-effects (although PR-2 still spawns claude for the LLM monitor agent, whereas PR-6 has zero LLM call). Secondary precedent: **PR-5 #4377** (`scheduled-bug-fixer`) — adopt its **ephemeral workspace pattern** (in-handler `git clone --depth=1` + installation-token GH_TOKEN) because the bash script must scan a **live** `knowledge-base/` tree from `main`, and the Hetzner deploy image carries no checked-out repo.

Closes #4416.

## Research Reconciliation — Umbrella body vs codebase reality

The umbrella body lists `cron_run_ledger` as a binding substrate primitive. **No such table or migration exists in the codebase** (`grep -rn 'cron_run_ledger' apps/web-platform/ supabase/migrations/` returns nothing; latest migration is `066_audit_byok_use_art17_carveout.sql`). PR-1 through PR-5 all shipped without it; the inverse-assertion sweep is **`test/server/cron-no-byok-lease-sweep.test.ts`** (which globs `cron-*.ts` and auto-extends to this file). The "jitter-guard" role is served structurally by Inngest's `{ scope: "fn", limit: 1 }` + `{ scope: "account", key: '"cron-platform"', limit: 1 }` concurrency keys plus the per-function single-cron-trigger.

| Spec/umbrella claim                                 | Codebase reality                                                                 | Plan response                                                            |
| --------------------------------------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `cron_run_ledger` table for jitter-guard            | Does NOT exist; no migration creates it                                          | Do NOT introduce it; rely on Inngest fn-concurrency=1 + cron-platform account-key (PR-1..PR-5 precedent) |
| All cron-* MUST not import `runWithByokLease`       | Enforced by `test/server/cron-no-byok-lease-sweep.test.ts` (globs `cron-*.ts`)   | New file is auto-swept by the existing glob — no test change required   |
| `actor: "platform"` event-payload invariant         | This handler emits NO events (downstream of any per-tenant workflow)             | I6 structurally satisfied; manual-trigger event from operator carries no payload |
| GHA-era Sentry monitor `scheduled-strategy-review`  | NO monitor exists (`grep scheduled_strategy_review cron-monitors.tf` → 0 hits)  | NEW resource (no continuity rename — same as PR-5 bug-fixer pattern)    |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator (Jean) does not receive weekly strategy-doc review reminders → strategy docs go stale → product/marketing/sales decisions reference outdated artifacts. No customer-facing surface; no founder-facing surface. Operator-only.

**If this leaks, the user's [data / workflow / money] is exposed via:** N/A — the function reads operator-owned `knowledge-base/{product,marketing,sales}/` markdown and creates issues in `jikig-ai/soleur`. No founder data, no user data, no payment data.

**Brand-survival threshold:** none — operator-only ops workflow, no customer-facing surface.

**Reason:** the function reads operator-owned knowledge-base markdown and writes issues in the operator's own repo. No founder/customer data touches any code path.

## Goals

1. Inngest function `cron-strategy-review` fires weekly at `0 8 * * 1` UTC and produces the same effect as the current GHA workflow (issues created/skipped/up-to-date per strategy doc's `review_cadence`).
2. GHA workflow `.github/workflows/scheduled-strategy-review.yml` DELETED in the same commit.
3. New Sentry cron monitor `scheduled_strategy_review` in `apps/web-platform/infra/sentry/cron-monitors.tf`.
4. The function spawns `bash scripts/strategy-review-check.sh` inside `step.run` against an ephemeral cloned workspace (PR-5 pattern, simplified — no plugin symlink needed).
5. Operator can manual-trigger via Inngest event `cron/strategy-review.manual-trigger` with optional `{date_override: "YYYY-MM-DD"}` payload.
6. `bun test apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` passes (auto-extends to the new file via `cron-*.ts` glob).

## Non-Goals

- Porting `strategy-review-check.sh` logic to TypeScript inline (164 lines of bash; keep the script intact, spawn it).
- Introducing `cron_run_ledger` Supabase table (not in codebase; not adopted by PR-1..PR-5).
- Email notification on failure via Resend (Sentry heartbeat + `reportSilentFallback` cover the observability surface; matches PR-2/PR-5 — Resend was decorative on the GHA side).
- Tightening the script's logic, adding new strategy-doc scopes, or fixing #-tracked bugs in the bash itself. **Scope is strictly substrate migration.**
- Adding a plugin symlink (PR-5 needs it because claude resolves plugins from cwd; PR-6 spawns no claude).

## Files to Create

- `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` — new Inngest function (~250 lines, much smaller than `cron-bug-fixer.ts`'s 1226 because no claude-eval/auto-merge-gate/Resend).

## Files to Edit

- `apps/web-platform/app/api/inngest/route.ts` — add `cronStrategyReview` import + register in `serve({ functions })` (alphabetical position between `cronOauthProbe` and `cronGithubAppDriftGuard`… actually between `cronFollowThroughMonitor` and `cronGithubAppDriftGuard` per existing alpha order).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_strategy_review` resource (no GHA-era predecessor; NEW slug per PR-5 pattern).
- `.github/workflows/scheduled-strategy-review.yml` — **DELETE** in the same commit per TR9 I-13 hygiene.
- `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-shell-only-no-claude-eval-pattern.md` — capture the simplification pattern (shell-only cron with no LLM call: drop `--allowedTools`, drop `MAX_TURN_DURATION_MS`, drop plugin symlink, drop `notify-ops-email`).

## Files to NOT edit (explicit non-scope)

- `scripts/strategy-review-check.sh` — Keep intact. The script's exit-code + stdout contract IS the function's contract; modifying it is risk for zero TR9 benefit.
- `test/server/cron-no-byok-lease-sweep.test.ts` — Auto-extends via `cron-*.ts` glob; no edit required.
- `test/server/byok-audit-writer-sweep.test.ts` — N/A (BYOK boundary; cron-*.ts never opens a BYOK lease).
- All previously-migrated `cron-*.ts` files — independent migrations per K8.

## Implementation Phases

### Phase 0 — Preflight verification

Before authoring code, confirm the following (Bash, no edits):

1. `ls apps/web-platform/server/inngest/functions/cron-bug-fixer.ts` returns the reference file (1226 lines).
2. `gh issue view 3948 --json title,state` returns `OPEN` and umbrella title.
3. `gh issue view 4416` returns the freshly-filed child issue (this PR's `Closes` target).
4. `git ls-files | grep -E "scripts/strategy-review-check.sh|.github/workflows/scheduled-strategy-review.yml"` returns BOTH files (confirms the migration source is present in the worktree).
5. `grep -rn cron_run_ledger apps/web-platform/ supabase/migrations/` returns ZERO hits (confirms reconciliation row above).
6. `grep -n "cronFollowThroughMonitor\|cronBugFixer\|cronDailyTriage" apps/web-platform/app/api/inngest/route.ts` returns the 3 existing cron registrations (confirms registry edit shape).
7. `awk '/^name:/ { print; exit }' .github/workflows/scheduled-strategy-review.yml` returns `name: Strategy Review` (confirms exact wording for note in PR body).

### Phase 1 — Author `cron-strategy-review.ts`

Adopt the **simplified** PR-5 shape — drop everything claude/plugin/auto-merge/Resend related, keep ephemeral workspace + GH App token + Sentry heartbeat:

**Structure (target ~250 lines):**

```typescript
// TR9 PR-6 (closes #4416) — Migrated from the GHA scheduled-strategy-review
// workflow (deleted in the same PR per TR9 I-13 hygiene).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — bash binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator-owned data only; never founder BYOK. Structurally
//        satisfied — no SDK call. Auto-asserted by
//        test/server/cron-no-byok-lease-sweep.test.ts via cron-*.ts glob.
//   I3 — AbortSignal aborts at MAX_RUN_DURATION_MS (10 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — bash binary resolved at /bin/bash (POSIX path; not the claude
//        node_modules dance — script needs the system shell, not a plugin
//        runtime).
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}.
//   I6 — Event payloads emitted by this handler MUST carry actor: "platform".
//        (This handler emits none.)
//
// NAME NOTE: Sentry monitor slug "scheduled-strategy-review" is NEW — the
// GHA predecessor had NO Sentry check-in. Resource added in same commit.
//
// SHELL-ONLY PATTERN — PR-6 is the first TR9 child with ZERO claude-eval.
// No --allowedTools, no MAX_TURN_DURATION_MS, no plugin symlink, no Resend
// email. The script's exit code IS the contract. See learning
// 2026-05-25-tr9-pr6-strategy-review-shell-only-no-claude-eval-pattern.md.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inngest } from "@/server/inngest/client";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import { reportSilentFallback } from "@/server/observability";

const SENTRY_MONITOR_SLUG = "scheduled-strategy-review";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;
const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

// 10 min wall-clock budget. GHA's timeout-minutes was 5; 10 doubles it for
// safety against transient `gh issue create` rate-limit retry. Past runs
// complete in <30s typically (≤20 strategy docs scanned, ≤5 issues created).
export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;
export const KILL_ESCALATION_MS = 5_000;

// Installation-token lifetime floor: 10-min spawn budget + 5-min headroom.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

interface SpawnResult {
  ok: boolean;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  abortedByTimeout: boolean;
  durationMs: number;
}

interface HandlerArgs {
  event?: { data?: { date_override?: unknown } };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: { info: (...a: unknown[]) => void; warn: (...a: unknown[]) => void; error: (...a: unknown[]) => void };
}

// ----- helpers (mint token, clone repo, spawn bash, teardown, heartbeat) -----

async function mintInstallationToken(): Promise<string> {
  const octokit = await createProbeOctokit();
  const { data: installation } = await octokit.request(
    "GET /repos/{owner}/{repo}/installation",
    { owner: REPO_OWNER, repo: REPO_NAME },
  );
  return generateInstallationToken(installation.id, {
    minRemainingMs: TOKEN_MIN_LIFETIME_MS,
  });
}

function buildAuthenticatedCloneUrl(token: string): string {
  return `https://x-access-token:${token}@github.com/${REPO_OWNER}/${REPO_NAME}.git`;
}

function redactToken(s: string, token: string): string {
  if (!token) return s;
  return s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]");
}

function buildSpawnEnv(
  installationToken: string,
  dateOverride: string | undefined,
): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    GH_TOKEN: installationToken,
    SERVER_URL: "https://github.com",
    REPO_NAME: `${REPO_OWNER}/${REPO_NAME}`,
    ...(dateOverride ? { DATE_OVERRIDE: dateOverride } : {}),
  };
}

// `git clone --depth=1` into an ephemeral workspace. No plugin symlink
// (PR-6 spawns no claude). Returns the cloned repo path.
async function setupEphemeralWorkspace(token: string): Promise<{
  ephemeralRoot: string;
  spawnCwd: string;
}> {
  const ephemeralRoot = await mkdtemp(join(tmpdir(), "soleur-cron-strategy-review-"));
  const spawnCwd = join(ephemeralRoot, "repo");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const cloneResult = await new Promise<{ exitCode: number | null }>((resolve) => {
    const child = spawn("git", ["clone", "--depth=1", cloneUrl, spawnCwd], {
      stdio: "ignore",
    });
    child.on("exit", (exitCode) => resolve({ exitCode }));
    child.on("error", () => resolve({ exitCode: -1 }));
  });
  if (cloneResult.exitCode !== 0) {
    // DO NOT include cloneUrl — contains the token.
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  // Sentinel: confirm the script exists in the clone.
  const scriptPath = join(spawnCwd, "scripts", "strategy-review-check.sh");
  if (!existsSync(scriptPath)) {
    throw new Error(`Sentinel: ${scriptPath} missing after clone`);
  }
  return { ephemeralRoot, spawnCwd };
}

async function teardownEphemeralWorkspace(ephemeralRoot: string | null): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-strategy-review",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-strategy-review", ephemeralRoot },
    });
  }
}

async function spawnStrategyReview(args: {
  spawnCwd: string;
  installationToken: string;
  dateOverride: string | undefined;
  logger: HandlerArgs["logger"];
}): Promise<SpawnResult> {
  // [PR-5-style AbortController + SIGTERM→SIGKILL escalation + stdout/stderr
  // line-streaming through redactToken to strip GH_TOKEN bytes if the script
  // ever echoes them. The script does NOT echo GH_TOKEN today — defense-in-
  // depth only. Stdout/stderr pipe (NOT inherit) to enforce the redactor.
  // Spawn: spawn("/bin/bash", ["scripts/strategy-review-check.sh"], { cwd, env, detached: true })]
}

async function postSentryHeartbeat(args: {
  ok: boolean;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  // [verbatim from cron-bug-fixer.ts:postSentryHeartbeat — single end-of-step
  // POST per 2026-05-18-vendor-cron-heartbeat-silent-fail-pattern.md]
}

// ----- handler -----

export async function cronStrategyReviewHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; exitCode: number | null; durationMs: number }> {
  // 1. Parse date_override (manual-trigger event); validate YYYY-MM-DD shape.
  let dateOverride: string | undefined;
  const raw = event?.data?.date_override;
  if (raw !== undefined && raw !== null) {
    if (typeof raw !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
      reportSilentFallback(
        new Error(`Invalid event.data.date_override: ${JSON.stringify(raw)}`),
        {
          feature: "cron-strategy-review",
          op: "parse-event-data",
          message: "date_override must be YYYY-MM-DD",
          extra: { fn: "cron-strategy-review", rawOverride: String(raw) },
        },
      );
      await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: false, logger }));
      return { ok: false, exitCode: null, durationMs: 0 };
    }
    dateOverride = raw;
  }

  // 2. Mint installation token (memoized across replays).
  const installationToken = await step.run("mint-installation-token", () => mintInstallationToken());

  // 3. Setup ephemeral workspace (clone --depth=1, sentinel-check script path).
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const ws = await step.run("setup-workspace", () => setupEphemeralWorkspace(installationToken));
    ephemeralRoot = ws.ephemeralRoot;
    spawnCwd = ws.spawnCwd;
  } catch (err) {
    const e = err as Error;
    reportSilentFallback(new Error(redactToken(e.message ?? "", installationToken)), {
      feature: "cron-strategy-review",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-strategy-review" },
    });
    await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: false, logger }));
    return { ok: false, exitCode: null, durationMs: 0 };
  }

  // 4. Spawn bash script + heartbeat in try/finally so teardown always runs.
  try {
    const result = await step.run("strategy-review-check", () =>
      spawnStrategyReview({ spawnCwd: spawnCwd!, installationToken, dateOverride, logger }),
    );
    if (result.abortedByTimeout) {
      reportSilentFallback(
        new Error(`strategy-review-check aborted by timeout (${MAX_RUN_DURATION_MS}ms)`),
        {
          feature: "cron-strategy-review",
          op: "spawn-timeout",
          message: "strategy-review-check aborted by AbortController",
          extra: { fn: "cron-strategy-review", durationMs: result.durationMs, maxMs: MAX_RUN_DURATION_MS },
        },
      );
    }
    await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: result.ok, logger }));
    return { ok: result.ok, exitCode: result.exitCode, durationMs: result.durationMs };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) =>
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-strategy-review", ephemeralRoot },
      }),
    );
  }
}

// ----- registration -----

export const cronStrategyReview = inngest.createFunction(
  {
    id: "cron-strategy-review",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [{ cron: "0 8 * * 1" }, { event: "cron/strategy-review.manual-trigger" }],
  cronStrategyReviewHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
```

**Key simplifications vs PR-5 `cron-bug-fixer.ts`:**

- No `resolveClaudeBin` / no `CLAUDE_CODE_FLAGS` / no claude-eval prompt. Spawn `/bin/bash` directly with the script path.
- No plugin symlink in `setupEphemeralWorkspace` (script needs only the cloned repo's `scripts/` + `knowledge-base/` trees, not `plugins/soleur/`).
- No `precreateLabels` step — the script's `gh label create "$LABEL" 2>/dev/null || true` handles it idempotently.
- No PR-detection / auto-merge-gate / notify-ops-email steps.
- 10-min `MAX_RUN_DURATION_MS` (vs PR-5's 50-min claude-eval budget).
- No `CLAUDE_BIN` resolution — `/bin/bash` is POSIX-canonical.

**Borrowed verbatim from PR-5:**

- `mintInstallationToken` shape and `TOKEN_MIN_LIFETIME_MS` floor (smaller value, same semantics).
- `buildAuthenticatedCloneUrl` + `redactToken` (defense-in-depth even though script doesn't echo).
- `setupEphemeralWorkspace` minus the plugin symlink.
- `spawnStrategyReview` AbortController + SIGTERM→SIGKILL escalation (process-group kill via `detached: true`).
- `postSentryHeartbeat` single-step pattern.
- `teardownEphemeralWorkspace` finally-block discipline.

### Phase 2 — Register in `/api/inngest/route.ts`

Add the import (alphabetical) between `cronOauthProbe` and `cronStrategyReview` is the natural slot — but alphabetical order with the existing list places `cronStrategyReview` AFTER `cronOauthProbe` and BEFORE `githubOnEvent` in the registry:

```typescript
import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";
```

And add `cronStrategyReview` to the `functions: [...]` array in alphabetical position.

### Phase 3 — Add Sentry cron monitor resource

In `apps/web-platform/infra/sentry/cron-monitors.tf`, add a new `sentry_cron_monitor.scheduled_strategy_review` resource after the PR-5 `scheduled_bug_fixer` block (alphabetical → after bug-fixer, before daily-triage):

```hcl
# TR9 PR-6 (closes #4416): Inngest-fired via
# `apps/web-platform/server/inngest/functions/cron-strategy-review.ts`. NEW
# monitor — no GHA-era predecessor (the workflow ran on GHA's runner pool
# with no Sentry check-in). The GHA scheduled-strategy-review workflow was
# deleted in the same commit per TR9 I-13 hygiene.
resource "sentry_cron_monitor" "scheduled_strategy_review" {
  organization            = var.sentry_org
  project                 = data.sentry_project.web_platform.slug
  name                    = "scheduled-strategy-review"
  schedule                = { crontab = "0 8 * * 1" }
  checkin_margin_minutes  = 30
  max_runtime_minutes     = 10
  failure_issue_threshold = 1
  recovery_threshold      = 1
  timezone                = "UTC"
}
```

`max_runtime_minutes = 10` matches `MAX_RUN_DURATION_MS` in the TS file. The auto-apply workflow `.github/workflows/apply-sentry-infra.yml` already scopes to `-target=sentry_cron_monitor.*` (per `cron-monitors.tf` line 13 comment) so this resource auto-creates on push to `main`.

### Phase 4 — DELETE `.github/workflows/scheduled-strategy-review.yml`

In the SAME commit the Inngest function lands, `git rm .github/workflows/scheduled-strategy-review.yml`. The `scripts/strategy-review-check.sh` file STAYS — it's now the cron's binary contract.

### Phase 5 — Write capture learning

`knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-shell-only-no-claude-eval-pattern.md`:

Topic: "When a TR9 cron migration source is a pure bash script (no `claude-code-action` step), the Inngest migration drops the entire claude-eval + plugin-loading + token-redaction-pipe surface and shrinks to just: ephemeral workspace + GH App token + bash spawn + Sentry heartbeat. Plugin symlink and `--allowedTools` are claude-specific and have zero role here. The bash script's exit code becomes the entire ok/error contract."

### Phase 6 — Test

```bash
cd apps/web-platform
bun test test/server/cron-no-byok-lease-sweep.test.ts
# Expect: cron-strategy-review.ts auto-included in glob; passes (no runWithByokLease import).

bun run typecheck   # tsc --noEmit; route.ts import resolves; inngest serve() signature satisfied.

# Sentry TF validate (no apply — apply happens on push to main per Phase 3 above):
cd apps/web-platform/infra/sentry
terraform init -input=false
terraform validate
```

### Phase 7 — Post-merge verification (automated)

`/soleur:ship` already runs `gh workflow run apply-sentry-infra.yml` on PR merge (handles Phase 3 auto-apply). Post-merge automation:

1. `gh run list --workflow=apply-sentry-infra.yml --limit=1` confirms TF auto-apply ran on the merge SHA.
2. **Operator automation feasibility:** the next scheduled fire is the following Monday 08:00 UTC; verify-on-deploy is moot because Inngest can be hand-fired immediately via `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'`. Post-merge ship step fires this and confirms the function landed in the registry.
3. `gh api -X POST /repos/jikig-ai/soleur/dispatches` is NOT needed — `gh workflow run` is the canonical dispatch.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1** — `apps/web-platform/server/inngest/functions/cron-strategy-review.ts` exists; structure matches Phase 1 outline (handler exports `cronStrategyReview`, single-step Sentry heartbeat, AbortController + SIGTERM→SIGKILL escalation, redact-pipe stdio).
- [ ] **AC2** — `grep -E "^\s*(runWithByokLease|resolveKeyOwnerThenLease)\s*\(" apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns ZERO matches.
- [ ] **AC3** — `grep -E "import.*byok-lease" apps/web-platform/server/inngest/functions/cron-strategy-review.ts` returns ZERO matches.
- [ ] **AC4** — `cd apps/web-platform && bun test test/server/cron-no-byok-lease-sweep.test.ts` passes; output includes `cron-strategy-review.ts` in the `for (const file of cronFiles)` enumeration (the inverse-assertion fixture-proof tests + 6 cron-* file tests, now 7).
- [ ] **AC5** — `apps/web-platform/app/api/inngest/route.ts` contains both: `import { cronStrategyReview } from "@/server/inngest/functions/cron-strategy-review";` AND `cronStrategyReview,` inside the `functions: [...]` array. `cd apps/web-platform && bun run typecheck` succeeds.
- [ ] **AC6** — `apps/web-platform/infra/sentry/cron-monitors.tf` contains a `resource "sentry_cron_monitor" "scheduled_strategy_review"` block with `name = "scheduled-strategy-review"`, `schedule = { crontab = "0 8 * * 1" }`, `max_runtime_minutes = 10`. `cd apps/web-platform/infra/sentry && terraform init -input=false && terraform validate` exits 0.
- [ ] **AC7** — `.github/workflows/scheduled-strategy-review.yml` is DELETED. `git log --oneline -- .github/workflows/scheduled-strategy-review.yml apps/web-platform/server/inngest/functions/cron-strategy-review.ts` shows BOTH paths in the same commit (use `git rev-list <base>..HEAD -- <paths>` + `git show <sha> --name-status -- <paths>` per the awk-range-union sharp edge — the YAML deletion and the new TS file MUST land atomic in one commit).
- [ ] **AC8** — Capture learning file exists at `knowledge-base/project/learnings/2026-05-25-tr9-pr6-strategy-review-shell-only-no-claude-eval-pattern.md` with the "shell-only cron drops claude-eval surface" framing.
- [ ] **AC9** — PR body uses `Closes #4416` (the per-migration child issue) — NOT `Closes #3948` (the umbrella stays open until the umbrella's last child merges).
- [ ] **AC10** — `scripts/strategy-review-check.sh` is UNCHANGED (`git diff HEAD~1 -- scripts/strategy-review-check.sh` is empty).

### Post-merge (operator — but automated where possible)

- [ ] **AC11** — `gh run list --workflow=apply-sentry-infra.yml --limit=1 --json status,conclusion,headSha` confirms the post-merge Terraform apply completed `conclusion: success` on the merge SHA. Automation: `/soleur:ship`'s built-in `gh workflow run` triggers it; ship verification step polls until conclusion lands.
- [ ] **AC12** — Operator fires `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` (via `inngest-cli` on the Hetzner host); the function appears in `inngest list functions` and produces a successful run in the Inngest dashboard within 60s. Automation: deferred to `/soleur:ship` Phase 7 manual-trigger check (existing pattern for PR-1..PR-5).
- [ ] **AC13** — Sentry monitor `scheduled-strategy-review` appears at https://sentry.io with state `active` and a fresh `ok` check-in from AC12's manual trigger. Automation: `mcp__plugin_soleur_cloudflare__*` / Sentry-direct MCP is not loaded; defer to operator visual verify per `/soleur:postmerge`'s standing checklist (NOT operator-only — verifiable via the Sentry REST API but the cron-monitors.tf precedent already accepts dashboard-eyeball as the recovery-confirmation step at PR-1..PR-5 merge time).
- [ ] **AC14** — Umbrella #3948 body checklist updated to mark `scheduled-strategy-review` line as done with PR-6 link. Automation: `/soleur:ship` updates the umbrella body automatically (existing PR-1..PR-5 precedent in ship/SKILL.md).
- [ ] **AC15** — Issue #4416 closed automatically via `Closes #4416` in PR body at merge.

## Open Code-Review Overlap

`gh issue list --label code-review --state open --json number,title,body --limit 200` — scanned for paths touching `apps/web-platform/server/inngest/functions/`, `apps/web-platform/app/api/inngest/route.ts`, `apps/web-platform/infra/sentry/cron-monitors.tf`, `scripts/strategy-review-check.sh`, `.github/workflows/scheduled-strategy-review.yml`. **None.**

## Domain Review

**Domains relevant:** CTO (cron substrate / infrastructure). CPO not relevant (no user-facing surface). CLO not relevant beyond bucket-(i) carry-forward (operator-only data flow).

### CTO

**Status:** carry-forward from PR-5 multi-agent review (which approved the ephemeral-workspace + GH App token pattern).
**Assessment:** PR-6 is a strict subset of PR-5's surface (drops claude-eval + plugin symlink + auto-merge + Resend; keeps ephemeral workspace + token + Sentry heartbeat). No new architectural primitives are introduced. The simplification surface is the absence of components, not the addition of new ones. ADR-033 invariants I1/I3/I5/I6 carry over verbatim; I2 is structurally satisfied (no SDK call); I4 is reshaped (bash binary, not claude binary — `/bin/bash` POSIX path).

No fresh agent invocations needed beyond the carry-forward.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/sentry/cron-monitors.tf` — add `sentry_cron_monitor.scheduled_strategy_review` resource. NO new provider, NO new variable, NO new sensitive value. Reuses `var.sentry_org` + `data.sentry_project.web_platform.slug`.

### Apply path

- (c) **Auto-apply on push to main** via `.github/workflows/apply-sentry-infra.yml` (existing — added at PR-1 #3985 for sibling resources). The workflow is scoped to `-target=sentry_cron_monitor.*` per `cron-monitors.tf` line 13. Zero operator action.

### Distinctness / drift safeguards

- Sentry org/project are shared dev↔prd here (single Sentry project for web-platform per `hr-dev-prd-distinct-supabase-projects` does NOT apply to Sentry — Sentry is one project that ingests from both envs distinguished by `environment` tag). No drift hazard.

### Vendor-tier reality check

- Sentry crons monitors are unlimited on the team plan (current Soleur tier). No tier-gating needed.

## Observability

```yaml
liveness_signal:
  what: Sentry cron monitor "scheduled-strategy-review" check-in
  cadence: weekly (Mon 08:00 UTC)
  alert_target: Sentry → ops@jikigai.com via Sentry alert rule (existing for cron-monitor failures, applies to all sentry_cron_monitor resources)
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf (new resource scheduled_strategy_review) + apps/web-platform/server/inngest/functions/cron-strategy-review.ts (postSentryHeartbeat end-of-step.run POST)
error_reporting:
  destination: Sentry (via reportSilentFallback at every failure path — clone failure, spawn failure, abort-by-timeout, heartbeat-post failure, teardown failure, event-data-parse failure)
  fail_loud: true (reportSilentFallback mirrors to Sentry with feature/op/message/extra tagging per cq-silent-fallback-must-mirror-to-sentry)
failure_modes:
  - mode: "git clone --depth=1 fails (network, auth, repo deletion)"
    detection: spawn exitCode !== 0 in setupEphemeralWorkspace
    alert_route: reportSilentFallback → Sentry (feature=cron-strategy-review, op=setup-ephemeral-workspace) + step.run error + Sentry heartbeat status=error
  - mode: "bash script exits non-zero (gh API rate limit, malformed YAML in strategy doc, gh issue create failure)"
    detection: SpawnResult.ok === false in cronStrategyReviewHandler
    alert_route: Sentry heartbeat POST with status=error; stdout/stderr lines stream to logger.error (centralized via Inngest logs)
  - mode: "AbortController fires at MAX_RUN_DURATION_MS (10 min)"
    detection: SpawnResult.abortedByTimeout === true
    alert_route: reportSilentFallback (feature=cron-strategy-review, op=spawn-timeout) + Sentry heartbeat status=error
  - mode: "Installation token mint failure (GH App revoked, network)"
    detection: mintInstallationToken throws inside step.run
    alert_route: step.run replays once (retries: 1); on second failure, Sentry monitor opens issue via failure_issue_threshold=1 (no check-in lands)
  - mode: "Sentry heartbeat POST fails"
    detection: fetch error inside postSentryHeartbeat
    alert_route: reportSilentFallback (feature=cron-sentry-heartbeat) — monitor will open issue via missed check-in regardless
  - mode: "Teardown fails (stranded /tmp dir)"
    detection: rm() throws inside teardownEphemeralWorkspace
    alert_route: reportSilentFallback (feature=cron-strategy-review, op=teardown-ephemeral-workspace) — non-fatal, function still returns
logs:
  where: Inngest function logs (stdout/stderr from spawn streamed via redactToken pipe through logger.info/logger.error); Sentry events for reportSilentFallback paths
  retention: Inngest default (90 days for paid tier; check Doppler-pinned plan); Sentry default (90 days for events on team plan)
discoverability_test:
  command: 'curl -fsS https://api.example.invalid # placeholder — replaced with: gh api graphql -f query="query{viewer{login}}" --jq .data.viewer.login asserts the GH App token mint path works; for the live function probe: inngest send cron/strategy-review.manual-trigger ''{"actor":"platform","data":{"date_override":"2026-05-25"}}'' && sleep 30 && curl -fsS https://app.inngest.com/.../runs?function_id=cron-strategy-review | jq ''.runs[0].status''  — expected: "Completed". NO ssh required.'
  expected_output: '"Completed" (status from Inngest API for the most recent run of cron-strategy-review)'
```

## Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `git clone --depth=1` fails on Hetzner (DNS, network, GH App token expired) | Low | Medium (cron silently skipped one week) | `reportSilentFallback` → Sentry; missed Sentry check-in opens issue at `failure_issue_threshold=1` |
| Script reads a `last_reviewed` date that's malformed and the script's `set -euo pipefail` exits non-zero | Low | Low (script handles via `2>/dev/null` + continue) | Script already handles `2>&1` warnings and `continue`s on bad dates; `errors` counter; exit 1 only if `errors > 0`. Function reports status=error in that case but doesn't crash. |
| Concurrent manual-trigger fires while scheduled cron fires | Very low | Very low | `concurrency: [{ scope: "fn", limit: 1 }, { scope: "account", key: '"cron-platform"', limit: 1 }]` serializes both paths |
| Inngest replay re-executes the bash script after partial completion (e.g., script created 3 of 5 issues then crashed) | Low | Low (script dedups via `gh issue list --label "$LABEL"`) | Script's dedup check is idempotent across replays; worst case is an extra `gh issue list` call (harmless) |
| GH App token expires mid-spawn (token has ≥15 min lifetime when minted, spawn budget is 10 min) | Very low | Low | `TOKEN_MIN_LIFETIME_MS = 15 min`; mint floor exceeds spawn budget by 5 min |
| Script's `gh issue create` rate-limited by GitHub | Very low (max 5-10 issues per fire) | Low (operator notices the next Monday) | Script's `errors=$((errors + 1))` counter + final exit 1 → reportSilentFallback → Sentry |
| Plugin-symlink hazard (PR-5 specific) | N/A | N/A | Not applicable — PR-6 spawns no claude, so no symlink is created. Confirms via Phase 1 outline. |

## Pattern Boundaries (PR-6 specific — DO NOT carry to PR-7..N without re-derivation)

- `MAX_RUN_DURATION_MS = 10 min` ← bound by ~30s typical run + 4× headroom (PR-2 followed similar logic at 15 min for predicate-heavy script)
- `TOKEN_MIN_LIFETIME_MS = 15 min` ← bound by `MAX_RUN_DURATION_MS + 5 min slack`
- No plugin symlink ← bound by "this cron spawns no claude / no plugin"
- `cron: "0 8 * * 1"` ← bound by the weekly-strategy-review SLA semantic (Monday morning = start of work week)
- 5-step pipeline (mint-token → setup-workspace → strategy-review-check → sentry-heartbeat + finally:teardown) ← bound by shell-only pattern; PR-5's 9-step pipeline is for claude-eval crons

When the next group-(c) migration considers reusing this shape, **re-derive every boundary** — `scheduled-roadmap-review` (next likely child) ALSO has `bash scripts/roadmap-review-check.sh` (verify), so this pattern is reusable for it; subsequent migrations like `scheduled-community-monitor` (kb-writer + pr-creator, bucket ii) likely need PR-5's claude-eval shape instead.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above with `none` threshold + operator-only justification.
- The PR MUST land the GHA-YAML delete + new TS file + sentry TF resource in a SINGLE commit (per umbrella I-13 hygiene). `git log --oneline -- <yaml> <ts>` is a UNION filter (sharp edge from `2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption`); use `git rev-list <base>..HEAD -- <paths>` + per-commit `git show --name-status` to assert atomic landing in AC7.
- Sentry monitor name `scheduled-strategy-review` is NEW (no GHA-era predecessor). Do NOT confuse with the PR-5 rename-hazard pattern (PR-1..PR-4 preserved historical slugs because the GHA-era workflows had Sentry check-ins; PR-5 and PR-6 are NEW slugs because the GHA workflows had no Sentry monitor).
- The bash script's exit code is the entire ok/error contract for the Inngest step's `result.ok`. If a future PR modifies the script to exit 0 even on partial failures, the cron's Sentry heartbeat would silently mark status=ok while issues fail to land. Sentinel via `errors > 0 → exit 1` is the load-bearing invariant; do NOT relax it in subsequent script edits.
- ⚠️ The script's `--milestone "Post-MVP / Later"` may fail with HTTP 422 if that milestone has been renamed/deleted in the repo. The script `||` falls back to creating the issue without milestone, but the failure path emits `errors=$((errors + 1))` AND exits 1. If milestone failures become noisy post-merge, file a follow-up issue to make milestone assignment optional.
- The script reads `knowledge-base/{product,marketing,sales/battlecards}/` — if a future KB reorganization moves strategy docs (e.g., to `knowledge-base/strategy/`), the cron silently scans no files and reports "No strategy documents found." with exit 0. This is a soft-fail mode (status=ok, no issues created). Mitigation: the script's `if [[ ${#strategy_files[@]} -eq 0 ]]` branch should ideally be exit 1, but that's a script-edit out of scope. Track via Sharp Edge instead of fixing here.

## Test Strategy

- `apps/web-platform/test/server/cron-no-byok-lease-sweep.test.ts` — auto-extends to `cron-strategy-review.ts` via existing glob `server/inngest/functions/cron-*.ts`. No edit required. Validates: no `runWithByokLease` direct call, no aliased import, no bare named import, no dynamic import bypass.
- TypeScript compile via `bun run typecheck` validates the `inngest.createFunction` signature, handler args type, and import resolution in `route.ts`.
- Terraform validate (`terraform init -input=false && terraform validate`) confirms the new `sentry_cron_monitor` resource block parses against the `jianyuan/sentry` provider schema.
- Live smoke-test post-merge: `inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}'` from the Hetzner inngest-cli host → confirm a successful run in the Inngest dashboard within 60s + Sentry heartbeat lands.

## Rollback

If the new function misbehaves in production (e.g., creates duplicate issues, fails repeatedly):

1. Disable the cron schedule by amending `cron-strategy-review.ts` triggers to `[{ event: "cron/strategy-review.manual-trigger" }]` only (remove the `{ cron: "0 8 * * 1" }` entry); deploy.
2. Re-introduce `.github/workflows/scheduled-strategy-review.yml` from git history (`git show <pre-merge-sha>:.github/workflows/scheduled-strategy-review.yml`).
3. Remove the `sentry_cron_monitor.scheduled_strategy_review` resource from TF.
4. Leave `scripts/strategy-review-check.sh` intact (it never moved).

No data is mutated by the cron beyond GitHub issue creation (which is independently reversible via `gh issue close --reason "not planned"`). The migration is reversible without data-loss risk.

## PR Body Template

```
TR9 PR-6 — migrate scheduled-strategy-review to Inngest cron.

Closes #4416. (Umbrella #3948 child; update umbrella checklist on merge.)

## Summary
- Adds `cron-strategy-review.ts` Inngest function (~250 LoC; shell-only, no claude-eval).
- DELETES `.github/workflows/scheduled-strategy-review.yml` (TR9 I-13 hygiene).
- Adds `sentry_cron_monitor.scheduled_strategy_review` resource (NEW, no GHA-era predecessor).
- Reuses PR-5 ephemeral-workspace pattern minus plugin symlink (this cron spawns bash, not claude).

## Pattern note
First TR9 child with ZERO claude-eval. Drops --allowedTools, MAX_TURN_DURATION_MS, plugin symlink, Resend. Bash script's exit code is the entire ok/error contract. See learning 2026-05-25-tr9-pr6-strategy-review-shell-only-no-claude-eval-pattern.md.

## Test plan
- [ ] bun test test/server/cron-no-byok-lease-sweep.test.ts (auto-extends)
- [ ] bun run typecheck
- [ ] terraform validate apps/web-platform/infra/sentry
- [ ] Post-merge: inngest send cron/strategy-review.manual-trigger '{"actor":"platform"}' → Inngest dashboard shows successful run

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```
