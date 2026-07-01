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
//   - repo/plugins/soleur            (the clone's own tracked tree — #5091)
//   - repo/.claude/settings.json     (DEFAULT_SETTINGS overlay)
// The spawn cwd is repo/ so that:
//   (a) the explicit `--plugin-dir plugins/soleur` flag (in CLAUDE_CODE_FLAGS
//       below) registers the soleur plugin manifest at
//       plugins/soleur/.claude-plugin/plugin.json — headless `--print` does NOT
//       auto-discover it from spawn cwd (see #4993 / #4987);
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

import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  mintInstallationToken,
  deferIfTier2Cron,
  postSentryHeartbeat,
  resolveBestEffortEvalOk,
  DEFAULT_CRON_TOKEN_PERMISSIONS,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
  spawnClaudeEval,
  type SpawnResult,
} from "./_cron-claude-eval-substrate";
import type { Octokit } from "@octokit/core";
import { enableAutoMergeSquash } from "./_cron-safe-commit";
import { inngest } from "@/server/inngest/client";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-bug-fixer";
const RESEND_TIMEOUT_MS = 10_000;

// Token-lifetime floor passed to generateInstallationToken: claude-eval's
// 50-min wall-clock budget + 10-min slack for setup + teardown + retry
// (TR9 PR-5 security HIGH-1 — token expiry race vs. spawn budget).
const TOKEN_MIN_LIFETIME_MS = 50 * 60 * 1000 + 10 * 60 * 1000;

// 50 min wall-clock budget. Math: 50min / 55turns = 0.91 min/turn,
// comfortably above the 0.75 min/turn floor (Architecture-strategist F2,
// PR-1 header). Exported for test parity (cron-bug-fixer.test.ts imports
// to avoid hard-coded timing drift across SUT tuning).
export const MAX_TURN_DURATION_MS = 50 * 60 * 1000;
export { KILL_ESCALATION_MS } from "./_cron-claude-eval-substrate";

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
  EXECUTION_MODEL,
  "--max-turns",
  "55",
  "--allowedTools",
  "Bash,Read,Write,Edit,Glob,Grep,Skill,Task",
  "--plugin-dir",
  "plugins/soleur",
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

// =============================================================================
// Types
// =============================================================================

interface DetectedPR {
  number: number;
  node_id: string;
}

interface AutoMergeGateResult {
  queued: boolean;
  reason?: string;
}

// =============================================================================
// Helpers
// =============================================================================

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

  // All checks passed — fire enablePullRequestAutoMerge (shared with the
  // safe-commit pipeline since #5091; carries the idempotent-replay
  // "already enabled" tolerance — that path is expected under Inngest
  // step.run re-execution and MUST NOT emit a Sentry breadcrumb).
  const autoMerge = await enableAutoMergeSquash(octokit, pr.node_id);
  if (autoMerge.enabled) {
    logger.info(
      { fn: "cron-bug-fixer", prNumber: pr.number },
      autoMerge.alreadyEnabled
        ? "Auto-merge already enabled (idempotent replay) — treating as queued"
        : "Auto-merge queued",
    );
    return { queued: true };
  }
  // Deliberately NO direct-merge fallback on cleanStatus here (unlike
  // safeCommitAndPr): bug-fixer's auto-merge is gated by 3 safety nets and
  // must never force a merge the checks pipeline did not arbitrate.
  const reason = autoMerge.cleanStatus
    ? "Pull request is in clean status"
    : (autoMerge.reason ?? "enablePullRequestAutoMerge failed");
  reportSilentFallback(new Error(reason), {
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
    reason: `GraphQL mutation failed: ${reason}`,
  };
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
// Handler
// =============================================================================

export async function cronBugFixerHandler({
  event,
  step,
  logger,
  runId,
  attempt,
}: HandlerArgs): Promise<{
  selectedIssue: number | null;
  prNumber: number | null;
  autoMergeQueued: boolean;
  ok: boolean;
  errorSummary?: string;
}> {
  // D6 (#5018) / #5046 PR-2: still Tier-2-deferred — the firewall landed but
  // this cron needs per-construct Bash-allowlist refinement or non-GitHub
  // egress coverage before restore (see TIER2_DEFERRED_CRONS). Posts an
  // honest on-schedule check-in and skips the claude spawn (no fail-closed
  // FAILED-issue/RED-monitor storm); the scheduled output issue visibly stops.
  if (
    await deferIfTier2Cron({
      cronName: "cron-bug-fixer",
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      step,
      logger,
    })
  ) {
    return { selectedIssue: null, prNumber: null, autoMergeQueued: false, ok: true };
  }

  // --- Parse manual-trigger override ---
  let override: number | undefined;
  const rawOverride = event?.data?.issue_number as unknown;
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
        await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-bug-fixer", logger });
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
      // #5199 — narrow the mint to a least-privilege, repo-scoped token. bug-fixer
      // pushes + opens PRs (via the fix-issue SKILL), so it needs the WRITE-capable
      // DEFAULT_CRON_TOKEN_PERMISSIONS (contents/issues/pull_requests:write) — the
      // issue-creator read-only preset would 403 the push. Scoping to [REPO_NAME]
      // bounds a leaked token to a single-user incident.
      return mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,
        repositories: [REPO_NAME],
      });
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
      await postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-bug-fixer", logger });
    });
    return {
      selectedIssue: null,
      prNumber: null,
      autoMergeQueued: false,
      ok: true,
    };
  }

  // --- Step 4: setup ephemeral workspace (clone + settings + sentinel) ---
  // Track ephemeralRoot in handler-scope so teardown runs regardless of
  // downstream success/failure.
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const workspace = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({ installationToken, cronName: "cron-bug-fixer" });
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
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-bug-fixer", logger });
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
          flags: CLAUDE_CODE_FLAGS,
          prompt: fixIssuePrompt(selectedIssue),
          maxTurnDurationMs: MAX_TURN_DURATION_MS,
          cronName: "cron-bug-fixer",
          buildSpawnEnv,
          logger,
          runId,
          attempt,
        });
      },
    );

    // #5674 — classify-fatal heartbeat (NOT flip-all). A non-zero claude exit
    // (no fix landed, or aborted by the 50-min budget) is usually the NORMAL
    // best-effort outcome for an autonomous fixer — bug-fixer has the highest
    // benign-non-zero frequency in the fleet, so its benign path MUST stay green
    // (the #4730/#4727 decoupling; H1 in
    // knowledge-base/project/plans/2026-06-01-fix-scheduled-bug-fixer-cron-error-checkin-plan.md).
    // But resolveBestEffortEvalOk inspects the captured tail: a non-zero exit
    // matching a FATAL class (credit exhausted, auth/401 revoked, spawn fault,
    // AbortController timeout) now flips the monitor RED and records the scrubbed
    // reason in routine_runs — the 2026-06-29 credit incident was silently green
    // under the old unconditional-green policy. The abortedByTimeout infra-fault
    // is folded into the fatal class (single signal, no double-report with the
    // old separate claude-eval-timeout breadcrumb). decision.ok threads into BOTH
    // heartbeat/return sites below (no-PR early return AND the final one) so the
    // fatal flip holds on every exit path. See ADR-033 (classify-fatal invariant).
    //
    // A benign non-zero is still surfaced as a WARNING-level Sentry event
    // (warnSilentFallback, op=claude-eval-nonzero-nofix, tagged with
    // selectedIssue) — queryable off-host, NON-paging — so a chronically-broken
    // -but-live fixer is diff-able week over week (a bare pino logger.warn would
    // be invisible without SSH).
    const decision = resolveBestEffortEvalOk(spawnResult);
    if (!decision.ok) {
      reportSilentFallback(
        new Error(decision.errorSummary ?? "claude-eval fatal failure"),
        {
          feature: "cron-bug-fixer",
          op: "claude-eval-fatal",
          message:
            "claude-eval failed for a FATAL class (credit/auth/spawn/timeout); cron monitor flips red",
          extra: { fn: "cron-bug-fixer", selectedIssue, ...decision.sentryExtra },
        },
      );
    } else if (!spawnResult.ok) {
      warnSilentFallback(
        new Error("claude-eval exited non-zero — no fix landed this run"),
        {
          feature: "cron-bug-fixer",
          op: "claude-eval-nonzero-nofix",
          message:
            "claude-eval exited non-zero (benign no-fix); cron monitor stays green (liveness, not success)",
          extra: { fn: "cron-bug-fixer", selectedIssue, ...decision.sentryExtra },
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
      // No PR is the normal best-effort outcome → green liveness UNLESS the
      // claude exit was a FATAL class (decision.ok:false), in which case the
      // monitor flips red and routine_runs records the scrubbed reason (#5674).
      await step.run("sentry-heartbeat", async () => {
        await postSentryHeartbeat({ ok: decision.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-bug-fixer", logger });
      });
      return {
        selectedIssue,
        prNumber: null,
        autoMergeQueued: false,
        ok: decision.ok,
        errorSummary: decision.errorSummary,
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
    // classify-fatal: green on a clean/benign run (even one that opened a PR
    // despite a non-zero exit), red on a FATAL-class claude exit (decision.ok).
    // Infra faults page via the early-return status=error heartbeats above.
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: decision.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-bug-fixer", logger });
    });

    return {
      selectedIssue,
      prNumber: detectedPr.number,
      autoMergeQueued: gateResult.queued,
      ok: decision.ok,
      errorSummary: decision.errorSummary,
    };
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). The
    // teardown helper already mirrors any failure to Sentry — wrapping
    // in .catch() here is a paranoid double-net to ensure a teardown
    // throw can never escape the finally and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-bug-fixer").catch((err) => {
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
