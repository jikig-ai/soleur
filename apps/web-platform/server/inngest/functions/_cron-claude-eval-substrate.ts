import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { getPluginPath } from "@/server/plugin-path";
import { reportSilentFallback } from "@/server/observability";
import {
  buildAuthenticatedCloneUrl,
  redactToken,
  resolveCronWorkspaceRoot,
  warnIfCronWorkspaceLowOnDisk,
  type HandlerArgs,
} from "./_cron-shared";

export interface SpawnResult {
  ok: boolean;
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  abortedByTimeout: boolean;
  durationMs: number;
  // Bounded tail of the child's stderr (redacted), so a non-zero exit is
  // self-diagnosing in Sentry. The line-by-line pino stream goes to app stdout,
  // which Vector does NOT ship to Better Stack — capturing the tail here is the
  // only path that reaches Sentry. #4714 follow-up (roadmap/content silent
  // non-zero exits were undiagnosable: app stdout is not in the log warehouse).
  // Optional: sibling crons (daily-triage, follow-through-monitor) build their
  // own SpawnResult literals via the inline spawn pattern and do not populate it.
  stderrTail?: string;
}

export const KILL_ESCALATION_MS = 5_000;

// Hard ceiling on captured child stderr — a pathological process must not OOM
// the worker. 8 KiB comfortably holds a git fatal: line + a few hints.
export const STDERR_CAP_BYTES = 8192;

export function resolveClaudeBin(): string {
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

export function spawnSimple(
  cmd: string,
  args: string[],
  opts: { cwd?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<{
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  stderr: string;
}> {
  return new Promise((resolve) => {
    // Capture stderr (stdin/stdout stay ignored). Without this, a non-zero
    // exit — e.g. `git clone` exit 128 — discarded the only line that says
    // WHY (auth/network/DNS), leaving Sentry with an opaque exit code. The
    // caller folds this into the thrown error so the next failure is
    // self-diagnosing (cq-silent-fallback-must-mirror-to-sentry).
    const child = spawn(cmd, args, {
      stdio: ["ignore", "ignore", "pipe"],
      cwd: opts.cwd,
      env: opts.env ?? process.env,
    });
    let stderr = "";
    if (child.stderr) {
      child.stderr.setEncoding("utf-8");
      child.stderr.on("data", (chunk: string) => {
        // Exact cap (slice on assignment) — appending whole chunks could
        // overshoot the ceiling by up to one chunk's length.
        if (stderr.length < STDERR_CAP_BYTES) {
          stderr = (stderr + chunk).slice(0, STDERR_CAP_BYTES);
        }
      });
    }
    child.on("exit", (exitCode: number | null, signal: NodeJS.Signals | null) => {
      resolve({ exitCode, signal, stderr: stderr.trim() });
    });
    child.on("error", (err: Error) => {
      resolve({ exitCode: -1, signal: null, stderr: err.message });
    });
  });
}

const DEFAULT_CLAUDE_SETTINGS = {
  permissions: {
    allow: [] as string[],
  },
  sandbox: {
    enabled: true,
  },
};

export async function setupEphemeralWorkspace(args: {
  installationToken: string;
  cronName: string;
}): Promise<{ ephemeralRoot: string; spawnCwd: string }> {
  const { installationToken, cronName } = args;
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), `soleur-${cronName}-`),
  );
  const spawnCwd = join(ephemeralRoot, "repo");

  // Pre-clone free-space guard (#4684/#4689 observability fold-in). Non-fatal:
  // warns in Sentry if the workspace root is low on disk before the clone.
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, cronName);

  const cloneUrl = buildAuthenticatedCloneUrl(installationToken);
  const cloneResult = await spawnSimple("git", [
    "clone",
    "--depth=1",
    cloneUrl,
    spawnCwd,
  ]);
  if (cloneResult.exitCode !== 0) {
    // Fold git's stderr into the message so the failure is self-diagnosing
    // (auth vs network vs DNS). Redact the installation token first — the
    // clone URL embeds it and git echoes the remote on some failures.
    // cloneResult.stderr is already trimmed by spawnSimple.
    const reason = redactToken(cloneResult.stderr, installationToken);
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}, signal ${cloneResult.signal}) for jikig-ai/soleur` +
        (reason ? `: ${reason}` : ""),
    );
  }

  const pluginsDir = join(spawnCwd, "plugins");
  const symlinkTarget = join(pluginsDir, "soleur");
  await rm(symlinkTarget, { recursive: true, force: true });
  await mkdir(pluginsDir, { recursive: true });
  await symlink(getPluginPath(), symlinkTarget);

  const claudeDir = join(spawnCwd, ".claude");
  await mkdir(claudeDir, { recursive: true });
  await writeFile(
    join(claudeDir, "settings.json"),
    JSON.stringify(DEFAULT_CLAUDE_SETTINGS, null, 2) + "\n",
    "utf-8",
  );

  const manifestPath = join(symlinkTarget, ".claude-plugin", "plugin.json");
  if (!existsSync(manifestPath)) {
    throw new Error(
      `Plugin sentinel check failed: ${manifestPath} does not exist (symlink target empty or wrong path)`,
    );
  }

  return { ephemeralRoot, spawnCwd };
}

export async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
  cronName: string,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: cronName,
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: cronName, ephemeralRoot },
    });
  }
}

export async function spawnClaudeEval(args: {
  spawnCwd: string;
  installationToken: string;
  flags: string[];
  prompt: string;
  maxTurnDurationMs: number;
  cronName: string;
  buildSpawnEnv: (token: string) => NodeJS.ProcessEnv;
  logger: HandlerArgs["logger"];
}): Promise<SpawnResult> {
  const {
    spawnCwd,
    installationToken,
    flags,
    prompt,
    maxTurnDurationMs,
    cronName,
    buildSpawnEnv,
    logger,
  } = args;

  if (!existsSync(spawnCwd)) {
    throw new Error(
      `spawn cwd ${spawnCwd} no longer exists (container restart between setup-workspace and claude-eval?). ` +
        `Re-run will re-execute setup-workspace and create a fresh ephemeral root.`,
    );
  }

  const claudeBin = resolveClaudeBin();
  const ac = new AbortController();
  const timer = setTimeout(() => ac.abort(), maxTurnDurationMs);
  const startedAt = Date.now();
  let abortedByTimeout = false;
  let exited = false;
  let escalationTimer: NodeJS.Timeout | null = null;
  // Rolling bounded tail of redacted stderr lines (last STDERR_CAP_BYTES) so a
  // non-zero exit can be surfaced to Sentry by the caller.
  let stderrTail = "";

  try {
    return await new Promise<SpawnResult>((resolve) => {
      const child = spawn(claudeBin, [...flags, prompt], {
        detached: true,
        stdio: ["ignore", "pipe", "pipe"],
        cwd: spawnCwd,
        env: buildSpawnEnv(installationToken),
      });

      if (child.stdout) {
        const rlOut = createInterface({ input: child.stdout });
        rlOut.on("line", (line) => {
          logger.info(
            { fn: cronName, stream: "stdout" },
            redactToken(line, installationToken),
          );
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          const redacted = redactToken(line, installationToken);
          logger.error({ fn: cronName, stream: "stderr" }, redacted);
          // Keep a bounded tail (drop oldest) for the Sentry surface.
          stderrTail = (stderrTail + redacted + "\n").slice(-STDERR_CAP_BYTES);
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
              // already exited between SIGTERM and escalation
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
          stderrTail,
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
          extra: { fn: cronName },
        });
        finish({
          ok: false,
          exitCode: -1,
          signal: null,
          abortedByTimeout,
          durationMs: Date.now() - startedAt,
          stderrTail: stderrTail || redactedMsg,
        });
      });

      logger.info(
        { fn: cronName, spawnCwd, pid: child.pid },
        "claude-eval spawned",
      );
    });
  } finally {
    clearTimeout(timer);
  }
}
