// TR9 Phase 2 — Migrated from the GHA scheduled-content-generator workflow
// (deleted in the same PR per TR9 I-13 hygiene). claude-code-spawn pattern;
// structural template is cron-roadmap-review.ts.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (55 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks; the
//        CLAUDE_BIN env var is the override hatch for fresh-host bootstraps.
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)

import {
  redactToken,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-content-generator";

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 55-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 55 * 60 * 1000 + 10 * 60 * 1000;

// 55 min wall-clock budget (from 60 min GHA timeout minus headroom).
// Exported for test parity.
export const MAX_TURN_DURATION_MS = 55 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-sonnet-4-6",
  "--max-turns",
  "50",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-content-generator.yml.
const CONTENT_GENERATOR_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly to main. Use the PR-based commit pattern in the MANDATORY FINAL STEP.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

STEP 1 — Select topic from queue:
Read knowledge-base/marketing/seo-refresh-queue.md and identify the highest-priority item without a "generated_date" annotation. Priority order: Priority 1 first, then Priority 2 pillar, then Priority 2 comparison.

If ALL items have a generated_date:
  STEP 1b — Run /soleur:growth plan "Company-as-a-Service content for solo founders building with AI"
  Extract the single highest-priority P1 content suggestion.
  If no usable topic, create issue "[Scheduled] Content Generator - <today>" with label "scheduled-content-generator" and stop.

STEP 2 — Generate article:
Run /soleur:content-writer <topic> --headless
If content-writer aborts due to FAIL citations, create issue and stop.

STEP 3 — Generate distribution content:
Run /soleur:social-distribute <article-path> --headless
Ensure frontmatter has: publish_date: <today>, status: scheduled, channels: discord, x, bluesky, linkedin-company

STEP 4 — Validate:
npx @11ty/eleventy
bash scripts/validate-blog-links.sh _site
If build or link validation fails, create issue and stop.

STEP 5 — Record topic in queue:
Update seo-refresh-queue.md with generated_date annotation.

STEP 6 — Create audit issue:
"[Scheduled] Content Generator - <today>" with label "scheduled-content-generator"

MANDATORY FINAL STEP — persist via PR:
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add -A
git diff --cached --quiet && echo "No changes to commit" && exit 0
BRANCH="ci/content-gen-$(date -u +%Y-%m-%d-%H%M%S)"
git checkout -b "$BRANCH"
git commit -m "feat(content): auto-generate article"
git push -u origin "$BRANCH"
gh pr create --title "feat(content): auto-generate article $(date -u +%Y-%m-%d)" --body "Automated commit from content generator workflow." --base main --head "$BRANCH"
gh pr merge "$BRANCH" --squash --auto
`;

// Spawn-env allowlist (NOT a denylist). The keys below are the COMPLETE set
// the spawned claude is allowed to see; anything not listed (notably
// RESEND_API_KEY, SENTRY_*, DOPPLER_*, GITHUB_APP_PRIVATE_KEY) is excluded.
function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
  };
}

// =============================================================================
// Handler
// =============================================================================

export async function cronContentGeneratorHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // --- Step 1: mint installation token (memoized across replays) ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: setup ephemeral workspace (clone + symlink + sentinel) ---
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-content-generator" });
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-content-generator",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-content-generator" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-content-generator", logger });
    });
    return { ok: false };
  }

  try {
    // --- Step 3: claude-eval (55-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: CONTENT_GENERATOR_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-content-generator",
          buildSpawnEnv,
          logger,
        });
      },
    );

    if (spawnResult.abortedByTimeout) {
      reportSilentFallback(
        new Error(
          `claude-eval aborted by timeout (${MAX_TURN_DURATION_MS}ms budget exceeded)`,
        ),
        {
          feature: "cron-content-generator",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-content-generator",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 4: sentry-heartbeat (final POST) ---
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: spawnResult.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-content-generator", logger });
    });

    return { ok: spawnResult.ok };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-content-generator").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-content-generator",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-content-generator", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 10 * * 2,4 UTC — Tuesday/Thursday 10:00) +
// manual operator event `cron/content-generator.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation.

export const cronContentGenerator = inngest.createFunction(
  {
    id: "cron-content-generator",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 10 * * 2,4" },
    { event: "cron/content-generator.manual-trigger" },
  ],
  cronContentGeneratorHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
