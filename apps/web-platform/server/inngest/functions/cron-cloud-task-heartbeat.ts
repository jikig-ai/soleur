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
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
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

// INVENTORY SCOPE — UNCONDITIONALLY output-producing scheduled tasks ONLY.
//
// The heartbeat's only valid signal is "did this task produce its expected
// `scheduled-<task>` issue artifact within its cadence window?" — so a task
// belongs here ONLY if its cron function creates a `scheduled-<task>` labeled
// issue on EVERY successful run. Tasks excluded because the label-presence
// signal can never reliably observe their output (they'd false-fire):
//   - daily-triage: labels existing issues only (prompt forbids `gh issue create`)
//   - ux-audit: runs UX_AUDIT_DRY_RUN=true → writes Supabase/stdout, no issue
//   - bug-fixer: opens bot-fix PRs, never a `scheduled-bug-fixer` issue
//   - strategy-review: CONDITIONAL/idempotent producer — opens an issue ONLY per
//     knowledge-base file needing review (title-dedup, skips up_to_date), so a
//     quiet week with everything up-to-date legitimately yields zero issues.
//     Issue-presence is the wrong silence signal for it (#4874). Its liveness is
//     covered by the Sentry cron monitor `scheduled-strategy-review`.
// Cron LIVENESS for ALL excluded tasks is covered separately by the per-function
// Sentry cron monitors — see #4708, which retired the sibling
// cron-inngest-cron-watchdog for the same reason (Inngest `/v1/*` run-history is
// loopback-gated and unreachable from the app container). maxGapDays is derived
// from each task's real cron cadence; see the runbook's Threshold Derivation.
//
// NEVER-PRODUCED GRACE: a task that is in this inventory but has produced ZERO
// issues ever (e.g. a newly-migrated quarterly producer before its first fire)
// is reported as `pending-first-run` (silent:false + a Sentry warning), NOT as
// silent — see the `issues.length === 0` arm in check-task-silence. This
// restores the original GHA watchdog's "warn-and-skip on never-seen labels"
// behavior (#4875: legal-audit migrated 2026-05-25, first real fire 2026-07-01).
export const TASK_INVENTORY: TaskEntry[] = [
  { name: "content-generator", label: "scheduled-content-generator", maxGapDays: 9 },
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
            // NEVER-PRODUCED GRACE (#4875): the query SUCCEEDED and returned zero
            // rows — the task has never produced its `scheduled-<task>` issue.
            // For a newly-migrated producer (e.g. legal-audit, quarterly, first
            // real fire 2026-07-01) this is "pending first run", NOT silence.
            // Report it as a Sentry warning (visible, non-paging) and do NOT flag
            // silent — so issue-handling files no GitHub issue and auto-closes any
            // stale one. Cron liveness for the pre-first-fire window is covered by
            // the task's OWN per-function Sentry cron monitor, not this watchdog.
            // (Distinct code path from the `catch` arm below — an API error — and
            // from the in-band `daysSince === null` NaN-parse case, both of which
            // remain `silent: true`.)
            warnSilentFallback(null, {
              feature: "cron-cloud-task-heartbeat",
              op: "task-pending-first-run",
              message: `Task ${task.name} has never produced a ${task.label} issue — pending first run`,
              extra: { fn: "cron-cloud-task-heartbeat", task: task.name },
            });
            checks.push({
              name: task.name,
              label: task.label,
              silent: false,
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
          // Recovery: close any open silence issue for this task. `daysSince`
          // is null for a pending-first-run task (never produced an issue) —
          // guard the comment so it reads sensibly instead of "null days ago".
          const recoveryDetail =
            result.daysSince === null
              ? `pending first run (never produced an issue)`
              : `last issue was ${result.daysSince} days ago (within ${result.maxGapDays}-day threshold)`;
          if (existing) {
            await octokit.request(
              "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
              {
                owner: REPO_OWNER,
                repo: REPO_NAME,
                issue_number: existing.number,
                body: `Task "${result.name}" recovered at ${new Date().toISOString()} — ${recoveryDetail}. Auto-closing.`,
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
