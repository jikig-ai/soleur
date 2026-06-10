import { execFileSync, spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { createInterface } from "node:readline";
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
  // Bounded tail of the child's stdout (redacted). `claude --print` writes its
  // max-turns notice to STDOUT, not stderr — that notice previously reached only
  // logger.info (app stdout), which Vector does NOT ship to Better Stack, so a
  // turn-exhaustion exit was red-on-the-monitor but not self-diagnosing without
  // SSH. Capturing the tail here folds the notice into the scheduled-output-missing
  // Sentry extra alongside stderrTail. #4773 (follow-up to #4714/#4770).
  // Optional, same as stderrTail: inline-spawn sibling crons do not populate it.
  stdoutTail?: string;
}

export const KILL_ESCALATION_MS = 5_000;

// Hard ceiling on captured child stderr — a pathological process must not OOM
// the worker. 8 KiB comfortably holds a git fatal: line + a few hints.
export const STDERR_CAP_BYTES = 8192;

// Hard ceiling on captured child stdout. The max-turns notice is a few hundred
// bytes; the cap is a pathological-OOM ceiling (a runaway --print could stream
// unbounded stdout), same rationale and value as STDERR_CAP_BYTES.
export const STDOUT_TAIL_CAP_BYTES = 8192;

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

// =============================================================================
// Cron containment — hook-primary deny-by-default (v3.1 / #5018, #5000, #5004)
// =============================================================================
// #5000/#5004: when the cloud runner's bwrap cannot acquire unprivileged user
// namespaces (kernel `apparmor_restrict_unprivileged_userns` drift, #4928/#4932),
// the OS bash sandbox is unavailable and every `Bash` tool call inside
// `claude --print` fails → the cron self-reports FAILED (#4978/#4988). The host
// sysctl pin (#4932) recurred 4 days later, so the durable fix removes the cron's
// dependency on unprivileged userns: `sandbox.enabled:false` (host-independent).
//
// But disabling the sandbox removes the only thing containing headless bash.
// Phase-0 probes (committed AC0 evidence; re-verified on the prod-pinned CLI
// 2.1.79) proved that with the sandbox off, headless `claude --print` does NOT
// fail-close non-allowlisted commands via `--allowedTools`/`defaultMode` — only
// an explicit `permissions.deny` rule OR a PreToolUse hook blocks, and an
// unhooked tool class / a crashed hook FAILS OPEN. (The v1 `bypassPermissions`
// approach was P1-blocked as a credential-exfil vector; that token MUST NOT
// reappear.) So containment is the deny-by-default PreToolUse hook
// (`cron-bash-allowlist-hook.mjs`), registered per-spawn under a `*` catch-all
// matcher by buildCronEvalSettings(). This base overlay is inert — the hook is
// the control. See knowledge-base/.../2026-06-08-fix-cron-sandbox-hook-primary-containment-plan.md.

// Per-cron Bash command allowlists for the containment hook. Each entry is a
// command PREFIX at sub-command granularity (`gh issue list`, NOT `gh issue`);
// the hook matches a Bash command's DEQUOTED leading verb-phrase against these
// and denies anything else (plus all secret-reads / egress / interpreters /
// substitution / argument-injection, regardless of the allowlist). A cron ABSENT
// from this map (or mapped to []) is fully fail-closed → its bash is denied → it
// self-reports FAILED → Tier-2 (egress firewall) restores it. Only crons whose
// entire command surface is a finite allowlist are Tier-1.
export const CRON_BASH_ALLOWLISTS: Record<string, string[]> = {
  "cron-roadmap-review": [
    "gh issue list",
    "gh issue view",
    "gh issue create",
    "gh issue edit",
    "gh issue close",
    "gh issue comment",
    "gh pr list",
    "gh pr create",
    "gh pr comment",
    "gh api repos/jikig-ai/soleur/",
    "gh label list",
    "gh label create",
    "git status",
    "git add",
    "git commit",
    "git checkout",
    "git switch",
    // `git push` (not `git push origin`) so flagged forms match — `git push -u
    // origin <branch>`, `git push origin HEAD`. The hook's gitVerbReason is the
    // origin-only enforcer (denies any push to a non-origin remote), so the
    // broader prefix is safe and the auto-fix-PR path (#5004 AC4c) is not
    // silently denied on its `-u` flag.
    "git push",
    "git rev-parse",
  ],
};

// Inert base overlay. `sandbox.enabled:false` = the host-independence fix;
// `defaultMode:"default"` + `allow:[]` are inert (the hook is the boundary). The
// token "bypassPermissions" MUST NOT appear here (v1 P1-blocked exfil primitive).
export const DEFAULT_CLAUDE_SETTINGS = {
  permissions: {
    allow: [] as string[],
    defaultMode: "default",
  },
  sandbox: {
    enabled: false,
  },
};

// Relative-to-spawnCwd paths inside the clone. The hook ships via the git clone
// (a tracked file) — so a Write to it is scoped to the single ephemeral run
// (and denied by the hook's own Write/Edit guard).
const HOOK_REL_PATH =
  "apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs";
const ALLOWLIST_REL_PATH = ".claude/cron-allow.txt";

// Resolve `node` by ABSOLUTE path for the hook command. Relying on PATH lookup
// risks a PATH-drift fail-open (a cron whose buildSpawnEnv trims PATH → node not
// found → hook crashes → fail-open per probe D-new-1). Mirrors resolveClaudeBin.
export function resolveNodeBin(): string {
  const override = process.env.NODE_BIN;
  if (override && existsSync(override)) return override;
  if (process.execPath && existsSync(process.execPath)) return process.execPath;
  for (const c of ["/usr/local/bin/node", "/usr/bin/node"]) {
    if (existsSync(c)) return c;
  }
  return "node";
}

// Build the per-spawn settings overlay: the inert base + the deny-by-default
// hook under a `*` catch-all matcher (so NO tool class is unhooked — an unhooked
// class fails open per probe). The hook command is `<node> <hook> <allowlist>`,
// all absolute, so it is independent of the hook's runtime CWD.
export function buildCronEvalSettings(
  spawnCwd: string,
): Record<string, unknown> {
  const command = `${resolveNodeBin()} ${join(spawnCwd, HOOK_REL_PATH)} ${join(
    spawnCwd,
    ALLOWLIST_REL_PATH,
  )}`;
  return {
    ...DEFAULT_CLAUDE_SETTINGS,
    hooks: {
      PreToolUse: [{ matcher: "*", hooks: [{ type: "command", command }] }],
    },
  };
}

// Spawn-time hook self-test (D2 — mitigates the probe D-new-1 fail-open: a
// crashed/missing/misregistered hook silently reverts to fail-open). Runs the
// hook BINARY against a canonical exfil payload (and, for a Tier-1 cron, its
// first allowed verb) BEFORE the real agent spawns, using the byte-identical
// node+hook+allowlist the real spawn uses. Throws (→ cron aborts → FAILED
// self-report) rather than letting the cron run unprotected.
export function runHookSelfTest(args: {
  spawnCwd: string;
  cronName: string;
  allow: string[];
}): void {
  const { spawnCwd, cronName, allow } = args;
  const nodeBin = resolveNodeBin();
  const hookAbs = join(spawnCwd, HOOK_REL_PATH);
  const allowlistAbs = join(spawnCwd, ALLOWLIST_REL_PATH);
  const run = (payload: object): string => {
    try {
      return execFileSync(nodeBin, [hookAbs, allowlistAbs], {
        input: JSON.stringify(payload),
        encoding: "utf-8",
        timeout: 10_000,
      });
    } catch (err) {
      // execFileSync throws on non-zero exit / missing binary → treat as a
      // self-test failure (fail-closed), not a pass.
      return `self-test-exec-error: ${(err as Error).message}`;
    }
  };
  const denied = run({
    tool_name: "Bash",
    tool_input: { command: "cat /proc/self/environ" },
  });
  if (!denied.includes('"permissionDecision":"deny"')) {
    throw new Error(
      `[${cronName}] containment hook self-test FAILED: the canonical exfil payload ` +
        `was NOT denied (hook unreachable/misconfigured → would fail-open). Aborting cron.`,
    );
  }
  if (allow.length > 0) {
    const allowed = run({
      tool_name: "Bash",
      tool_input: { command: allow[0] },
    });
    if (!allowed.includes('"permissionDecision":"allow"')) {
      throw new Error(
        `[${cronName}] containment hook self-test FAILED: allowlisted verb "${allow[0]}" ` +
          `was NOT allowed (allowlist not delivered). Aborting cron.`,
      );
    }
  }
}

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

  // #5091 — the depth-1 clone already contains the full tracked
  // plugins/soleur tree, and headless `--plugin-dir plugins/soleur` resolves
  // against it (spike-verified under a scrubbed HOME; the flag itself remains
  // required per #4993/#4987). The previous rm+symlink(getPluginPath()) swap
  // made clone-git see every tracked plugins/soleur file as DELETED on every
  // run (the #5026 destructive-PR contamination, 654 files) and routed the
  // spawned claude's plugin-docs edits to the HOST plugin dir — mutating the
  // live install and making the edits uncommittable from the clone.
  const pluginDir = join(spawnCwd, "plugins", "soleur");

  const claudeDir = join(spawnCwd, ".claude");
  await mkdir(claudeDir, { recursive: true });
  // Per-cron Bash allowlist for the containment hook (deny-all if absent → the
  // cron fail-closes and self-reports FAILED; Tier-2 restores it). Read by the
  // hook from disk; the hook also denies any tool from READING `.claude/`.
  const allow = CRON_BASH_ALLOWLISTS[cronName] ?? [];
  await writeFile(
    join(claudeDir, "cron-allow.txt"),
    allow.length ? allow.join("\n") + "\n" : "",
    "utf-8",
  );
  await writeFile(
    join(claudeDir, "settings.json"),
    JSON.stringify(buildCronEvalSettings(spawnCwd), null, 2) + "\n",
    "utf-8",
  );

  const manifestPath = join(pluginDir, ".claude-plugin", "plugin.json");
  if (!existsSync(manifestPath)) {
    throw new Error(
      `Plugin sentinel check failed: ${manifestPath} does not exist (clone incomplete or plugin tree moved)`,
    );
  }

  // D2 (mitigates probe D-new-1 fail-open): confirm the hook actually denies a
  // canonical exfil payload (and allows this cron's first verb) BEFORE any agent
  // spawns. A throw here aborts the cron → FAILED self-report, never an
  // unprotected run.
  runHookSelfTest({ spawnCwd, cronName, allow });

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
  // Rolling bounded tail of redacted stdout lines (last STDOUT_TAIL_CAP_BYTES).
  // Carries the `claude --print` max-turns notice (stdout, not stderr) to the
  // Sentry surface. #4773.
  let stdoutTail = "";

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
          const redacted = redactToken(line, installationToken);
          logger.info({ fn: cronName, stream: "stdout" }, redacted);
          // Keep a bounded tail (drop oldest) for the Sentry surface — mirrors
          // the stderrTail accumulation below. Carries the max-turns notice.
          stdoutTail = (stdoutTail + redacted + "\n").slice(-STDOUT_TAIL_CAP_BYTES);
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
          stdoutTail,
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
          // No `|| redactedMsg` fallback for stdout: a child_process spawn error
          // (ENOENT, EACCES) means the child never started, so there is no stdout
          // to capture — the error message belongs on stderrTail only. #4773.
          stdoutTail,
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
