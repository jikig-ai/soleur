// SLA lifecycle WORKER for the `action-required` staleness contract (#6836).
//
// Processes ONE issue per invocation (fanned out by cron-action-required-sla.ts). Failure-
// isolated: one slow/failing issue never aborts the batch. Holds the close authority — every
// mutation is fail-safe (allowlist policy), replay-safe (deterministic step ids), and idempotent
// against live GitHub state (D2 sentinel-marker dedup + TOCTOU re-assert).
//
// This is the ONLY place issues are mutated; all decisions come from the pure policy module.

import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  type HandlerArgs,
} from "./_cron-shared";
import {
  classifyIssue,
  decideAction,
  isHumanEngaged,
  lastNonBotActivityMs,
  buildSentinelMarker,
  hasSentinel,
  EXPIRE_INACTIVE_DAYS,
  PRIORITY_RANK,
  WONTFIX_STALE_LABEL,
  type ActivityEvent,
  type Assignee,
  type SlaAction,
} from "./action-required-sla-policy";

export const PROCESS_ISSUE_EVENT = "cron/action-required-sla.process-issue";
// Event-fired worker (no schedule) — deliberately declares NO SENTRY_MONITOR_SLUG /
// sentry_cron_monitor (a crontab monitor would page MISSED forever on a fn that has no
// cadence). Failure observability is `reportSilentFallback` (the emit() error path, D6).
const SLA_FEATURE = "sla-issue-process";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;
const DAY_MS = 86_400_000;

interface FreshIssue {
  number: number;
  state: string;
  labels: string[];
  assignees: Assignee[];
  createdAt: string;
  updatedAt: string;
  events: ActivityEvent[];
}

/** Re-fetch the issue + its timeline fresh (TOCTOU — the list snapshot is stale, D2/D3). */
async function fetchFreshIssue(client: Octokit, issueNumber: number): Promise<FreshIssue> {
  const issue = (await client.request("GET /repos/{owner}/{repo}/issues/{issue_number}", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    issue_number: issueNumber,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  })) as {
    data: {
      state: string;
      updated_at: string;
      created_at: string;
      labels: Array<string | { name?: string }>;
      assignees?: Array<{ login: string; type?: string }> | null;
    };
  };
  const timeline = (await client.request(
    "GET /repos/{owner}/{repo}/issues/{issue_number}/timeline",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      issue_number: issueNumber,
      per_page: 100,
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    },
  )) as { data: Array<{ actor?: { login?: string; type?: string } | null; created_at?: string }> };

  return {
    number: issueNumber,
    state: issue.data.state,
    updatedAt: issue.data.updated_at,
    createdAt: issue.data.created_at,
    labels: issue.data.labels
      .map((l) => (typeof l === "string" ? l : (l.name ?? "")))
      .filter(Boolean),
    assignees: (issue.data.assignees ?? []).map((a) => ({ login: a.login, type: a.type })),
    events: timeline.data
      .filter((e) => e.created_at)
      .map((e) => ({ actor: e.actor?.login, actorType: e.actor?.type, at: e.created_at as string })),
  };
}

function highestPriorityLabel(labels: string[]): string | null {
  let best: string | null = null;
  let bestRank = 0;
  for (const l of labels) {
    const r = PRIORITY_RANK[l] ?? 0;
    if (r > bestRank) {
      bestRank = r;
      best = l;
    }
  }
  return best;
}

/** GET the issue's comments and true if the action/threshold sentinel is already present (D2). */
async function sentinelAlreadyPosted(
  client: Octokit,
  issueNumber: number,
  action: SlaAction,
  threshold: string,
): Promise<boolean> {
  const res = (await client.request("GET /repos/{owner}/{repo}/issues/{issue_number}/comments", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    issue_number: issueNumber,
    per_page: 100,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  })) as { data: Array<{ body?: string }> };
  return res.data.some((c) => hasSentinel(c.body ?? "", action, threshold));
}

export async function slaIssueProcessHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; action: string }> {
  const data = (event?.data ?? {}) as {
    issueNumber?: number;
    listedUpdatedAt?: string;
    runStartedAt?: string;
  };
  const issueNumber = data.issueNumber;
  const listedUpdatedAt = data.listedUpdatedAt;
  const runStartedMs = data.runStartedAt ? Date.parse(data.runStartedAt) : Date.now();

  if (!issueNumber) return { ok: true, action: "skip:no-issue" };

  const emit = (action: SlaAction | "toctou-abort" | "error", extra: Record<string, unknown>) =>
    reportSilentFallback(new Error(`action-required-sla ${action} #${issueNumber}`), {
      feature: SLA_FEATURE,
      op: "action-required-sla",
      message: `SLA ${action} on #${issueNumber}`,
      // `human_engaged` is a TAG (not just extra) so the Sentry alert can filter on the
      // FEARED case: an expire that slipped past the veto (human_engaged=true → the veto
      // failed, an invariant violation). Sentry alert filters match tags, never extra.
      tags: { sla_action: action, human_engaged: String(Boolean(extra.humanEngaged)) },
      extra: { issue: issueNumber, ...extra },
    });

  try {
    const token = await step.run(`mint-token-${issueNumber}`, async () =>
      mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
    );

    const decision = await step.run(`assess-${issueNumber}`, async () => {
      const { Octokit } = await import("@octokit/core");
      const client = new Octokit({ auth: token }) as unknown as Octokit;
      const fresh = await fetchFreshIssue(client, issueNumber);

      // TOCTOU (D2): the issue changed between the dispatcher's list snapshot and now — an
      // operator may have relabeled/commented/reopened. Abort; the next run re-evaluates.
      if (listedUpdatedAt && fresh.updatedAt !== listedUpdatedAt) {
        emit("toctou-abort", { listedUpdatedAt, freshUpdatedAt: fresh.updatedAt });
        return { action: "skip" as SlaAction, reason: "toctou", cls: "ops", humanEngaged: false };
      }

      const cls = classifyIssue(fresh.labels);
      const createdMs = Date.parse(fresh.createdAt);
      const lastNonBot = lastNonBotActivityMs(fresh.events) ?? createdMs;
      const ageDays = Math.floor((runStartedMs - createdMs) / DAY_MS);
      const inactiveDays = Math.floor((runStartedMs - lastNonBot) / DAY_MS);
      // Veto: a non-bot assignee (standing ownership) OR a RECENT (<expiry window) non-bot
      // touch — a day-29 "still broken" comment must block the day-30 close (D1). Old non-bot
      // touches only set the inactivity clock; they do not veto.
      const recentEvents = fresh.events.filter(
        (e) => Date.parse(e.at) >= runStartedMs - EXPIRE_INACTIVE_DAYS * DAY_MS,
      );
      const humanEngaged = isHumanEngaged({ assignees: fresh.assignees, events: recentEvents });

      const d = decideAction({
        cls,
        ageDays,
        inactiveDays,
        humanEngaged,
        currentPriority: highestPriorityLabel(fresh.labels),
        labels: fresh.labels,
        closed: fresh.state === "closed",
      });
      return {
        action: d.action,
        targetPriority: d.targetPriority,
        reason: d.reason,
        cls,
        ageDays,
        inactiveDays,
        humanEngaged,
        currentPriority: highestPriorityLabel(fresh.labels),
      };
    });

    if (decision.action === "escalate" && decision.targetPriority) {
      await step.run(`escalate-${issueNumber}-${decision.targetPriority}`, async () => {
        const { Octokit } = await import("@octokit/core");
        const client = new Octokit({ auth: token }) as unknown as Octokit;
        // Idempotent comment: skip if this action/threshold's sentinel is already present (D2).
        if (!(await sentinelAlreadyPosted(client, issueNumber, "escalate", decision.targetPriority!))) {
          await client.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: issueNumber,
            body:
              `This has been open ${decision.ageDays} days and still needs you. Bumping priority to ` +
              `\`${decision.targetPriority}\`.\n\n${buildSentinelMarker("escalate", decision.targetPriority!)}`,
            headers: { "X-GitHub-Api-Version": "2022-11-28" },
          });
        }
        // Adding a label is idempotent on GitHub (a set operation).
        await client.request("POST /repos/{owner}/{repo}/issues/{issue_number}/labels", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: issueNumber,
          labels: [decision.targetPriority!],
          headers: { "X-GitHub-Api-Version": "2022-11-28" },
        });
        emit("escalate", {
          class: decision.cls,
          ageDays: decision.ageDays,
          priorityBefore: decision.currentPriority,
          priorityAfter: decision.targetPriority,
          humanEngaged: decision.humanEngaged,
        });
      });
    } else if (decision.action === "expire") {
      await step.run(`expire-${issueNumber}`, async () => {
        const { Octokit } = await import("@octokit/core");
        const client = new Octokit({ auth: token }) as unknown as Octokit;
        if (!(await sentinelAlreadyPosted(client, issueNumber, "expire", "stale"))) {
          await client.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: issueNumber,
            body:
              `Auto-closing: no owner activity for ${decision.inactiveDays} days. ` +
              (decision.cls === "dead-content"
                ? "The distribution gap is tracked by the standing `content-starvation` signal."
                : "This decision-challenge's reversal window elapsed unreviewed.") +
              ` Reopen if you still need it.\n\n${buildSentinelMarker("expire", "stale")}`,
            headers: { "X-GitHub-Api-Version": "2022-11-28" },
          });
        }
        await client.request("POST /repos/{owner}/{repo}/issues/{issue_number}/labels", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: issueNumber,
          labels: [WONTFIX_STALE_LABEL],
          headers: { "X-GitHub-Api-Version": "2022-11-28" },
        });
        await client.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: issueNumber,
          state: "closed",
          state_reason: "not_planned",
          headers: { "X-GitHub-Api-Version": "2022-11-28" },
        });
        emit("expire", {
          class: decision.cls,
          ageDays: decision.ageDays,
          inactiveDays: decision.inactiveDays,
          humanEngaged: decision.humanEngaged,
        });
      });
    }

    return { ok: true, action: decision.action };
  } catch (err) {
    // Event worker: no cron heartbeat. The error is durably captured via emit() →
    // reportSilentFallback → Sentry (D6 failure observability).
    emit("error", { message: (err as Error).message });
    return { ok: false, action: "error" };
  }
}

export const slaIssueProcess = inngest.createFunction(
  {
    id: "sla-issue-process",
    concurrency: [{ scope: "fn", limit: 3 }],
    retries: 1,
  },
  { event: PROCESS_ISSUE_EVENT },
  slaIssueProcessHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
