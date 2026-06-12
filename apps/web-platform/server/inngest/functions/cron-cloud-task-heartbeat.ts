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

// --- Stale bot-PR watchdog (#5138) -------------------------------------------
//
// safeCommitAndPr's `mergeMode: "auto"` pipelines rely on GitHub
// `enablePullRequestAutoMerge`, which SILENTLY disarms on a merge conflict — the
// PR stays open with no signal. The `direct` mode's merge-fallback (Sentry op
// `safe-commit-direct-merge-fell-back`) can enter the same disarmable state.
// This scan catches the RESULT (an open `ci/*` PR past the threshold) merge-mode
// agnostically, so it covers both cohorts without special-casing. Staleness is
// kept ORTHOGONAL to the heartbeat `ok`/`silentCount` — it warns + comments only,
// never flips the cron monitor (found-work ≠ liveness). See ADR-054.
const STALE_BOT_PR_THRESHOLD_MS = 48 * 60 * 60 * 1000;
const BOT_PR_HEAD_PREFIXES = ["ci/", "self-healing/auto-"] as const;
export const STALE_BOT_PR_WARN_OP = "stale-bot-pr";

/** The subset of the `GET …/pulls` payload the watchdog reads. */
export interface BotPrLite {
  number: number;
  head: { ref: string };
  created_at: string;
  draft: boolean;
  labels: Array<{ name: string }>;
  html_url: string;
}

interface StaleBotPr {
  number: number;
  headRef: string;
  ageHours: number;
  /** `scheduled-<cron>` label, or null when the head does not reverse-derive one. */
  scheduledLabel: string | null;
  htmlUrl: string;
}

/**
 * Reverse-derive a cron's scheduled-issue label from a `ci/<name>-<ts>` head
 * branch (`deriveBranchName`, _cron-safe-commit.ts). The trailing
 * `-YYYY-MM-DD-HHMMSS` timestamp is `$`-anchored so digit/hyphen cron names
 * survive (`ci/nag-4216-readiness-…` → `scheduled-nag-4216-readiness`). Returns
 * null for `self-healing/auto-*` (excluded) and any non-`ci/` head — a null
 * label routes to Sentry-only (the warn still fires).
 */
export function scheduledLabelFromHead(headRef: string): string | null {
  if (!headRef.startsWith("ci/")) return null;
  const rest = headRef
    .slice("ci/".length)
    .replace(/-\d{4}-\d{2}-\d{2}-\d{6}$/, "");
  return rest ? `scheduled-${rest}` : null;
}

/**
 * A bot PR is stale iff its head matches a BOT_PR_HEAD_PREFIXES entry, it was
 * created strictly more than 48h ago, and it is NOT a compound-promote
 * human-review draft (draft AND labeled `self-healing/auto`). A malformed
 * `created_at` returns false rather than throwing — a single corrupt payload
 * must not dark the whole scan.
 */
export function isStaleBotPr(pr: BotPrLite, nowMs: number): boolean {
  const ref = pr.head?.ref ?? "";
  if (!BOT_PR_HEAD_PREFIXES.some((p) => ref.startsWith(p))) return false;
  if (pr.draft && (pr.labels ?? []).some((l) => l.name === "self-healing/auto")) {
    return false;
  }
  const createdAt = Date.parse(pr.created_at);
  if (Number.isNaN(createdAt)) return false;
  return nowMs - createdAt > STALE_BOT_PR_THRESHOLD_MS;
}

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
                "See [cloud-scheduled-tasks.md runbook](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md).",
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

  // Step 3.5: scan open bot PRs for staleness (#5138). Orthogonal to the
  // task-silence `ok` above — never flips the heartbeat monitor.
  const staleBotPrs = await step.run(
    "check-stale-bot-prs",
    async (): Promise<StaleBotPr[]> => {
      try {
        const { Octokit } = await import("@octokit/core");
        const octokit = new Octokit({ auth: installationToken });
        const out: StaleBotPr[] = [];
        const now = Date.now();
        // sort=created asc (oldest first); the order is monotonic because
        // `created_at` is immutable, so the first PR newer than the threshold
        // means no later page can hold a stale one — early-exit bounds the scan
        // to the >48h-old PRs (≈0 bot PRs in steady state). No page cap needed.
        for (let page = 1; ; page++) {
          const res = await octokit.request("GET /repos/{owner}/{repo}/pulls", {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            state: "open",
            sort: "created",
            direction: "asc",
            per_page: 100,
            page,
            headers: { "X-GitHub-Api-Version": "2022-11-28" },
          });
          const prs = res.data as BotPrLite[];
          if (prs.length === 0) break;
          let reachedFresh = false;
          for (const pr of prs) {
            const createdAt = Date.parse(pr.created_at);
            if (
              !Number.isNaN(createdAt) &&
              now - createdAt <= STALE_BOT_PR_THRESHOLD_MS
            ) {
              reachedFresh = true; // every later PR is newer → stop scanning
              break;
            }
            if (isStaleBotPr(pr, now)) {
              out.push({
                number: pr.number,
                headRef: pr.head.ref,
                ageHours: Math.floor((now - createdAt) / (3600 * 1000)),
                scheduledLabel: scheduledLabelFromHead(pr.head.ref),
                htmlUrl: pr.html_url,
              });
            }
          }
          if (reachedFresh || prs.length < 100) break;
        }
        return out;
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-cloud-task-heartbeat",
          op: "stale-bot-pr-scan-failed",
          message: "Failed to scan open bot PRs for staleness",
          extra: { fn: "cron-cloud-task-heartbeat" },
        });
        return [];
      }
    },
  );

  // Step 3.6: warn + best-effort owning-issue comment for each stale bot PR.
  await step.run("stale-bot-pr-handling", async () => {
    if (staleBotPrs.length === 0) return;

    // 1. Sentry warns first — these need no Octokit, so an @octokit import /
    //    constructor failure below can never suppress the routed signal. Stable
    //    message; per-PR detail in `extra` so Sentry groups one issue per PR.
    for (const pr of staleBotPrs) {
      warnSilentFallback(null, {
        feature: "cron-cloud-task-heartbeat",
        op: STALE_BOT_PR_WARN_OP,
        message: "Bot PR open past staleness threshold",
        extra: {
          fn: "cron-cloud-task-heartbeat",
          pr_number: pr.number,
          head_ref: pr.headRef,
          age_hours: pr.ageHours,
          owning_cron: pr.scheduledLabel?.replace(/^scheduled-/, "") ?? "unknown",
          html_url: pr.htmlUrl,
        },
      });
    }

    // 2. Best-effort owning-issue comments. Wrapped in an OUTER guard (mirroring
    //    check-task-silence / issue-handling) so an import or Octokit-constructor
    //    failure cannot throw the step — staleness must never flip the heartbeat
    //    monitor (found-work ≠ liveness). Per-PR errors are caught individually.
    try {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });

      for (const pr of staleBotPrs) {
        if (!pr.scheduledLabel) continue; // no derivable label → Sentry-only
        try {
          const issues = (await octokit.request(
            "GET /repos/{owner}/{repo}/issues",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              labels: pr.scheduledLabel,
              state: "open",
              sort: "created",
              direction: "desc",
              per_page: 1,
              headers: { "X-GitHub-Api-Version": "2022-11-28" },
            },
          )) as { data: Array<{ number: number }> };
          const issue = issues.data[0];
          if (!issue) continue; // no labeled open issue → Sentry-only

          const marker = `<!-- stale-bot-pr:${pr.number} -->`;
          // direction:desc — the dedup marker from any prior run is among the
          // most-recent comments, so it lands on page 1 even on a months-old
          // issue with >100 comments (page-1-only scan would otherwise re-spam).
          const comments = (await octokit.request(
            "GET /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: issue.number,
              per_page: 100,
              sort: "created",
              direction: "desc",
              headers: { "X-GitHub-Api-Version": "2022-11-28" },
            },
          )) as { data: Array<{ body?: string }> };
          if (comments.data.some((c) => (c.body ?? "").includes(marker))) {
            continue; // already commented for this PR
          }

          await octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: issue.number,
              body: [
                marker,
                `⚠️ Bot PR [#${pr.number}](${pr.htmlUrl}) (head \`${pr.headRef}\`) has been open ${pr.ageHours}h (threshold: 48h).`,
                "",
                "Auto-merge likely disarmed on a merge conflict (it disarms silently) — rebase the branch to resolve the conflict and let auto-merge re-fire, or close the PR.",
                "",
                "See [cloud-scheduled-tasks.md runbook §Stale bot PR](https://github.com/jikig-ai/soleur/blob/main/knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md).",
              ].join("\n"),
              headers: { "X-GitHub-Api-Version": "2022-11-28" },
            },
          );
          logger.info(
            { fn: "cron-cloud-task-heartbeat", pr: pr.number },
            "Stale bot PR — commented on owning scheduled issue",
          );
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cron-cloud-task-heartbeat",
            op: "stale-bot-pr-comment-failed",
            message: "Could not post stale-bot-PR comment on owning scheduled issue",
            extra: {
              fn: "cron-cloud-task-heartbeat",
              pr_number: pr.number,
              label: pr.scheduledLabel,
            },
          });
        }
      }
    } catch (err) {
      // import/constructor failure — never throw the step (would flip monitor).
      reportSilentFallback(err, {
        feature: "cron-cloud-task-heartbeat",
        op: "stale-bot-pr-comment-failed",
        message: "stale-bot-PR comment handler failed before posting",
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
