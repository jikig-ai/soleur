// TR9 PR-9 (closes #4442) — Migrated from the GHA scheduled-agent-native-audit
// workflow (deleted in the same PR per TR9 I-13 hygiene). Fourth handler
// ported via the claude-code-spawn pattern; structural template is PR-7's
// cron-roadmap-review.ts (global-state prompt, no per-entity factory).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — claude binary spawned INSIDE step.run (Inngest replay memoization).
//   I2 — Operator ANTHROPIC_API_KEY only; never founder BYOK. Enforced at
//        build time by test/server/cron-no-byok-lease-sweep.test.ts.
//   I3 — AbortSignal aborts at MAX_TURN_DURATION_MS (50 min). Manual
//        SIGTERM→SIGKILL escalation via process-group kill (detached:true).
//   I4 — claude binary resolved at spawn time via filesystem checks; the
//        CLAUDE_BIN env var is the override hatch for fresh-host bootstraps.
//   I5 — Deterministic step.run return shape: {ok, exitCode, signal,
//        abortedByTimeout, durationMs}. stdout is NOT captured.
//   I6 — Event payloads emitted by cron-*.ts MUST carry actor: "platform".
//        (This handler emits none.)
//
// NAME NOTE: Sentry monitor slug "scheduled-agent-native-audit" is NEW —
// the GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
// The new Terraform resource sentry_cron_monitor.scheduled_agent_native_audit
// is added in the same PR (apps/web-platform/infra/sentry/cron-monitors.tf).
//
// SHAPE DIFF vs PR-7 cron-roadmap-review.ts:
//   - --max-turns 50 (was 40) — agent-native-audit launches 8 principle
//     sub-agents via the Task tool, each with their own turn budget; 50
//     outer turns is the per-skill envelope.
//   - --allowedTools adds Task (for sub-agent dispatch); drops WebSearch
//     and WebFetch (audit is purely codebase-introspection).
//   - --model claude-opus-4-7 (was sonnet-4-6) — the principle scoring is
//     opus-class reasoning, mirroring scheduled-bug-fixer's escalation.
//   - Cadence: monthly 15th 09:00 UTC (was weekly Monday).
//   - Skip-window: 30 days (was 6) — monthly cadence + stable findings
//     warrant a 30-day reopen-loop guard.
//   - Prompt body: agent-native-audit skill invocation with 8-sub-agent
//     dispatch + CAP_OPEN_ISSUES=20 / CAP_PER_RUN=5 cap-enforcement.
//
// PLUGIN-LOADING — Verbatim PR-5 ephemeral-workspace pattern:
//   - repo/                          (in-handler `git clone --depth=1`)
//   - repo/plugins/soleur            (symlink to getPluginPath())
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// Plugin resolution is cwd-relative — the soleur plugin manifest at
// plugins/soleur/.claude-plugin/plugin.json is discovered from spawn cwd.
//
// GH TOKEN — installation token minted via createProbeOctokit() →
// installation discovery → generateInstallationToken(installation.id).
// Injected as GH_TOKEN so the spawned claude can run `gh api ...`,
// `gh issue create`, `gh pr create`, `gh label create`, `git push`.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
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

const SENTRY_MONITOR_SLUG = "scheduled-agent-native-audit";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// Repo coordinates. Aligned with createProbeOctokit's PROBE_ISSUE_OWNER /
// PROBE_ISSUE_REPO constants (NOT re-exported here to keep this file
// self-contained against probe-octokit module shape).
const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

// 50 min wall-clock budget. Math: 50min / 50turns = 1.0 min/turn,
// comfortably above the 0.75 min/turn floor. Exported for test parity
// (cron-agent-native-audit.test.ts imports to avoid hard-coded timing drift
// across SUT tuning).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export const KILL_ESCALATION_MS = 5_000;

// Sentry URL component validators (PR-1 / PR-4 / PR-5 shape). A typo in
// Doppler (e.g., SENTRY_INGEST_DOMAIN="ingest.sentry.io/x?leak=") would
// otherwise produce a partially-attacker-controllable URL since the
// components are interpolated raw into the heartbeat fetch.
const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
//
// Mirrors .github/workflows/scheduled-agent-native-audit.yml `claude_args`:
//   --model claude-opus-4-7
//   --max-turns 50
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep,Task
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-opus-4-7",
  "--max-turns",
  "50",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Task",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-agent-native-audit.yml lines 80-112 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings ("Run /soleur:agent-native-audit",
// "CAP_OPEN_ISSUES = 20", "CAP_PER_RUN     = 5", "[Scheduled] Agent-Native Audit",
// "8 principle sub-agents") asserted by the test suite to catch silent
// paraphrasing across plan→work cycles.
const AGENT_NATIVE_AUDIT_PROMPT = `IMPORTANT: This is an automated CI workflow. Do NOT push directly
to main. Do NOT create commits.

MILESTONE RULE: Every gh issue create command MUST include
--milestone "Post-MVP / Later".

Run /soleur:agent-native-audit on this repository. Each of the 8
principle sub-agents produces a scored finding; collect findings
into a structured list before filing.

Cap enforcement is mandatory:
  CAP_OPEN_ISSUES = 20   (refuse to file when reached; check via
                          \`gh issue list --label scheduled-agent-native-audit
                           --state open --limit 30 | wc -l\`)
  CAP_PER_RUN     = 5    (severity-ranked top-N filed per run)

For each filed issue:
  - Title prefix: "[Scheduled] Agent-Native Audit — <principle>: <gap>"
  - Labels: scheduled-agent-native-audit
  - Milestone: "Post-MVP / Later"
  - Body: principle name, score, specific gap, recommendation,
    referenced files

Idempotency: before filing, check
  gh issue list --label scheduled-agent-native-audit \\
                --search "<gap-summary> in:title" --state all --limit 5
and skip if any existing issue (open or closed within 30 days)
matches. Prevents reopen-loops on stable findings.

Injection safety: write each finding's title and body to env vars
or files BEFORE \`gh issue create\` — never interpolate agent output
into bash \`run:\` commands directly.
`;

// .claude/settings.json overlay — mirrors DEFAULT_SETTINGS from workspace.ts.
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
// Helpers
// =============================================================================

// Resolve the `claude` binary lazily inside the spawning step.run (NOT at
// module load) — see PR-1 cron-daily-triage.ts header for the full
// `require.resolve` → filesystem-check refactor rationale (#4017 bug 8/8).
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

// Spawn-env allowlist (NOT a denylist). PR-5 shape verbatim — the keys
// below are the COMPLETE set the spawned claude is allowed to see;
// anything not listed (notably RESEND_API_KEY, SENTRY_*, DOPPLER_*,
// GITHUB_APP_PRIVATE_KEY) is excluded.
function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
  };
}

// Build the authenticated clone URL. NEVER log this string — it contains
// the installation token inline. Mask via the helper below for any
// diagnostic emission.
function buildAuthenticatedCloneUrl(token: string): string {
  return `https://x-access-token:${token}@github.com/${REPO_OWNER}/${REPO_NAME}.git`;
}

// Redact the installation token from a string before emitting it to
// observability sinks. Defense-in-depth: callers are expected to NOT
// include the cloneUrl at all, but if they do, this prevents token bytes
// from reaching Sentry / pino.
function redactToken(s: string, token: string): string {
  if (!token) return s;
  return s.replaceAll(token, "[REDACTED-INSTALLATION-TOKEN]");
}

// Mint a fresh installation token with a lifetime floor that exceeds the
// claude-eval wall-clock budget (TR9 PR-5 security HIGH-1). Without the
// `minRemainingMs` guard, a warm cache entry minted ~50 min ago could be
// returned with <14 min remaining, expiring mid-spawn → auth failures
// inside the agent's gh CLI calls and git push.
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

// Spawn a child process and resolve with its exit status. Used for `git
// clone` (no abort budget) — separate from the claude-eval spawn which
// has the 50-min AbortController envelope.
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

// Scaffold the ephemeral workspace: clone repo, symlink plugin, write
// settings overlay, sentinel-check the plugin manifest. Returns the path
// to the cloned repo (the spawn cwd for claude-eval).
async function setupEphemeralWorkspace(
  installationToken: string,
): Promise<{ ephemeralRoot: string; spawnCwd: string }> {
  const ephemeralRoot = await mkdtemp(
    join(tmpdir(), "soleur-cron-agent-native-audit-"),
  );
  const spawnCwd = join(ephemeralRoot, "repo");

  // 1. git clone --depth=1 (token in URL is NEVER logged)
  const cloneUrl = buildAuthenticatedCloneUrl(installationToken);
  const cloneResult = await spawnSimple("git", [
    "clone",
    "--depth=1",
    cloneUrl,
    spawnCwd,
  ]);
  if (cloneResult.exitCode !== 0) {
    // DO NOT include cloneUrl in the error message — it contains the token.
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}, signal ${cloneResult.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }

  // 2. plugin symlink: repo/plugins/soleur → getPluginPath()
  // The cloned repo already has plugins/soleur as a real directory (it's
  // tracked in the repo). Remove the cloned directory and replace with
  // a symlink to the deployed plugin tree so claude-code resolves the
  // installed plugin version (NOT the freshly-cloned source).
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

  // 4. Sentinel check: the plugin manifest MUST exist via the symlink.
  // Catches the silent-failure shape where the symlink points at an empty
  // /app/shared/plugins/soleur (post-deploy seed gap, #3045).
  const manifestPath = join(symlinkTarget, ".claude-plugin", "plugin.json");
  if (!existsSync(manifestPath)) {
    throw new Error(
      `Plugin sentinel check failed: ${manifestPath} does not exist (symlink target empty or wrong path)`,
    );
  }

  return { ephemeralRoot, spawnCwd };
}

// Best-effort teardown of the ephemeral workspace. Failures are mirrored
// to Sentry but never propagated — a stranded /tmp dir is acceptable
// degraded state, throwing here would mask the upstream result.
async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-agent-native-audit",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-agent-native-audit", ephemeralRoot },
    });
  }
}

// =============================================================================
// Claude-eval spawn (50-min AbortController + SIGTERM→SIGKILL escalation)
// =============================================================================

async function spawnClaudeEval(args: {
  spawnCwd: string;
  installationToken: string;
  logger: HandlerArgs["logger"];
}): Promise<SpawnResult> {
  const { spawnCwd, installationToken, logger } = args;
  // Defensive re-check: setup-workspace is memoized across Inngest replays,
  // so the workspace path could be stale if the container restarted between
  // setup and claude-eval. If it's missing, surface a typed error rather
  // than letting `spawn` fail with a confusing ENOENT on cwd.
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

  try {
    return await new Promise<SpawnResult>((resolve) => {
      // stdio: pipe (NOT inherit) so we can redact the installation token
      // from any output line BEFORE it reaches the parent's stdout/stderr
      // and is scraped into centralized logs (PR-5 security HIGH-2 —
      // prompt-injected `claude` could `echo $GH_TOKEN` / `env`).
      const child = spawn(
        claudeBin,
        [...CLAUDE_CODE_FLAGS, AGENT_NATIVE_AUDIT_PROMPT],
        {
          detached: true,
          stdio: ["ignore", "pipe", "pipe"],
          cwd: spawnCwd,
          env: buildSpawnEnv(installationToken),
        },
      );

      // Stream stdout/stderr line-by-line through the redactor. Lines are
      // emitted to logger.info (stdout) / logger.error (stderr) so they
      // still land in centralized logs — with the token bytes stripped.
      if (child.stdout) {
        const rlOut = createInterface({ input: child.stdout });
        rlOut.on("line", (line) => {
          logger.info(
            { fn: "cron-agent-native-audit", stream: "stdout" },
            redactToken(line, installationToken),
          );
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          logger.error(
            { fn: "cron-agent-native-audit", stream: "stderr" },
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
              // already exited between SIGTERM and the 5s escalation
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
        // Redact installation token from any error message (defense-in-depth;
        // child_process spawn errors typically don't include argv/env, but
        // the redaction is cheap insurance).
        const redactedMsg = redactToken(err.message ?? "", installationToken);
        const redacted = new Error(redactedMsg);
        redacted.name = err.name;
        reportSilentFallback(redacted, {
          feature: "cron-claude-eval",
          op: "child_process.spawn",
          message: "claude-code spawn failed",
          extra: { fn: "cron-agent-native-audit" },
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
        {
          fn: "cron-agent-native-audit",
          spawnCwd,
          pid: child.pid,
        },
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
    logger.info(
      { fn: "cron-agent-native-audit" },
      "Sentry env unset — skipping heartbeat",
    );
    return;
  }
  if (
    !SENTRY_DOMAIN_RE.test(domain) ||
    !SENTRY_PROJECT_RE.test(projectId) ||
    !SENTRY_PUBLIC_KEY_RE.test(publicKey)
  ) {
    logger.warn(
      { fn: "cron-agent-native-audit" },
      "Sentry env malformed — skipping heartbeat",
    );
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
      extra: {
        fn: "cron-agent-native-audit",
        status,
        aborted: e.name === "TimeoutError",
      },
    });
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronAgentNativeAuditHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  // --- Step 1: mint installation token (memoized across replays) ---
  // The raw token string is the return value (NEVER log this value).
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken();
    },
  );

  // --- Step 2: setup ephemeral workspace (clone + symlink + sentinel) ---
  // Track ephemeralRoot in handler-scope so teardown runs regardless of
  // downstream success/failure.
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace(installationToken);
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    // Redact token if it sneaks into the error message (defense-in-depth).
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-agent-native-audit",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-agent-native-audit" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, logger });
    });
    return { ok: false };
  }

  // Wrap the entire post-setup pipeline in try/finally so the ephemeral
  // workspace is torn down even if claude-eval throws at the Inngest step
  // boundary. The teardown side-effect outside step.run is acceptable
  // because rm {recursive:true, force:true} is idempotent — a replay
  // re-creates a fresh ephemeralRoot from setup-workspace's memoization
  // (or the existsSync guard at the top of spawnClaudeEval rebuilds it).
  try {
    // --- Step 3: claude-eval (50-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
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
          feature: "cron-agent-native-audit",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-agent-native-audit",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 4: sentry-heartbeat (final POST) ---
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: spawnResult.ok, logger });
    });

    return { ok: spawnResult.ok };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-agent-native-audit",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-agent-native-audit", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 9 15 * * UTC — monthly 15th 09:00) + manual
// operator event `cron/agent-native-audit.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1 / PR-4 / PR-5 precedent).

export const cronAgentNativeAudit = inngest.createFunction(
  {
    id: "cron-agent-native-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 15 * *" },
    { event: "cron/agent-native-audit.manual-trigger" },
  ],
  cronAgentNativeAuditHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
