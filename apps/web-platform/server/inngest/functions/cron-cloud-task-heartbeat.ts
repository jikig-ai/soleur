// TR9 Phase-2 — Daily cloud-task silence watchdog migrated to Inngest cron.
//
// Migrated from .github/workflows/scheduled-cloud-task-heartbeat.yml (deleted
// in the same PR per TR9 I-13 hygiene). Pure TS port — no agent spawn,
// no ephemeral workspace. All IO via Octokit (installation-scoped token).
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — No long-running subprocess; Octokit timeout bounds wallclock.
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.
//
// NAME NOTE: Sentry monitor slug "scheduled-cloud-task-heartbeat" preserves
// historical check-in continuity from the GHA workflow.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-cloud-task-heartbeat";

// Installation-token lifetime floor: 15-min headroom for ~20 API calls.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

export interface TaskEntry {
  name: string;
  label: string;
  maxGapDays: number;
}

// INVENTORY SCOPE — output-producing scheduled tasks ONLY.
//
// The heartbeat's only valid signal is "did this task produce its expected
// `scheduled-<task>` issue artifact within its cadence window?" — so a task
// belongs here ONLY if its cron function actually creates a `scheduled-<task>`
// labeled issue. Three tasks were removed because they are NON-PRODUCERS and
// would false-fire forever via the `daysSince === null → silent: true` branch:
//   - daily-triage: labels existing issues only (prompt forbids `gh issue create`)
//   - ux-audit: runs UX_AUDIT_DRY_RUN=true → writes Supabase/stdout, no issue
//   - bug-fixer: opens bot-fix PRs, never a `scheduled-bug-fixer` issue
// Cron LIVENESS for ALL tasks (including these three) is covered separately by
// the per-function Sentry cron monitors — see #4708, which retired the sibling
// cron-inngest-cron-watchdog for the same reason (Inngest `/v1/*` run-history is
// loopback-gated and unreachable from the app container). maxGapDays is derived
// from each task's real cron cadence; see the runbook's Threshold Derivation.
export const TASK_INVENTORY: TaskEntry[] = [
  { name: "content-generator", label: "scheduled-content-generator", maxGapDays: 9 },
  { name: "strategy-review", label: "scheduled-strategy-review", maxGapDays: 9 },
  { name: "legal-audit", label: "scheduled-legal-audit", maxGapDays: 95 },
  { name: "competitive-analysis", label: "scheduled-competitive-analysis", maxGapDays: 40 },
  { name: "community-monitor", label: "scheduled-community-monitor", maxGapDays: 3 },
  { name: "roadmap-review", label: "scheduled-roadmap-review", maxGapDays: 9 },
];

const SILENCE_ISSUE_TITLE_PREFIX = "[cloud-task-silence]";

// =============================================================================
// Helpers
// =============================================================================

interface TaskCheckResult {
  name: string;
  label: string;
  silent: boolean;
  daysSince: number | null;
  maxGapDays: number;
}

// =============================================================================
// Handler
// =============================================================================

export async function cronCloudTaskHeartbeatHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  results: TaskCheckResult[];
  silentCount: number;
}> {
  // Step 1: mint installation token
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // Step 2: check all tasks for silence
  const results = await step.run(
    "check-task-silence",
    async (): Promise<TaskCheckResult[]> => {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });
      const checks: TaskCheckResult[] = [];

      for (const task of TASK_INVENTORY) {
        try {
          const res = await octokit.request(
            "GET /repos/{owner}/{repo}/issues",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              labels: task.label,
              state: "all",
              per_page: 1,
              sort: "created",
              direction: "desc",
            },
          );
          const issues = res.data as Array<{ created_at: string }>;
          if (issues.length === 0) {
            checks.push({
              name: task.name,
              label: task.label,
              silent: true,
              daysSince: null,
              maxGapDays: task.maxGapDays,
            });
            continue;
          }

          const createdAt = Date.parse(issues[0].created_at);
          const daysSince = Number.isNaN(createdAt)
            ? null
            : Math.floor((Date.now() - createdAt) / (86400 * 1000));

          checks.push({
            name: task.name,
            label: task.label,
            silent: daysSince === null || daysSince > task.maxGapDays,
            daysSince,
            maxGapDays: task.maxGapDays,
          });
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cron-cloud-task-heartbeat",
            op: "check-task",
            message: `Failed to check task ${task.name}`,
            extra: { fn: "cron-cloud-task-heartbeat", task: task.name },
          });
          checks.push({
            name: task.name,
            label: task.label,
            silent: true,
            daysSince: null,
            maxGapDays: task.maxGapDays,
          });
        }
      }

      return checks;
    },
  );

  // Step 3: issue handling — file/comment silence issues, auto-close on recovery
  await step.run("issue-handling", async () => {
    try {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });

      for (const result of results) {
        const issueTitle = `${SILENCE_ISSUE_TITLE_PREFIX} ${result.name} silent`;

        // Search for existing open silence issue for this task
        const search = await octokit.request("GET /search/issues", {
          q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${issueTitle}"`,
          per_page: 1,
        });
        const existing = (search.data.items ?? [])[0];

        if (result.silent) {
          const detail =
            result.daysSince === null
              ? `No issues found with label "${result.label}"`
              : `Last issue was ${result.daysSince} days ago (threshold: ${result.maxGapDays} days)`;

          if (existing) {
            await octokit.request(
              "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
              {
                owner: REPO_OWNER,
                repo: REPO_NAME,
                issue_number: existing.number,
                body: `Still silent at ${new Date().toISOString()} — ${detail}`,
              },
            );
          } else {
            await octokit.request("POST /repos/{owner}/{repo}/issues", {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              title: issueTitle,
              labels: ["cloud-task-silence"],
              body: [
                `## Cloud task "${result.name}" is silent`,
                "",
                `- **Label:** \`${result.label}\``,
                `- **Days since last issue:** ${result.daysSince ?? "never"}`,
                `- **Max gap threshold:** ${result.maxGapDays} days`,
                `- **Detected at:** ${new Date().toISOString()}`,
                "",
                "### What to do",
                "",
                "See [cloud-scheduled-tasks.md runbook](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md).",
                "",
                "**Tracks:** #2714",
                "",
                "_Auto-created by the [cron-cloud-task-heartbeat Inngest function](https://github.com/jikig-ai/soleur/blob/main/apps/web-platform/server/inngest/functions/cron-cloud-task-heartbeat.ts)._",
              ].join("\n"),
            });
          }
          logger.info(
            { fn: "cron-cloud-task-heartbeat", task: result.name },
            "Task is silent — issue filed/commented",
          );
        } else {
          // Recovery: close any open silence issue for this task
          if (existing) {
            await octokit.request(
              "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
              {
                owner: REPO_OWNER,
                repo: REPO_NAME,
                issue_number: existing.number,
                body: `Task "${result.name}" recovered at ${new Date().toISOString()} — last issue was ${result.daysSince} days ago (within ${result.maxGapDays}-day threshold). Auto-closing.`,
              },
            );
            await octokit.request(
              "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
              {
                owner: REPO_OWNER,
                repo: REPO_NAME,
                issue_number: existing.number,
                state: "closed",
              },
            );
            logger.info(
              { fn: "cron-cloud-task-heartbeat", task: result.name },
              "Task recovered — auto-closed silence issue",
            );
          }
        }
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-cloud-task-heartbeat",
        op: "issue-handling",
        message: "Failed to handle silence issues",
        extra: { fn: "cron-cloud-task-heartbeat" },
      });
    }
  });

  // Step 4: Sentry heartbeat
  const silentCount = results.filter((r) => r.silent).length;
  const ok = silentCount === 0;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-cloud-task-heartbeat",
      logger,
    });
  });

  return { ok, results, silentCount };
}

// =============================================================================
// Registration
// =============================================================================

export const cronCloudTaskHeartbeat = inngest.createFunction(
  {
    id: "cron-cloud-task-heartbeat",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "30 9 * * *" },
    { event: "cron/cloud-task-heartbeat.manual-trigger" },
  ],
  cronCloudTaskHeartbeatHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
