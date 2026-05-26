// TR9 Phase 2 T9 — Weekly nag on issue #4216 (PR-I milestone tracking).
//
// Migrated from .github/workflows/scheduled-nag-4216-readiness.yml
// (deleted in the same PR per TR9 I-13 hygiene). Pure TS port — no bash
// script, no gh CLI. All GitHub ops via Octokit.
//
// ADR-033 invariants:
//   I1 — Octokit called INSIDE step.run (Inngest replay memoization).
//        No claude-eval spawn (pure TS port).
//   I2 — Operator-owned data only; never founder BYOK.
//   I5 — Deterministic step.run return shape per step.

import type { Octokit } from "@octokit/core";
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
// Constants — exported for tests
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-nag-4216-readiness";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

export const ISSUE_NUMBER = 4216;
export const PR_I_MERGE_DATE = "2026-05-21";

// =============================================================================
// Handler
// =============================================================================

export async function cronNag4216ReadinessHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  skipped?: boolean;
  daysSince?: number;
}> {
  // Step 1: mint installation token
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // Step 2: check issue state and post nag if open
  const result = await step.run(
    "check-and-nag",
    async (): Promise<{ ok: boolean; skipped?: boolean; daysSince?: number }> => {
      const { Octokit: OctokitCtor } = await import("@octokit/core");
      const octokit = new OctokitCtor({
        auth: installationToken,
      }) as unknown as Octokit;

      // Fetch issue state
      let issueState: string;
      try {
        const resp = await octokit.request(
          "GET /repos/{owner}/{repo}/issues/{issue_number}",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: ISSUE_NUMBER,
          },
        );
        issueState = (resp.data as { state?: string }).state ?? "unknown";
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-nag-4216-readiness",
          op: "get-issue",
          message: `Failed to fetch issue #${ISSUE_NUMBER}`,
          extra: { fn: "cron-nag-4216-readiness" },
        });
        return { ok: false };
      }

      // If not open, skip
      if (issueState.toUpperCase() !== "OPEN") {
        logger.info(
          { fn: "cron-nag-4216-readiness", issueState },
          `Issue #${ISSUE_NUMBER} is ${issueState} — no nag needed.`,
        );
        return { ok: true, skipped: true };
      }

      // Calculate days since PR-I merge
      const daysSince = Math.floor(
        (Date.now() - new Date(PR_I_MERGE_DATE).getTime()) / 86_400_000,
      );
      const today = new Date().toISOString().slice(0, 10);

      const body = [
        `**Weekly readiness check (${today})** — PR-I (#4078) merged ${daysSince} days ago.`,
        "",
        "Re-evaluation criteria:",
        "- [ ] ≥1 cohort founder with `draft_one_click` send history",
        "- [ ] Misclassification signal exists",
        "",
        "If both met, re-run `/soleur:go #4216`. If neither, ignore this nag.",
        "",
        `_Posted by Inngest function \`cron-nag-4216-readiness\`. Delete the function to stop._`,
      ].join("\n");

      try {
        await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: ISSUE_NUMBER,
            body,
          },
        );
        logger.info(
          { fn: "cron-nag-4216-readiness", daysSince },
          `Posted readiness nag on #${ISSUE_NUMBER} (day ${daysSince} since PR-I).`,
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-nag-4216-readiness",
          op: "post-comment",
          message: `Failed to post nag comment on #${ISSUE_NUMBER}`,
          extra: { fn: "cron-nag-4216-readiness" },
        });
        return { ok: false, daysSince };
      }

      return { ok: true, daysSince };
    },
  );

  // Step 3: Sentry heartbeat
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: result.ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-nag-4216-readiness",
      logger,
    });
  });

  return result;
}

// =============================================================================
// Registration
// =============================================================================

export const cronNag4216Readiness = inngest.createFunction(
  {
    id: "cron-nag-4216-readiness",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 14 * * 1" },
    { event: "cron/nag-4216-readiness.manual-trigger" },
  ],
  cronNag4216ReadinessHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
