// TR9 PR-7 (closes #4425) — Migrated from the GHA scheduled-roadmap-review
// workflow (deleted in the same PR per TR9 I-13 hygiene). Second handler
// ported via the claude-code-spawn pattern; structural template is PR-5's
// cron-bug-fixer.ts (PR-6 used the alternate pure-TS pattern).
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
// NAME NOTE: Sentry monitor slug "scheduled-roadmap-review" is NEW — the
// GHA predecessor had NO Sentry check-in (it ran on GHA's runner pool).
// The new Terraform resource sentry_cron_monitor.scheduled_roadmap_review
// is added in the same PR (apps/web-platform/infra/sentry/cron-monitors.tf).
//
// SHAPE DIFF vs PR-5 cron-bug-fixer.ts:
//   - NO auto-merge gate (this handler does roadmap hygiene, not bug-fix
//     PR auto-merge).
//   - NO ops-email notification (no Resend POST).
//   - NO priority cascade / issue-selection (prompt operates over live
//     issue set; no per-issue TS-side filter).
//   - NO manual-trigger payload parsing (workflow_dispatch carried no
//     inputs; manual trigger event is fire-and-forget).
//   - --max-turns 40 (was 55); --allowedTools adds WebSearch,WebFetch
//     (mirrors the YAML's claude_args).
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

const SENTRY_MONITOR_SLUG = "scheduled-roadmap-review";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry.
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// Repo coordinates. Aligned with createProbeOctokit's PROBE_ISSUE_OWNER /
// PROBE_ISSUE_REPO constants (NOT re-exported here to keep this file
// self-contained against probe-octokit module shape).
const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

// 50 min wall-clock budget. Math: 50min / 40turns = 1.25 min/turn,
// comfortably above the 0.75 min/turn floor. Exported for test parity
// (cron-roadmap-review.test.ts imports to avoid hard-coded timing drift
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
// Mirrors .github/workflows/scheduled-roadmap-review.yml `claude_args`:
//   --model claude-sonnet-4-6
//   --max-turns 40
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-sonnet-4-6",
  "--max-turns",
  "40",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,WebSearch,WebFetch",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-roadmap-review.yml lines 61-108 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings ("Part 1: Issue-to-
// Milestone Alignment", "Part 2: Bidirectional Integrity Gate",
// "MILESTONE RULE:", "BIDIRECTIONAL RULE:") asserted by the test suite
// to catch silent paraphrasing across plan→work cycles.
const ROADMAP_REVIEW_PROMPT = `You are the CPO performing a weekly roadmap consistency review.

## Part 1: Issue-to-Milestone Alignment

1. Read knowledge-base/product/roadmap.md
2. Fetch all GitHub milestones (open and closed): gh api 'repos/jikig-ai/soleur/milestones?state=all&per_page=100' --jq '.[] | {number, title, state, open_issues, closed_issues}'
3. Fetch all open issues with milestones: gh api 'repos/jikig-ai/soleur/issues?state=open&per_page=100' --paginate --jq '.[] | {number, title, milestone: .milestone.title}'
4. For each open issue, check:
   - Is it assigned to the correct milestone per the roadmap?
   - Is it stale (superseded by roadmap decisions, no activity in 30+ days, references deprecated features)?
   - Does it have a priority label that matches its phase placement?

## Part 2: Bidirectional Integrity Gate (milestones <-> issues)

5. For each roadmap phase table, check:
   - Does EVERY feature row have a linked GitHub issue in the Issue column?
   - Does that issue actually exist and is it in the correct milestone?
   - If an issue is missing, flag it as MISSING_ISSUE
6. For each open milestone, check:
   - Does it have at least one open issue? An open milestone with 0 open issues is either stale (should be closed) or incomplete (features defined but no issues created)
   - Flag empty milestones as EMPTY_MILESTONE
7. For each roadmap feature status, check:
   - Does the status column match the actual issue state? (e.g., "Not started" but issue is closed = stale status)
   - Flag mismatches as STALE_STATUS

## Rules

MILESTONE RULE: Every gh issue create command must include --milestone.
Use --milestone "Post-MVP / Later" for operational/maintenance issues.
For feature issues, read knowledge-base/product/roadmap.md for available milestones and assign the one matching the relevant phase.

BIDIRECTIONAL RULE: Every feature in a roadmap phase table MUST have a linked GitHub issue. Every milestone MUST have at least one issue. These are both enforced -- violations are flagged as high severity.

CLONE DEPTH RULE: This workspace was cloned with --depth=1. Do NOT use \`git log\` for staleness analysis (every file appears "just touched"). Use GitHub Issue/PR \`updatedAt\` timestamps via \`gh api\` instead.

ISSUE CLOSURE SAFETY: BEFORE closing or reassigning ANY issue:
  (a) record the original state (milestone, labels, last activity) in your PR description so it is auditable;
  (b) only close issues with NO activity (no comments, no commits referencing the issue) in the last 14 days;
  (c) NEVER close issues with the labels \`in-progress\`, \`wip\`, \`auto-merge\`, or any priority label \`priority/p0-critical\`, \`priority/p1-high\`. Skip and flag for human review instead.

ROADMAP.MD CONFLICT GUARD: BEFORE editing knowledge-base/product/roadmap.md, run:
  gh pr list --state open --search 'roadmap.md in:files' --json number,title,headRefName
If any open PR touches roadmap.md, do NOT make conflicting edits. Instead, post a comment on that PR with your suggested updates and skip the roadmap.md edit in your own PR.

## Output

After your analysis, create a GitHub issue summarizing your findings.

DEDUP RULE (BEFORE creating the review issue): run
  gh issue list --label scheduled-roadmap-review --state open --search 'Weekly Roadmap Review in:title' --json number,title,createdAt
If any results from within the last 6 days exist, do NOT create a new issue. Instead, post your findings as a comment on the most recent existing issue and exit. This prevents duplicate issues when a manual trigger fires the same week as the natural Monday 09:00 UTC cron.

If no recent duplicate exists, create a new issue with:
- Title format: [Scheduled] Weekly Roadmap Review - YYYY-MM-DD
- Label: scheduled-roadmap-review
- --milestone "Post-MVP / Later"

The issue body should contain:
- Health summary: X consistent, Y inconsistent, Z stale, W missing
- Bidirectional gate results: empty milestones, missing issues, stale statuses
- Recommended actions table (close, move, create, relabel)
- Any roadmap.md updates needed
- Audit log: list of issues you closed/reassigned with original state captured (per ISSUE CLOSURE SAFETY (a))

If inconsistencies are found that can be fixed automatically (milestone reassignment, stale issue closure, roadmap status updates),
create a branch, apply the fixes, and open a PR. If only the review issue is needed, skip the PR.
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
    join(tmpdir(), "soleur-cron-roadmap-review-"),
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
      feature: "cron-roadmap-review",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-roadmap-review", ephemeralRoot },
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
        [...CLAUDE_CODE_FLAGS, ROADMAP_REVIEW_PROMPT],
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
            { fn: "cron-roadmap-review", stream: "stdout" },
            redactToken(line, installationToken),
          );
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          logger.error(
            { fn: "cron-roadmap-review", stream: "stderr" },
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
          extra: { fn: "cron-roadmap-review" },
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
          fn: "cron-roadmap-review",
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
      { fn: "cron-roadmap-review" },
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
      { fn: "cron-roadmap-review" },
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
        fn: "cron-roadmap-review",
        status,
        aborted: e.name === "TimeoutError",
      },
    });
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronRoadmapReviewHandler({
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
      feature: "cron-roadmap-review",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-roadmap-review" },
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
          feature: "cron-roadmap-review",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-roadmap-review",
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
        feature: "cron-roadmap-review",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-roadmap-review", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 9 * * 1 UTC — weekly Monday 09:00) + manual
// operator event `cron/roadmap-review.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1 / PR-4 / PR-5 precedent).

export const cronRoadmapReview = inngest.createFunction(
  {
    id: "cron-roadmap-review",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 9 * * 1" },
    { event: "cron/roadmap-review.manual-trigger" },
  ],
  cronRoadmapReviewHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
