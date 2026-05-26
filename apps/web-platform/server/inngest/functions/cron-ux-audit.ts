// TR9 PR-11/2 (closes #4464) — Migrated from the GHA scheduled-ux-audit
// workflow (deleted in the same PR per TR9 I-13 hygiene). Substrate
// extension: Playwright Chromium + bot-fixture lifecycle + Supabase
// findings-upload. Reference handler: cron-legal-audit.ts (closest
// side-effect class: claude-eval + issue-creator).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (50 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks.
//        Chromium pinned transitively via @playwright/test devDep at
//        docker build time (image-baked, not runtime-installed).
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)
//   I7 — Chromium zombie process reaping: production docker run SHOULD use
//        --init (tini) to reap zombie chrome zygote children. Without it,
//        zombie <defunct> processes accumulate (one set per monthly fire).
//        Verified in PR-1 I3 gate.
//
// SHAPE DIFF vs cron-legal-audit.ts:
//   - --allowedTools adds Playwright MCP tools for authenticated screenshots.
//   - Bot-fixture lifecycle: seed → signin → writeStorageState → eval → reset.
//   - Per-fire .mcp.json overlay with --user-data-dir (NOT --isolated).
//   - Upload findings to Supabase ux-audit-artifacts bucket.
//   - Monthly cron 0 9 1 * * (vs quarterly).

import { existsSync } from "node:fs";
import { chmod, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";
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
import { getPluginPath } from "@/server/plugin-path";
import { reportSilentFallback } from "@/server/observability";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-ux-audit";

const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;


export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";


const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-opus-4-7",
  "--max-turns",
  "60",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Task,mcp__playwright__browser_navigate,mcp__playwright__browser_take_screenshot,mcp__playwright__browser_resize,mcp__playwright__browser_close,mcp__playwright__browser_wait_for",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-ux-audit.yml lines 170-191 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
const UX_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly
to main. Do NOT create commits. The skill only creates GitHub
issues when UX_AUDIT_DRY_RUN=false; in dry-run mode it writes
findings to stdout and to
\${GITHUB_WORKSPACE}/tmp/ux-audit/findings.json only.

MILESTONE RULE: Every gh issue create command MUST include
--milestone "Post-MVP / Later".

Run /soleur:ux-audit against the route list at
plugins/soleur/skills/ux-audit/references/route-list.yaml. The bot
fixture has already been seeded and storageState.json written to
\${UX_AUDIT_STORAGE_STATE}. Follow SKILL.md exactly.

Cap enforcement is mandatory:
  CAP_OPEN_ISSUES = 20   (refuse to file when reached)
  CAP_PER_RUN     = 5    (severity-ranked top-N filed per run)

Injection safety: all finding fields (title, body, hash) must be
written to files or env vars before \`gh issue create\` — never
interpolate agent output into bash \`run:\` commands directly.
`;


function buildSpawnEnv(
  installationToken: string,
  extra: Record<string, string> = {},
): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
    ...extra,
  };
}


async function uploadFindings(args: {
  workspaceDir: string;
  installationToken: string;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const { workspaceDir, installationToken, logger } = args;
  const findingsPath = join(workspaceDir, "findings.json");

  if (!existsSync(findingsPath)) {
    logger.info({ fn: "cron-ux-audit" }, "No findings.json found — skipping upload");
    return;
  }

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceKey) {
    logger.warn({ fn: "cron-ux-audit" }, "Supabase env unset — skipping upload");
    return;
  }

  const runDate = new Date().toISOString().split("T")[0];
  const findings = await readFile(findingsPath, "utf-8");

  // Upload findings.json
  const uploadPath = `${runDate}/findings.json`;
  const uploadRes = await fetch(
    `${supabaseUrl}/storage/v1/object/ux-audit-artifacts/${uploadPath}`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: findings,
    },
  );
  if (!uploadRes.ok) {
    logger.warn(
      { fn: "cron-ux-audit", status: uploadRes.status },
      "findings.json upload failed",
    );
  }

  // Upload any screenshots (*.png in workspace)
  const files = await readdir(workspaceDir);
  const screenshots = files.filter((f) => f.endsWith(".png"));
  for (const screenshot of screenshots) {
    const screenshotPath = join(workspaceDir, screenshot);
    const screenshotData = await readFile(screenshotPath);
    const screenshotUploadPath = `${runDate}/${screenshot}`;
    await fetch(
      `${supabaseUrl}/storage/v1/object/ux-audit-artifacts/${screenshotUploadPath}`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "image/png",
        },
        body: screenshotData,
      },
    ).catch((err) => {
      logger.warn(
        { fn: "cron-ux-audit", screenshot, err: (err as Error).message },
        "screenshot upload failed",
      );
    });
  }

  logger.info(
    { fn: "cron-ux-audit", findingsUploaded: true, screenshotCount: screenshots.length },
    "findings uploaded to ux-audit-artifacts bucket",
  );
}

// =============================================================================
// Handler
// =============================================================================

export async function cronUxAuditHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // --- Step 1: mint installation token ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
  );

  // --- Step 2: bot-fixture-seed ---
  await step.run("bot-fixture-seed", async () => {
    const botFixturePath = join(getPluginPath(), "skills/ux-audit/scripts/bot-fixture.ts");
    const mod = await import(botFixturePath) as { seed: () => Promise<void> };
    await mod.seed();
  });

  // --- Step 3: bot-signin + writeStorageState ---
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  let workspaceDir: string | null = null;

  try {
    // --- Step 4: setup ephemeral workspace ---
    const workspace = await step.run("setup-workspace", async () => {
      const base = await setupEphemeralWorkspace({ installationToken, cronName: "cron-ux-audit" });
      const wDir = join(base.ephemeralRoot, "workspace");

      // Per-fire .mcp.json overlay for Playwright MCP
      const playwrightProfileDir = join(wDir, "playwright-mcp-profile");
      await mkdir(playwrightProfileDir, { recursive: true });
      const mcpConfig = {
        mcpServers: {
          playwright: {
            command: "npx",
            args: [
              "@playwright/mcp@latest",
              `--user-data-dir=${playwrightProfileDir}`,
            ],
          },
        },
      };
      await writeFile(
        join(base.spawnCwd, ".mcp.json"),
        JSON.stringify(mcpConfig, null, 2) + "\n",
        "utf-8",
      );

      // Workspace dir for storageState + findings output
      await mkdir(wDir, { recursive: true, mode: 0o700 });

      return { ...base, workspaceDir: wDir };
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
    workspaceDir = workspace.workspaceDir;

    // --- Step 5: bot-signin → write storageState to workspace ---
    await step.run("bot-signin", async () => {
      const botSigninPath = join(getPluginPath(), "skills/ux-audit/scripts/bot-signin.ts");
      const mod = await import(botSigninPath) as {
        signIn: () => Promise<{ access_token: string; refresh_token: string; expires_in: number; expires_at: number; token_type: string; user: unknown }>;
        writeStorageState: (session: unknown, outPath: string, supabaseUrl: string, siteUrl: string) => void;
      };
      const session = await mod.signIn();
      const outPath = join(workspace.workspaceDir, "storage-state.json");
      mod.writeStorageState(
        session,
        outPath,
        process.env.SUPABASE_URL!,
        process.env.NEXT_PUBLIC_APP_URL!,
      );
      await chmod(outPath, 0o600);
    });

    // --- Step 6: claude-eval ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        const storageStatePath = join(workspaceDir!, "storage-state.json");
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          flags: CLAUDE_CODE_FLAGS,
          prompt: UX_AUDIT_PROMPT,
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-ux-audit",
          buildSpawnEnv: (token) => buildSpawnEnv(token, {
            UX_AUDIT_DRY_RUN: "true",
            UX_AUDIT_STORAGE_STATE: storageStatePath,
          }),
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
          feature: "cron-ux-audit",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-ux-audit",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 7: upload findings ---
    await step.run("upload-findings", async () => {
      await uploadFindings({
        workspaceDir: workspaceDir!,
        installationToken,
        logger,
      });
    });

    // --- Step 8: bot-fixture-reset ---
    await step.run("bot-fixture-reset", async () => {
      const botFixturePath = join(getPluginPath(), "skills/ux-audit/scripts/bot-fixture.ts");
      const mod = await import(botFixturePath) as { reset: () => Promise<void> };
      await mod.reset();
    });

    // --- Step 9: sentry heartbeat ---
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: spawnResult.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-ux-audit", logger });
    });

    return { ok: spawnResult.ok };
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-ux-audit",
      op: "handler",
      message: "cron-ux-audit handler failed",
      extra: { fn: "cron-ux-audit" },
    });
    await step.run("sentry-heartbeat-error", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-ux-audit", logger });
    });
    return { ok: false };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-ux-audit").catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-ux-audit",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-ux-audit", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================

export const cronUxAudit = inngest.createFunction(
  {
    id: "cron-ux-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 1 * *" },
    { event: "cron/ux-audit.manual-trigger" },
  ],
  cronUxAuditHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
