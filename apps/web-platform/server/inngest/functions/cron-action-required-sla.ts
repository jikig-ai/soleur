// SLA lifecycle DISPATCHER for the `action-required` escalation staleness contract (#6836).
//
// Architecture (deepen-plan D1): a per-issue loop of side-effecting GitHub mutations must NOT
// run in one function — a mid-run failure aborts the whole batch and a large backlog blows the
// 10-min wall clock. The dispatcher does ONE memoized paginated read of the full open backlog,
// then fans out ONE `sla/action-required.process-issue` event per issue. The WORKER
// (sla-issue-process.ts) processes each issue in its own failure-isolated invocation.
//
// ADR-033 invariants: I1 (Octokit inside step.run), I2 (operator-owned data only), I5
// (deterministic step return shape). The dispatcher performs NO issue mutation — only the worker
// holds close authority.

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
import { PROCESS_ISSUE_EVENT } from "./sla-issue-process";

const SENTRY_MONITOR_SLUG = "cron-action-required-sla";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;
const ACTION_REQUIRED_LABEL = "action-required";

// `step.sendEvent` is present on the real Inngest step but not on the shared HandlerArgs type
// (which only declares `.run`). Type it locally so the fan-out is replay-safe and memoized.
type DispatchStep = HandlerArgs["step"] & {
  sendEvent(
    id: string,
    events: Array<{ name: string; data: Record<string, unknown>; id?: string }>,
  ): Promise<unknown>;
};

interface BacklogIssue {
  number: number;
  updatedAt: string;
}

/** Paginate the FULL open action-required backlog to exhaustion (D2 — a single page drops the
 * oldest escalate/expire candidates, which sort onto the far page). PRs are excluded. */
async function readBacklog(client: Octokit): Promise<BacklogIssue[]> {
  const out: BacklogIssue[] = [];
  for (let page = 1; page <= 20; page++) {
    const res = (await client.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      state: "open",
      labels: ACTION_REQUIRED_LABEL,
      per_page: 100,
      page,
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    })) as { data: Array<{ number: number; updated_at: string; pull_request?: unknown }> };
    for (const i of res.data) {
      if (i.pull_request) continue; // the issues endpoint also returns PRs
      out.push({ number: i.number, updatedAt: i.updated_at });
    }
    if (res.data.length < 100) break;
  }
  return out;
}

export async function cronActionRequiredSlaHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; dispatched: number }> {
  try {
    // Memoized run anchor — the worker computes age/inactivity against this single clock (D3).
    const runStartedAt = await step.run("run-started-at", async () => new Date().toISOString());

    const token = await step.run("mint-installation-token", async () =>
      mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
    );

    const backlog = await step.run("read-backlog", async () => {
      const { Octokit } = await import("@octokit/core");
      const client = new Octokit({ auth: token }) as unknown as Octokit;
      return readBacklog(client);
    });

    if (backlog.length > 0) {
      await (step as DispatchStep).sendEvent(
        "fan-out-issues",
        backlog.map((i) => ({
          name: PROCESS_ISSUE_EVENT,
          // `id` dedups a DISPATCHER replay within the run; a new daily run has a new
          // runStartedAt and re-dispatches (correct — thresholds may have crossed). The
          // worker is idempotent against live state (sentinel dedup + TOCTOU) regardless.
          id: `sla-${i.number}-${runStartedAt}`,
          data: {
            issueNumber: i.number,
            listedUpdatedAt: i.updatedAt, // TOCTOU token for the worker (D3/D2)
            runStartedAt,
          },
        })),
      );
    }

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: SENTRY_MONITOR_SLUG, logger }),
    );

    return { ok: true, dispatched: backlog.length };
  } catch (err) {
    reportSilentFallback(err, {
      feature: SENTRY_MONITOR_SLUG,
      op: "dispatcher-top-level",
      message: (err as Error).message,
    });
    try {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: SENTRY_MONITOR_SLUG, logger });
    } catch {
      // best-effort
    }
    return { ok: false, dispatched: 0 };
  }
}

export const cronActionRequiredSla = inngest.createFunction(
  {
    id: "cron-action-required-sla",
    concurrency: [{ scope: "fn", limit: 1 }],
    retries: 1,
  },
  [
    // Weekly, aligned with the operator digest cadence (Fridays).
    { cron: "0 12 * * 5" },
    { event: "cron/action-required-sla.manual-trigger" },
  ],
  cronActionRequiredSlaHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
