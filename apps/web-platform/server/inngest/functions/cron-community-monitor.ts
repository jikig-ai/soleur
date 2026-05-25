// TR9 PR-11 (closes #4468) — Migrated from the GHA
// scheduled-community-monitor workflow (deleted in the same PR per TR9
// I-13 hygiene). Sixth handler ported via the claude-code-spawn pattern;
// structural template is PR-7's cron-roadmap-review.ts.
//
// BUCKET II (kb-writer + pr-creator) — first bucket-ii migration in the
// claude-code-spawn cohort. CLO bucket-ii means more careful authorization
// context: the spawned agent can create branches, commit to them, open PRs,
// and create issues. The buildSpawnEnv allowlist is wider than bucket-i
// (adds 7 community-platform vars for Discord, Bluesky, LinkedIn) but
// still uses the explicit-allowlist shape (NOT denylist / spread).
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
// NAME NOTE: Sentry monitor slug "scheduled-community-monitor" pre-exists
// from the GHA era (apps/web-platform/infra/sentry/cron-monitors.tf). This
// PR mutates the resource in place (margin 60→30, runtime 10→55).
//
// SHAPE DIFF vs PR-7 cron-roadmap-review.ts:
//   - buildSpawnEnv is WIDER: adds DISCORD_WEBHOOK_URL, DISCORD_BOT_TOKEN,
//     DISCORD_GUILD_ID, BSKY_HANDLE, BSKY_APP_PASSWORD, LINKEDIN_ACCESS_TOKEN,
//     LINKEDIN_PERSON_URN (the community-router.sh platform scripts need
//     these to flip platforms from "disabled" → "enabled").
//   - --max-turns 50 (was 40); --allowedTools is NARROWER (no WebSearch,
//     WebFetch — mirrors the YAML's claude_args).
//   - Cron 0 8 * * * (daily 08:00 UTC, not weekly Monday 09:00).
//   - DEDUP RULE uses 24h window (daily cadence) not 6 days (weekly).
//   - ISSUE CLOSURE SAFETY and ROADMAP.MD CONFLICT GUARD are N/A (prompt
//     has zero `gh issue close` calls and zero roadmap.md references).
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

const SENTRY_MONITOR_SLUG = "scheduled-community-monitor";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export const KILL_ESCALATION_MS = 5_000;

const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8.
// Mirrors .github/workflows/scheduled-community-monitor.yml `claude_args`:
//   --model claude-sonnet-4-6
//   --max-turns 50
//   --allowedTools Bash,Read,Write,Edit,Glob,Grep
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-sonnet-4-6",
  "--max-turns",
  "50",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep",
  "--",
];

// Verbatim prompt extracted from
// .github/workflows/scheduled-community-monitor.yml lines 92-168 (the
// `prompt: |` block body, 12-space YAML indentation stripped).
// Verbatim-extraction discipline: anchor strings asserted by the test
// suite (cron-community-monitor.test.ts) to catch silent paraphrasing
// across plan→work cycles.
const COMMUNITY_MONITOR_PROMPT = `You are a community monitoring agent. Your job is to generate a daily
community digest and create a GitHub Issue summarizing the findings.

IMPORTANT: This is an automated CI workflow. The AGENTS.md rule
Do NOT push directly to main.
Use the PR-based commit pattern in the MANDATORY FINAL STEP.

MILESTONE RULE: Every gh issue create command must include --milestone "Post-MVP / Later".

## Instructions

1. **Detect platforms** using the community router:
   Run: bash plugins/soleur/skills/community/scripts/community-router.sh platforms
   This shows which platforms are enabled/disabled. If only GitHub and HN
   are enabled (no Discord or X), create a GitHub Issue titled
   "[Scheduled] Community Monitor - FAILED" with label
   "scheduled-community-monitor" explaining the misconfiguration, then stop.

2. **Collect data** from enabled platforms. IMPORTANT: batch commands
   into as few Bash calls as possible to conserve turns. Use \`;\` (not
   \`&&\`) to chain commands so failures don't halt the batch.
   Set: ROUTER="plugins/soleur/skills/community/scripts/community-router.sh"
   Batch 1 (Discord + X + Bluesky — single Bash call):
   - Discord (if enabled): \`bash $ROUTER discord guild-info; bash $ROUTER discord members; bash $ROUTER discord channels\`
     Then one more call to fetch messages for each channel ID from the output above.
   - X/Twitter (if enabled): append \`bash $ROUTER x fetch-metrics\` to the same call.
     Do NOT call fetch-mentions or fetch-timeline (403 on Free tier).
   - Bluesky (if enabled): append \`bash $ROUTER bsky get-metrics\` to the same call.
   - LinkedIn (if enabled): skip — log "enabled (posting only)".
   Batch 2 (GitHub + HN — single Bash call):
   - \`bash $ROUTER github activity 1; bash $ROUTER github contributors 1; bash $ROUTER github discussions 1; bash $ROUTER github repo-stats 1; bash $ROUTER github fetch-interactions 1; bash $ROUTER hn mentions --query soleur --limit 20; bash $ROUTER hn trending --limit 30\`
   If any command in a batch fails, log the error and continue.

3. **Read brand guide** at knowledge-base/marketing/brand-guide.md (section ## Voice)
   before writing any content. Match the brand voice in the digest.

4. **Generate digest** and write to knowledge-base/support/community/YYYY-MM-DD-digest.md
   (use today's date). Follow the digest file contract from the community-manager
   agent: frontmatter with period_start/period_end/generated_at, then sections
   ## Period, ## Activity Summary, ## Top Contributors, and optional sections
   ## Trending Topics, ## GitHub Activity, ## X/Twitter Metrics,
   ## Bluesky Metrics, ## LinkedIn Activity, ## Hacker News Activity.
   The ## GitHub Activity section must include a **Repository Stats** sub-section
   with a table showing Stars, Forks, and Watchers counts, plus a list of
   new stargazers in the period (username and starred date) from the repo-stats data.
   If fetch-interactions returned any interactions, include a **Community Interactions**
   sub-section with a markdown table: | User | Issue/PR | Comment |. Each row shows
   the commenter, a link to the issue (e.g., #123), and a snippet of their comment.
   Omit this sub-section entirely if there are no external interactions.
   Summarize and aggregate -- do not store raw message transcripts. Brief
   contextual quotes (under 100 chars) with attribution are acceptable.
   If the file already exists for today, overwrite it.

5. **Persist via PR** (do not push directly to main):
   Run these bash commands:
   \\\`\\\`\\\`
   git config user.name "github-actions[bot]"
   git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
   git add knowledge-base/support/community/
   git diff --cached --quiet && echo "No changes to commit" && exit 0
   BRANCH="ci/community-digest-$(date -u +%Y-%m-%d-%H%M%S)"
   git checkout -b "$BRANCH"
   git commit -m "docs: daily community digest"
   git push -u origin "$BRANCH"
   gh pr create \\
     --title "docs: daily community digest $(date -u +%Y-%m-%d)" \\
     --body "Automated daily community digest commit." \\
     --base main \\
     --head "$BRANCH"
   gh pr merge "$BRANCH" --squash --auto
   \\\`\\\`\\\`

6. **Create GitHub Issue** titled "[Scheduled] Community Monitor - YYYY-MM-DD"
   with label "scheduled-community-monitor". Include a condensed summary:
   platform status, key metrics, notable items, and a link to the digest file.

DEDUP RULE (BEFORE creating the monitor issue): run
  gh issue list --label scheduled-community-monitor --state open --search 'Community Monitor in:title' --json number,title,createdAt
If any results from within the last 24 hours exist, do NOT create a new issue. Instead, post your findings as a comment on the most recent existing issue and exit. This prevents duplicate issues when a manual trigger fires the same day as the natural 08:00 UTC cron.

CLONE DEPTH RULE: This workspace was cloned with --depth=1. Do NOT use \\\`git log\\\` for staleness analysis (every file appears "just touched"). Use GitHub Issue/PR \\\`updatedAt\\\` timestamps via \\\`gh api\\\` instead.
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
// Helpers
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

// Spawn-env allowlist (NOT a denylist). PR-5 base shape + PR-11 community-
// monitor additions. The keys below are the COMPLETE set the spawned claude
// is allowed to see; anything not listed (notably RESEND_API_KEY, SENTRY_*,
// DOPPLER_*, GITHUB_APP_PRIVATE_KEY, SUPABASE_SERVICE_ROLE_KEY,
// INNGEST_SIGNING_KEY, INNGEST_EVENT_KEY, STRIPE_SECRET_KEY) is excluded.
//
// PR-11 additions (bucket-ii authorization): DISCORD_WEBHOOK_URL,
// DISCORD_BOT_TOKEN, DISCORD_GUILD_ID, BSKY_HANDLE, BSKY_APP_PASSWORD,
// LINKEDIN_ACCESS_TOKEN, LINKEDIN_PERSON_URN — the community-router.sh
// platform scripts need these to flip platforms from "disabled" → "enabled".
// Defensive: ONLY the platform secrets the community-router.sh needs, NOT a
// wholesale process.env passthrough.
function buildSpawnEnv(installationToken: string): NodeJS.ProcessEnv {
  return {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
    GH_TOKEN: installationToken,
    DISCORD_WEBHOOK_URL: process.env.DISCORD_WEBHOOK_URL,
    DISCORD_BOT_TOKEN: process.env.DISCORD_BOT_TOKEN,
    DISCORD_GUILD_ID: process.env.DISCORD_GUILD_ID,
    BSKY_HANDLE: process.env.BSKY_HANDLE,
    BSKY_APP_PASSWORD: process.env.BSKY_APP_PASSWORD,
    LINKEDIN_ACCESS_TOKEN: process.env.LINKEDIN_ACCESS_TOKEN,
    LINKEDIN_PERSON_URN: process.env.LINKEDIN_PERSON_URN,
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

async function setupEphemeralWorkspace(
  installationToken: string,
): Promise<{ ephemeralRoot: string; spawnCwd: string }> {
  const ephemeralRoot = await mkdtemp(
    join(tmpdir(), "soleur-cron-community-monitor-"),
  );
  const spawnCwd = join(ephemeralRoot, "repo");

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

async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-community-monitor",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-community-monitor", ephemeralRoot },
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
      const child = spawn(
        claudeBin,
        [...CLAUDE_CODE_FLAGS, COMMUNITY_MONITOR_PROMPT],
        {
          detached: true,
          stdio: ["ignore", "pipe", "pipe"],
          cwd: spawnCwd,
          env: buildSpawnEnv(installationToken),
        },
      );

      if (child.stdout) {
        const rlOut = createInterface({ input: child.stdout });
        rlOut.on("line", (line) => {
          logger.info(
            { fn: "cron-community-monitor", stream: "stdout" },
            redactToken(line, installationToken),
          );
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          logger.error(
            { fn: "cron-community-monitor", stream: "stderr" },
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
        const redactedMsg = redactToken(err.message ?? "", installationToken);
        const redacted = new Error(redactedMsg);
        redacted.name = err.name;
        reportSilentFallback(redacted, {
          feature: "cron-claude-eval",
          op: "child_process.spawn",
          message: "claude-code spawn failed",
          extra: { fn: "cron-community-monitor" },
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
          fn: "cron-community-monitor",
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
      { fn: "cron-community-monitor" },
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
      { fn: "cron-community-monitor" },
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
        fn: "cron-community-monitor",
        status,
        aborted: e.name === "TimeoutError",
      },
    });
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronCommunityMonitorHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken();
    },
  );

  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace(installationToken);
    });
    ephemeralRoot = workspace.ephemeralRoot;
    spawnCwd = workspace.spawnCwd;
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-community-monitor",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-community-monitor" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, logger });
    });
    return { ok: false };
  }

  try {
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
          feature: "cron-community-monitor",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-community-monitor",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: spawnResult.ok, logger });
    });

    return { ok: spawnResult.ok };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-community-monitor",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-community-monitor", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 8 * * * UTC — daily 08:00) + manual
// operator event `cron/community-monitor.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1 / PR-4 / PR-5 precedent).

export const cronCommunityMonitor = inngest.createFunction(
  {
    id: "cron-community-monitor",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 8 * * *" },
    { event: "cron/community-monitor.manual-trigger" },
  ],
  cronCommunityMonitorHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
