// TR9 PR-5 (closes #4376) — Migrated from the GHA scheduled-bug-fixer
// workflow (deleted in the same PR per TR9 I-13 hygiene).
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
// NAME NOTE: Sentry monitor slug "scheduled-bug-fixer" is NEW — the GHA
// predecessor had NO Sentry check-in (it ran on GHA's runner pool). The
// new Terraform resource sentry_cron_monitor.scheduled_bug_fixer is added
// in the same PR (apps/web-platform/infra/sentry/cron-monitors.tf).
//
// PLUGIN-LOADING (Q1, AC6) — unique to this cron function. The handler
// scaffolds an ephemeral workspace at /tmp/soleur-cron-bug-fixer-<X>/
// containing:
//   - repo/                          (in-handler `git clone --depth=1`)
//   - repo/plugins/soleur            (symlink to getPluginPath())
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// The spawn cwd is repo/ so that:
//   (a) claude-code's plugin discovery (cwd-relative) finds the soleur
//       plugin manifest at plugins/soleur/.claude-plugin/plugin.json;
//   (b) the fix-issue skill's worktree-manager.sh has a real git repo
//       to create worktrees against. Clone is done in-handler (vs.
//       relying on a pre-seeded repo path) because Hetzner has no
//       checked-out repo tree at deploy time per Phase 0 verification.
//
// GH TOKEN (Q2, AC5) — installation token minted via createProbeOctokit()
// → installation discovery → generateInstallationToken(installation.id).
// Injected as GH_TOKEN in buildSpawnEnv() so the spawned claude can run
// `gh issue view`, `gh pr create`, `gh pr edit`, etc. The token's value
// is also used to construct the `git clone` URL — that URL is NEVER
// logged or surfaced to reportSilentFallback to prevent token leak.
//
// AUTO-MERGE GATE (AC13, AC14) — synchronous step.run after detect-pr.
// Three safety nets (bot-identity, single-file diff, p3-low source) +
// label assertion (`bot-fix/auto-merge-eligible`). On all checks passing,
// fires `enablePullRequestAutoMerge` GraphQL mutation with mergeMethod:
// SQUASH. Idempotent under Inngest replay (mutation returns same
// enabledAt on second call).

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createInterface } from "node:readline";
import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import { getPluginPath } from "@/server/plugin-path";
import { reportSilentFallback } from "@/server/observability";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-bug-fixer";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;
const RESEND_TIMEOUT_MS = 10_000;

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry
// (TR9 PR-5 security HIGH-1 — token expiry race vs. spawn budget).
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// Repo coordinates. Aligned with createProbeOctokit's PROBE_ISSUE_OWNER /
// PROBE_ISSUE_REPO constants (NOT re-exported here to keep this file
// self-contained against probe-octokit module shape).
const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

// 50 min wall-clock budget. Math: 50min / 55turns = 0.91 min/turn,
// comfortably above the 0.75 min/turn floor (Architecture-strategist F2,
// PR-1 header). Exported for test parity (cron-bug-fixer.test.ts imports
// to avoid hard-coded timing drift across SUT tuning).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export const KILL_ESCALATION_MS = 5_000;

// Sentry URL component validators (PR-1 / PR-4 shape). A typo in Doppler
// (e.g., SENTRY_INGEST_DOMAIN="ingest.sentry.io/x?leak=") would otherwise
// produce a partially-attacker-controllable URL since the components are
// interpolated raw into the heartbeat fetch.
const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

// 5 bot-fix labels pre-created idempotently. Matches the GHA workflow's
// pre-create step verbatim (color + description).
const BOT_FIX_LABELS = [
  {
    name: "bot-fix/attempted",
    description: "Bot attempted fix but failed",
    color: "D93F0B",
  },
  {
    name: "bot-fix/auto-merge-eligible",
    description: "Bot fix qualifies for autonomous merge",
    color: "0E8A16",
  },
  {
    name: "bot-fix/review-required",
    description: "Bot fix requires human review",
    color: "FBCA04",
  },
  {
    name: "bot-fix/verified",
    description: "Bot fix verified on main (CI passed)",
    color: "0075CA",
  },
  {
    name: "bot-fix/reverted",
    description: "Bot fix was auto-reverted (CI failed on main)",
    color: "B60205",
  },
] as const;

// Cascade order: lowest priority first (p3-low is the auto-merge candidate
// per the auto-merge gate's source-issue check).
const PRIORITY_CASCADE = [
  "priority/p3-low",
  "priority/p2-medium",
  "priority/p1-high",
] as const;

// Title-regex skip list (matches workflow line 156 jq pattern). The bash
// `\\[` becomes `\[` in JS (one level of escape eaten by YAML, not by JS).
const TITLE_SKIP_RE =
  /^(\[Content Publisher\]|flaky|flake|test-flake|test)[: [(]/i;

// Skip-label list (matches workflow lines 152-155 jq filter).
const SKIP_LABELS = [
  "bot-fix/attempted",
  "ux-audit",
  "synthetic-test",
] as const;

// claude-code spawn argv. `--` is load-bearing per #4017 bug 8/8 (variadic
// --allowedTools consumes the prompt as a tool name without the end-of-
// options marker). The prompt is the SOLE positional argument after `--`.
const CLAUDE_CODE_FLAGS = [
  "--print",
  "--model",
  "claude-sonnet-4-6",
  "--max-turns",
  "55",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep",
  "--",
];

function fixIssuePrompt(issueNumber: number): string {
  return (
    `/soleur:fix-issue ${issueNumber} ` +
    `--exclude-label ux-audit ` +
    `--exclude-label 'agent:*' ` +
    `--exclude-label content-publisher`
  );
}

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

interface DetectedPR {
  number: number;
  node_id: string;
}

interface AutoMergeGateResult {
  queued: boolean;
  reason?: string;
}

interface HandlerArgs {
  event?: {
    data?: { issue_number?: unknown };
  };
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

// Spawn-env allowlist (NOT a denylist). PR-1 shape + GH_TOKEN replaced by
// the freshly minted installation token (deliberately dropping any long-
// lived PAT inherited from the parent env per hr-github-app-auth-not-pat).
// The keys below are the COMPLETE set the spawned claude is allowed to
// see; anything not listed (notably RESEND_API_KEY, SENTRY_*, DOPPLER_*,
// GITHUB_APP_PRIVATE_KEY) is excluded. RESEND_API_KEY in particular is
// consumed by notify-ops-email OUTSIDE the spawn — leaking it into the
// child env would let a prompt-injected Bash invocation exfiltrate it.
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
  const ephemeralRoot = await mkdtemp(join(tmpdir(), "soleur-cron-bug-fixer-"));
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
      feature: "cron-bug-fixer",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-bug-fixer", ephemeralRoot },
    });
  }
}

// =============================================================================
// Issue selection (cascade)
// =============================================================================

interface IssueShape {
  number: number;
  title: string;
  labels: { name: string }[];
  created_at: string;
}

interface PullShape {
  number: number;
  node_id: string;
  head: { ref: string };
  created_at: string;
}

// Collect issue numbers that already have open bot-fix PRs (skip-list).
// Mirrors workflow lines 108-112: parse `bot-fix/<N>-<slug>` head refs.
async function listOpenBotFixIssueNumbers(octokit: Octokit): Promise<Set<number>> {
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/pulls", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    per_page: 100,
  })) as { data: PullShape[] };
  const out = new Set<number>();
  for (const pr of resp.data) {
    const ref = pr.head?.ref ?? "";
    if (!ref.startsWith("bot-fix/")) continue;
    // `bot-fix/<N>-<slug>` → extract N
    const tail = ref.slice("bot-fix/".length);
    const numStr = tail.split("-")[0];
    const n = Number(numStr);
    if (Number.isInteger(n) && n > 0) out.add(n);
  }
  return out;
}

// Apply the priority cascade to find the oldest qualifying issue.
// Returns null if no qualifying issue exists at any priority level.
async function selectIssue(
  octokit: Octokit,
  override: number | undefined,
): Promise<number | null> {
  if (override !== undefined) {
    return override;
  }

  const skipSet = await listOpenBotFixIssueNumbers(octokit);

  for (const priority of PRIORITY_CASCADE) {
    const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      state: "open",
      labels: `${priority},type/bug`,
      per_page: 100,
      sort: "created",
      direction: "asc",
    })) as { data: IssueShape[] };

    for (const issue of resp.data) {
      if (skipSet.has(issue.number)) continue;
      const labelNames = issue.labels.map((l) => l.name);
      if (labelNames.some((n) => SKIP_LABELS.includes(n as never))) continue;
      if (labelNames.some((n) => n.startsWith("agent:"))) continue;
      if (TITLE_SKIP_RE.test(issue.title)) continue;
      return issue.number;
    }
  }

  return null;
}

// =============================================================================
// PR detection + auto-merge gate
// =============================================================================

// Find the most recently created open bot-fix/<N>-* PR. Returns null if
// none exist (the claude-eval may have failed before opening a PR).
async function detectBotFixPr(
  octokit: Octokit,
  issueNumber: number,
): Promise<DetectedPR | null> {
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/pulls", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    per_page: 100,
    sort: "created",
    direction: "desc",
  })) as { data: PullShape[] };

  // Filter by `bot-fix/<issueNumber>-*` prefix first; fall back to any
  // `bot-fix/*` if no issue-prefixed match (defends against agents that
  // mis-slug the head ref).
  const issuePrefix = `bot-fix/${issueNumber}-`;
  const matches = resp.data.filter((pr) => pr.head?.ref?.startsWith(issuePrefix));
  if (matches.length > 0) {
    const pr = matches[0]; // already sorted desc by created_at
    return { number: pr.number, node_id: pr.node_id };
  }

  // Fallback: any bot-fix/* PR, picking the most recently created one.
  const anyBotFix = resp.data.find((pr) =>
    pr.head?.ref?.startsWith("bot-fix/"),
  );
  if (anyBotFix) {
    return { number: anyBotFix.number, node_id: anyBotFix.node_id };
  }
  return null;
}

// Three safety nets + label assertion + GraphQL auto-merge mutation.
// Mirrors workflow lines 213-267 verbatim.
async function runAutoMergeGate(args: {
  octokit: Octokit;
  pr: DetectedPR;
  sourceIssueNumber: number;
  logger: HandlerArgs["logger"];
}): Promise<AutoMergeGateResult> {
  const { octokit, pr, sourceIssueNumber, logger } = args;

  // (1) bot-identity check
  const prResp = (await octokit.request(
    "GET /repos/{owner}/{repo}/pulls/{pull_number}",
    { owner: REPO_OWNER, repo: REPO_NAME, pull_number: pr.number },
  )) as { data: { user: { login: string } | null } };
  const author = prResp.data.user?.login ?? "";
  const isBot =
    author === "github-actions[bot]" ||
    author.includes("[bot]") ||
    author === "app/claude";
  if (!isBot) {
    return {
      queued: false,
      reason: `PR #${pr.number} author '${author}' is not a recognized bot`,
    };
  }

  // (2) Label assertion — PR must carry bot-fix/auto-merge-eligible
  const labelResp = (await octokit.request(
    "GET /repos/{owner}/{repo}/issues/{issue_number}/labels",
    { owner: REPO_OWNER, repo: REPO_NAME, issue_number: pr.number },
  )) as { data: { name: string }[] };
  const labelNames = labelResp.data.map((l) => l.name);
  if (!labelNames.includes("bot-fix/auto-merge-eligible")) {
    return {
      queued: false,
      reason: `PR #${pr.number} missing bot-fix/auto-merge-eligible label`,
    };
  }

  // (3) single-file diff check
  const filesResp = (await octokit.request(
    "GET /repos/{owner}/{repo}/pulls/{pull_number}/files",
    { owner: REPO_OWNER, repo: REPO_NAME, pull_number: pr.number, per_page: 100 },
  )) as { data: { filename: string }[] };
  if (filesResp.data.length !== 1) {
    // Strip eligibility, add review-required (defense-in-depth — agent
    // mis-labeled). Best-effort; failures are non-fatal here.
    try {
      await octokit.request(
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: pr.number,
          name: "bot-fix/auto-merge-eligible",
        },
      );
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: pr.number,
          labels: ["bot-fix/review-required"],
        },
      );
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-bug-fixer",
        op: "relabel-multi-file-pr",
        message: "Failed to swap eligibility label on multi-file PR",
        extra: { fn: "cron-bug-fixer", prNumber: pr.number },
      });
    }
    return {
      queued: false,
      reason: `PR #${pr.number} has ${filesResp.data.length} files changed (single-file required)`,
    };
  }

  // (4) source-issue priority check (must be p3-low)
  const issueLabelResp = (await octokit.request(
    "GET /repos/{owner}/{repo}/issues/{issue_number}/labels",
    { owner: REPO_OWNER, repo: REPO_NAME, issue_number: sourceIssueNumber },
  )) as { data: { name: string }[] };
  const priorityLabels = issueLabelResp.data
    .map((l) => l.name)
    .filter((n) => n.startsWith("priority/"));
  const priority = priorityLabels[0] ?? "unknown";
  if (priority !== "priority/p3-low") {
    try {
      await octokit.request(
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: pr.number,
          name: "bot-fix/auto-merge-eligible",
        },
      );
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: pr.number,
          labels: ["bot-fix/review-required"],
        },
      );
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-bug-fixer",
        op: "relabel-non-p3-pr",
        message: "Failed to swap eligibility label on non-p3-low PR",
        extra: { fn: "cron-bug-fixer", prNumber: pr.number },
      });
    }
    return {
      queued: false,
      reason: `Source issue #${sourceIssueNumber} priority is '${priority}', not p3-low`,
    };
  }

  // All checks passed — fire enablePullRequestAutoMerge mutation.
  const mutation = `
    mutation EnableAutoMerge($pullRequestId: ID!) {
      enablePullRequestAutoMerge(input: {
        pullRequestId: $pullRequestId,
        mergeMethod: SQUASH
      }) {
        pullRequest { autoMergeRequest { enabledAt } }
      }
    }
  `;
  try {
    await octokit.graphql(mutation, { pullRequestId: pr.node_id });
    logger.info(
      { fn: "cron-bug-fixer", prNumber: pr.number },
      "Auto-merge queued",
    );
    return { queued: true };
  } catch (err) {
    // Idempotent path: under Inngest replay (step.run re-execution), the
    // second call to enablePullRequestAutoMerge returns "Pull request Auto
    // merge is already enabled". Treat as success — the prior call already
    // enabled it. Match by message substring (case-insensitive) since the
    // GraphQL response shape doesn't carry a stable error code.
    const message = ((err as Error).message ?? "").toLowerCase();
    if (
      message.includes("auto merge is already enabled") ||
      message.includes("auto-merge is already enabled") ||
      message.includes("already enabled auto merge") ||
      message.includes("already enabled auto-merge")
    ) {
      logger.info(
        { fn: "cron-bug-fixer", prNumber: pr.number },
        "Auto-merge already enabled (idempotent replay) — treating as queued",
      );
      return { queued: true };
    }
    reportSilentFallback(err, {
      feature: "cron-bug-fixer",
      op: "enable-auto-merge",
      message: "enablePullRequestAutoMerge GraphQL mutation failed",
      extra: {
        fn: "cron-bug-fixer",
        prNumber: pr.number,
        prNodeId: pr.node_id,
      },
    });
    return {
      queued: false,
      reason: `GraphQL mutation failed: ${(err as Error).message}`,
    };
  }
}

// =============================================================================
// Resend notification
// =============================================================================

async function notifyOpsEmail(args: {
  prNumber: number;
  logger: HandlerArgs["logger"];
}): Promise<void> {
  const { prNumber, logger } = args;
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    logger.info(
      { fn: "cron-bug-fixer" },
      "RESEND_API_KEY unset — skipping ops email",
    );
    return;
  }
  const from = process.env.OPS_EMAIL_FROM ?? "Soleur Ops <ops@soleur.ai>";
  const to = process.env.OPS_EMAIL_TO ?? "ops@jikigai.com";
  const prUrl = `https://github.com/${REPO_OWNER}/${REPO_NAME}/pull/${prNumber}`;
  const body = {
    from,
    to,
    subject: `[BOT-FIX] Auto-merge queued for PR #${prNumber}`,
    html: `<p><strong>Bot fix auto-merge queued</strong></p><p>PR: <a href="${prUrl}">#${prNumber}</a></p><p>Will merge automatically once CI passes.</p>`,
  };
  try {
    const resp = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(RESEND_TIMEOUT_MS),
    });
    if (!resp.ok) {
      reportSilentFallback(
        new Error(`Resend POST returned ${resp.status}`),
        {
          feature: "cron-bug-fixer",
          op: "notify-ops-email",
          message: "Resend email POST failed",
          extra: { fn: "cron-bug-fixer", prNumber, statusCode: resp.status },
        },
      );
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-bug-fixer",
      op: "notify-ops-email",
      message: "Resend email POST threw",
      extra: { fn: "cron-bug-fixer", prNumber },
    });
  }
}

// =============================================================================
// Pre-create labels
// =============================================================================

async function precreateLabels(octokit: Octokit): Promise<void> {
  for (const label of BOT_FIX_LABELS) {
    try {
      await octokit.request("POST /repos/{owner}/{repo}/labels", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        name: label.name,
        description: label.description,
        color: label.color,
      });
    } catch (err) {
      // 422 already_exists is the common idempotent path; swallow it.
      // Other failures still proceed — labels are bootstrapped once, and
      // the cron's daily fire is forgiving of a transient label-API hiccup.
      const status = (err as { status?: number }).status;
      if (status !== 422) {
        reportSilentFallback(err, {
          feature: "cron-bug-fixer",
          op: "precreate-label",
          message: "Failed to create bot-fix label",
          extra: { fn: "cron-bug-fixer", labelName: label.name, status },
        });
      }
    }
  }
}

// =============================================================================
// Claude-eval spawn (50-min AbortController + SIGTERM→SIGKILL escalation)
// =============================================================================

async function spawnClaudeEval(args: {
  spawnCwd: string;
  installationToken: string;
  issueNumber: number;
  logger: HandlerArgs["logger"];
}): Promise<SpawnResult> {
  const { spawnCwd, installationToken, issueNumber, logger } = args;
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
      // and is scraped into centralized logs (TR9 PR-5 security HIGH-2 —
      // prompt-injected `claude` could `echo $GH_TOKEN` / `env`). PR-1 and
      // PR-4 use stdio:"inherit" safely because they don't inject a write-
      // scoped GH_TOKEN into the child's env; PR-5 is the first cron-*
      // function that does, so the redacting pipe is required here.
      const child = spawn(
        claudeBin,
        [...CLAUDE_CODE_FLAGS, fixIssuePrompt(issueNumber)],
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
      // readline.createInterface back-pressures naturally; no manual ring
      // buffer needed since we forward-and-forget.
      if (child.stdout) {
        const rlOut = createInterface({ input: child.stdout });
        rlOut.on("line", (line) => {
          logger.info(
            { fn: "cron-bug-fixer", stream: "stdout" },
            redactToken(line, installationToken),
          );
        });
      }
      if (child.stderr) {
        const rlErr = createInterface({ input: child.stderr });
        rlErr.on("line", (line) => {
          logger.error(
            { fn: "cron-bug-fixer", stream: "stderr" },
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
          extra: { fn: "cron-bug-fixer", issueNumber },
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
          fn: "cron-bug-fixer",
          issueNumber,
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
      { fn: "cron-bug-fixer" },
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
      { fn: "cron-bug-fixer" },
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
        fn: "cron-bug-fixer",
        status,
        aborted: e.name === "TimeoutError",
      },
    });
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronBugFixerHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<{
  selectedIssue: number | null;
  prNumber: number | null;
  autoMergeQueued: boolean;
  ok: boolean;
}> {
  // --- Parse manual-trigger override ---
  let override: number | undefined;
  const rawOverride = event?.data?.issue_number;
  if (rawOverride !== undefined && rawOverride !== null) {
    if (
      typeof rawOverride !== "number" ||
      !Number.isInteger(rawOverride) ||
      rawOverride <= 0
    ) {
      reportSilentFallback(
        new Error(
          `Invalid event.data.issue_number: ${JSON.stringify(rawOverride)}`,
        ),
        {
          feature: "cron-bug-fixer",
          op: "parse-event-data",
          message: "Manual-trigger issue_number must be a positive integer",
          extra: { fn: "cron-bug-fixer", rawOverride: String(rawOverride) },
        },
      );
      await step.run("sentry-heartbeat", async () => {
        await postSentryHeartbeat({ ok: false, logger });
      });
      return {
        selectedIssue: null,
        prNumber: null,
        autoMergeQueued: false,
        ok: false,
      };
    }
    override = rawOverride;
  }

  // --- Step 1: mint installation token (memoized 5min) ---
  // Cached across replays via Inngest's step.run memoization; the raw token
  // string is the return value (NEVER log this value).
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken();
    },
  );

  // --- Step 2: precreate labels (idempotent) ---
  await step.run("precreate-labels", async () => {
    const octokit = await createProbeOctokit();
    await precreateLabels(octokit as unknown as Octokit);
  });

  // --- Step 3: select issue (cascade or override) ---
  const selectedIssue = await step.run("select-issue", async () => {
    const octokit = await createProbeOctokit();
    const result = await selectIssue(octokit as unknown as Octokit, override);
    if (result === null) {
      logger.info(
        { fn: "cron-bug-fixer" },
        "No qualifying issue found at any priority level",
      );
    }
    return result;
  });

  // No issue → empty-run; heartbeat ok, short-circuit.
  if (selectedIssue === null) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: true, logger });
    });
    return {
      selectedIssue: null,
      prNumber: null,
      autoMergeQueued: false,
      ok: true,
    };
  }

  // --- Step 4: setup ephemeral workspace (clone + symlink + sentinel) ---
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
      feature: "cron-bug-fixer",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-bug-fixer", selectedIssue },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, logger });
    });
    return {
      selectedIssue,
      prNumber: null,
      autoMergeQueued: false,
      ok: false,
    };
  }

  // Wrap the entire post-setup pipeline in try/finally so the ephemeral
  // workspace is torn down even if claude-eval throws at the Inngest step
  // boundary (TR9 PR-5 perf MEDIUM + architecture R1 + data-integrity).
  // The teardown side-effect outside step.run is acceptable because rm
  // {recursive:true, force:true} is idempotent — a replay re-creates a
  // fresh ephemeralRoot from setup-workspace's memoization (or the
  // existsSync guard at the top of spawnClaudeEval rebuilds it).
  try {
    // --- Step 5: claude-eval (50-min AbortController) ---
    const spawnResult = await step.run(
      "claude-eval",
      async (): Promise<SpawnResult> => {
        return spawnClaudeEval({
          spawnCwd: spawnCwd!,
          installationToken,
          issueNumber: selectedIssue,
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
          feature: "cron-bug-fixer",
          op: "claude-eval-timeout",
          message: "claude-eval aborted by AbortController",
          extra: {
            fn: "cron-bug-fixer",
            durationMs: spawnResult.durationMs,
            maxMs: MAX_TURN_DURATION_MS,
          },
        },
      );
    }

    // --- Step 6: detect-pr (even on non-zero exit; agent may have opened PR) ---
    const detectedPr = await step.run("detect-pr", async () => {
      const octokit = await createProbeOctokit();
      return detectBotFixPr(octokit as unknown as Octokit, selectedIssue);
    });

    if (!detectedPr) {
      logger.warn(
        { fn: "cron-bug-fixer", selectedIssue },
        "No bot-fix PR detected after claude-eval",
      );
      await step.run("sentry-heartbeat", async () => {
        await postSentryHeartbeat({ ok: spawnResult.ok, logger });
      });
      return {
        selectedIssue,
        prNumber: null,
        autoMergeQueued: false,
        ok: spawnResult.ok,
      };
    }

    // --- Step 7: auto-merge-gate ---
    const gateResult = await step.run("auto-merge-gate", async () => {
      const octokit = await createProbeOctokit();
      return runAutoMergeGate({
        octokit: octokit as unknown as Octokit,
        pr: detectedPr,
        sourceIssueNumber: selectedIssue,
        logger,
      });
    });

    if (!gateResult.queued) {
      logger.info(
        { fn: "cron-bug-fixer", prNumber: detectedPr.number, reason: gateResult.reason },
        "Auto-merge not queued",
      );
    }

    // --- Step 8: notify-ops-email (only if auto-merge queued) ---
    if (gateResult.queued) {
      await step.run("notify-ops-email", async () => {
        await notifyOpsEmail({ prNumber: detectedPr.number, logger });
      });
    }

    // --- Step 9: sentry-heartbeat (final POST) ---
    const overallOk = spawnResult.ok && !!detectedPr;
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: overallOk, logger });
    });

    return {
      selectedIssue,
      prNumber: detectedPr.number,
      autoMergeQueued: gateResult.queued,
      ok: overallOk,
    };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-bug-fixer",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-bug-fixer", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 6 * * * UTC) + manual operator event
// `cron/bug-fixer.manual-trigger`. account-scope concurrency
// "cron-platform" limits to 1 simultaneous cron-* invocation across the
// Hetzner node (PR-1 / PR-4 precedent).

export const cronBugFixer = inngest.createFunction(
  {
    id: "cron-bug-fixer",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [{ cron: "0 6 * * *" }, { event: "cron/bug-fixer.manual-trigger" }],
  cronBugFixerHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
