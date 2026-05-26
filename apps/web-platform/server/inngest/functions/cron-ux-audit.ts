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

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import {
  chmod,
  mkdir,
  mkdtemp,
  readdir,
  readFile,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { inngest } from "@/server/inngest/client";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import { getPluginPath } from "@/server/plugin-path";
import { reportSilentFallback } from "@/server/observability";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-ux-audit";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export const KILL_ESCALATION_MS = 5_000;

const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

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

const DEFAULT_CLAUDE_SETTINGS = {
  permissions: {
    allow: [] as string[],
  },
  sandbox: {
    enabled: true,
  },
};

// =============================================================================
// Types
// =============================================================================

interface SpawnResult {
  ok: boolean;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  abortedByTimeout: boolean;
  durationMs: number;
}

interface HandlerArgs {
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
}

// =============================================================================
// Helpers (shared with cron-legal-audit.ts — not extracted to avoid coupling)
// =============================================================================

function resolveClaudeBin(): string {
  const override = process.env.CLAUDE_BIN;
  if (override && existsSync(override)) return override;
  const candidates = [
    "/app/node_modules/.bin/claude",
    join(process.cwd(), "node_modules/.bin/claude"),
    join(process.cwd(), "apps/web-platform/node_modules/.bin/claude"),
  ];
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  throw new Error(
    `claude binary not found in any known location: ${candidates.join(", ")}. ` +
      "Set CLAUDE_BIN env var to override.",
  );
}

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

function buildAuthenticatedCloneUrl(token: string): string {
  return `https://x-access-token:${token}@github.com/${REPO_OWNER}/${REPO_NAME}.git`;
}

function redactToken(s: string, token: string): string {
  if (!token) return s;
  return s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]");
}

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

function spawnSimple(
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<{ exitCode: number | null; signal: NodeJS.Signals | null }> {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, {
      stdio: "ignore",
      cwd: opts.cwd,
      env: opts.env ?? process.env,
    });
    child.on("exit", (exitCode: number | null, signal: NodeJS.Signals | null) => {
      resolve({ exitCode, signal });
    });
    child.on("error", () => {
      resolve({ exitCode: -1, signal: null });
    });
  });
}

// =============================================================================
// Workspace setup (extended for Playwright MCP overlay)
// =============================================================================

async function setupEphemeralWorkspace(
  installationToken: string,
): Promise<{ ephemeralRoot: string; spawnCwd: string; workspaceDir: string }> {
  const ephemeralRoot = await mkdtemp(join(tmpdir(), "soleur-cron-ux-audit-"));
  const spawnCwd = join(ephemeralRoot, "repo");
  const workspaceDir = join(ephemeralRoot, "workspace");

  // 1. git clone --depth=1
  const cloneUrl = buildAuthenticatedCloneUrl(installationToken);
  const cloneResult = await spawnSimple("git", [
    "clone",
    "--depth=1",
    cloneUrl,
    spawnCwd,
  ]);
  if (cloneResult.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}, signal ${cloneResult.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }

  // 2. plugin symlink
  const pluginsDir = join(spawnCwd, "plugins");
  const symlinkTarget = join(pluginsDir, "soleur");
  await rm(symlinkTarget, { recursive: true, force: true });
  await mkdir(pluginsDir, { recursive: true });
  await symlink(getPluginPath(), symlinkTarget);

  // 3. .claude/settings.json overlay
  const claudeDir = join(spawnCwd, ".claude");
  await mkdir(claudeDir, { recursive: true });
  await writeFile(
    join(claudeDir, "settings.json"),
    JSON.stringify(DEFAULT_CLAUDE_SETTINGS, null, 2) + "\n",
    "utf-8",
  );

  // 4. Per-fire .mcp.json overlay for Playwright MCP
  const playwrightProfileDir = join(workspaceDir, "playwright-mcp-profile");
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
    join(spawnCwd, ".mcp.json"),
    JSON.stringify(mcpConfig, null, 2) + "\n",
    "utf-8",
  );

  // 5. Sentinel check
  const manifestPath = join(symlinkTarget, ".claude-plugin", "plugin.json");
  if (!existsSync(manifestPath)) {
    throw new Error(
      `Plugin sentinel check failed: ${manifestPath} does not exist (symlink target empty or wrong path)`,
    );
  }

  // 6. Workspace dir for storageState + findings output
  await mkdir(workspaceDir, { recursive: true, mode: 0o700 });

  return { ephemeralRoot, spawnCwd, workspaceDir };
}

async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-ux-audit",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-ux-audit", ephemeralRoot },
    });
  }
}

// =============================================================================
// Claude-eval spawn
// =============================================================================

async function spawnClaudeEval(args: {
  spawnCwd: string;
  installationToken: string;
  workspaceDir: string;
  logger: HandlerArgs["logger"];
}): Promise<SpawnResult> {
  const { spawnCwd, installationToken, workspaceDir, logger } = args;
  if (!existsSync(spawnCwd)) {
    throw new Error(
      `spawn cwd ${spawnCwd} no longer exists (container restart between setup-workspace and claude-eval?). ` +
        `Re-run will re-execute setup-workspace and create a fresh ephemeral root.`,
    );
  }
  const claudeBin = resolveClaudeBin();
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), MAX_TURN_DURATION_MS);
  const startedAt = Date.now();
  let abortedByTimeout = false;
  let exited = false;
  let escalationTimer: NodeJS.Timeout | null = null;

  const storageStatePath = join(workspaceDir, "storage-state.json");

  try {
    return await new Promise<SpawnResult>((resolve) => {
      const child = spawn(
        claudeBin,
        [...CLAUDE_CODE_FLAGS, UX_AUDIT_PROMPT],
        {
          detached: true,
          stdio: ["ignore", "pipe", "pipe"],
          cwd: spawnCwd,
          env: buildSpawnEnv(installationToken, {
            UX_AUDIT_DRY_RUN: "true",
            UX_AUDIT_STORAGE_STATE: storageStatePath,
          }),
        },
      );

      if (child.stdout) {
        const rlOut = createInterface({ input: child.stdout });
        rlOut.on("line", (line) => {
          logger.info(
            { fn: "cron-ux-audit", stream: "stdout" },
            redactToken(line, installationToken),
          );
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          logger.error(
            { fn: "cron-ux-audit", stream: "stderr" },
            redactToken(line, installationToken),
          );
        });
      }

      const finish = (r: SpawnResult) => {
        exited = true;
        if (escalationTimer) clearTimeout(escalationTimer);
        resolve(r);
      };

      ac.signal.addEventListener(
        "abort",
        () => {
          abortedByTimeout = true;
          if (!child.pid) return;
          const pid = child.pid;
          try {
            process.kill(-pid, "SIGTERM");
          } catch {
            // process group already gone
          }
          escalationTimer = setTimeout(() => {
            if (exited) return;
            try {
              process.kill(-pid, "SIGKILL");
            } catch {
              // already exited
            }
          }, KILL_ESCALATION_MS);
        },
        { once: true },
      );

      child.on("exit", (exitCode, signal) => {
        finish({
          ok: exitCode === 0,
          exitCode,
          signal,
          abortedByTimeout,
          durationMs: Date.now() - startedAt,
        });
      });
      child.on("error", (err) => {
        const redactedMsg = redactToken(err.message ?? "", installationToken);
        const redacted = new Error(redactedMsg);
        redacted.name = err.name;
        reportSilentFallback(redacted, {
          feature: "cron-claude-eval",
          op: "child_process.spawn",
          message: "claude-code spawn failed",
          extra: { fn: "cron-ux-audit" },
        });
        finish({
          ok: false,
          exitCode: -1,
          signal: null,
          abortedByTimeout,
          durationMs: Date.now() - startedAt,
        });
      });

      logger.info(
        { fn: "cron-ux-audit", spawnCwd, pid: child.pid },
        "claude-eval spawned",
      );
    });
  } finally {
    clearTimeout(timer);
  }
}

// =============================================================================
// Sentry heartbeat
// =============================================================================

async function postSentryHeartbeat(args: {
  ok: boolean;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const { ok, logger } = args;
  const domain = process.env.SENTRY_INGEST_DOMAIN;
  const projectId = process.env.SENTRY_PROJECT_ID;
  const publicKey = process.env.SENTRY_PUBLIC_KEY;
  if (!domain || !projectId || !publicKey) {
    logger.info({ fn: "cron-ux-audit" }, "Sentry env unset — skipping heartbeat");
    return;
  }
  if (
    !SENTRY_DOMAIN_RE.test(domain) ||
    !SENTRY_PROJECT_RE.test(projectId) ||
    !SENTRY_PUBLIC_KEY_RE.test(publicKey)
  ) {
    logger.warn({ fn: "cron-ux-audit" }, "Sentry env malformed — skipping heartbeat");
    return;
  }
  const status = ok ? "ok" : "error";
  const url = `https://${domain}/api/${projectId}/cron/${SENTRY_MONITOR_SLUG}/${publicKey}/?status=${status}`;
  try {
    await fetch(url, {
      method: "POST",
      signal: AbortSignal.timeout(SENTRY_HEARTBEAT_TIMEOUT_MS),
    });
  } catch (err) {
    const e = err as Error;
    reportSilentFallback(e, {
      feature: "cron-sentry-heartbeat",
      op: "fetch",
      message: "Sentry Crons heartbeat POST failed",
      extra: { fn: "cron-ux-audit", status, aborted: e.name === "TimeoutError" },
    });
  }
}

// =============================================================================
// Upload findings to Supabase ux-audit-artifacts bucket
// =============================================================================

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
    async () => mintInstallationToken(),
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
      return setupEphemeralWorkspace(installationToken);
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
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          workspaceDir: workspaceDir!,
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
      await postSentryHeartbeat({ ok: spawnResult.ok, logger });
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
      await postSentryHeartbeat({ ok: false, logger });
    });
    return { ok: false };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) => {
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
