// PR #4457 — Stale deferred-scope-out sweep migrated to Inngest.
//
// Migrated from the GHA scheduled-stale-deferred-scope-outs workflow
// (deleted in the same PR). The work properly belongs in Inngest: it
// benefits from step.run memoization (per-issue progress survives Inngest
// replays) and the rest of the cron substrate (Sentry tagging via the
// inngest sentry-correlation middleware, reportSilentFallback mirroring).
//
// ADR-033 invariants (only load-bearing entries cited; sibling
// cron-github-app-drift-guard.ts uses the same convention):
//   I5 — Deterministic step.run return shape: {closed, skipped, total}.
//        Per-issue side effects (gh issue comment / close) live inside the
//        sweep step so replays memoize the aggregate counters; the per-call
//        gh-API write idempotency comes from GitHub's "already closed" tolerance.
//   I7 — Replay-safety: GH search `is:open` filter + close-is-no-op
//        semantics on retry + in-loop `state === "closed"` defensive guard
//        (GH Search has a ~30s eventual-consistency window where just-closed
//        issues may still surface; the guard short-circuits the comment/close
//        sequence in that window).
//
// POLICY CARRIED VERBATIM FROM THE GHA WORKFLOW:
//   - Cutoff: 90 days since last issue activity.
//   - Kill switch: `do-not-autoclose` label exempts an issue.
//   - Comment body: references PR #4452 (the original scope-out drain PR)
//     and the review-todo-structure runbook for re-evaluation triggers.
//
// DRY-RUN MODE: invoke via Inngest event `cron/stale-deferred-scope-outs.manual-trigger`
// with payload `{ data: { dry_run: true } }` — lists stale candidates
// without commenting or closing. Operators can fire from the Inngest
// dashboard or via `inngest.send({ name: "...", data: { dry_run: true } })`.
//
// NAME NOTE: Inngest function id is "cron-stale-deferred-scope-outs"
// (TR9 / ADR-033 convention).

import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  createProbeOctokit,
  PROBE_ISSUE_OWNER,
  PROBE_ISSUE_REPO,
} from "@/server/github/probe-octokit";

// 90 days, expressed in ms — matches `date -u -d '90 days ago'` from the
// original bash workflow.
const STALE_WINDOW_MS = 90 * 24 * 60 * 60 * 1000;

// Label sentinels.
const TARGET_LABEL = "deferred-scope-out";
const KILLSWITCH_LABEL = "do-not-autoclose";

// Search caps — bash workflow used `--limit 200`, mirrored here. Sorted
// oldest-first via `sort:updated-asc` so each daily fire makes steady
// progress on the tail of the backlog.
// GH's /search/issues caps at 100 items/page, so reaching the 200-item
// ceiling REQUIRES two requests (page=1, page=2). The bash precedent's
// `gh ... --limit 200` opaquely paginated under the hood.
const SEARCH_PER_PAGE = 100;
const SEARCH_MAX_RESULTS = 200;

// Sentry Crons heartbeat — mirrors cron-github-app-drift-guard substrate.
// Slug matches the Terraform sentry_cron_monitor.scheduled_stale_deferred_scope_outs
// resource `name` field for historical/check-in continuity.
const SENTRY_MONITOR_SLUG = "scheduled-stale-deferred-scope-outs";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;
const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

/**
 * Auto-close comment body — heredoc verbatim from the GHA workflow. Refers
 * to PR #4452 (the scope-out drain PR that introduced this sweep) and the
 * review-todo-structure runbook so re-filers know what re-evaluation
 * trigger to attach.
 */
const COMMENT_BODY = [
  "Auto-closing: this issue has been open with no activity for 90+ days.",
  "",
  "If the concern is still relevant, re-file with an updated re-evaluation trigger",
  "(date / counter / event-grep / dependency — see `plugins/soleur/skills/review/references/review-todo-structure.md`).",
  "Open-ended scope-outs accumulate into the backlog this auto-close exists to drain.",
  "",
  "See PR #4452 for rationale; apply the `do-not-autoclose` label to exempt.",
].join("\n");

// =============================================================================
// Sweep — pure logic, isolated for testability
// =============================================================================

interface SweepResult {
  total: number;
  closed: number;
  skipped: number;
  dryRun: boolean;
}

interface SweepCandidate {
  number: number;
  title: string;
  updatedAt: string;
  state: string;
  labels: Array<{ name: string }>;
}

interface SearchResponseItem {
  number?: number;
  title?: string;
  updated_at?: string;
  state?: string;
  labels?: Array<{ name?: string }>;
}

async function fetchCandidates(args: {
  octokit: Octokit;
  cutoffIso: string;
}): Promise<SweepCandidate[]> {
  const { octokit, cutoffIso } = args;
  // GH /search/issues caps at 100 items/page; reaching the 200-item ceiling
  // requires two requests. Loop short-circuits on either the cap (return)
  // or a short page (break).
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;
  const q = `repo:${owner}/${repo} is:issue is:open label:"${TARGET_LABEL}" updated:<${cutoffIso} sort:updated-asc`;
  const candidates: SweepCandidate[] = [];
  for (let page = 1; page <= 2; page++) {
    const res = await octokit.request("GET /search/issues", {
      q,
      per_page: SEARCH_PER_PAGE,
      page,
    });
    const items = (res.data?.items ?? []) as SearchResponseItem[];
    for (const item of items) {
      if (typeof item.number !== "number") continue;
      candidates.push({
        number: item.number,
        title: typeof item.title === "string" ? item.title : "",
        updatedAt: typeof item.updated_at === "string" ? item.updated_at : "",
        state: typeof item.state === "string" ? item.state : "open",
        labels: Array.isArray(item.labels)
          ? item.labels
              .filter((l): l is { name: string } => typeof l?.name === "string")
              .map((l) => ({ name: l.name }))
          : [],
      });
      if (candidates.length >= SEARCH_MAX_RESULTS) return candidates;
    }
    if (items.length < SEARCH_PER_PAGE) break;
  }
  return candidates;
}

/**
 * The sweep core. Exported for unit tests; the inngest-wrapped handler
 * below feeds it a real octokit + a logger.
 *
 * Returns counters. Side effects:
 *   - Posts a comment on each non-kill-switched candidate (unless dry-run).
 *   - Closes each commented issue (unless dry-run).
 *
 * Per-issue try/catch is intentional: a single 410 (issue archived) or
 * 422 (invalid state transition) from gh should NOT abort the rest of
 * the sweep. The error is mirrored to Sentry via reportSilentFallback
 * and the counter advances.
 */
export async function sweepStaleScopeOuts(args: {
  octokit: Octokit;
  now: Date;
  dryRun: boolean;
  logger: HandlerArgs["logger"];
}): Promise<SweepResult> {
  const { octokit, now, dryRun, logger } = args;
  const owner = PROBE_ISSUE_OWNER;
  const repo = PROBE_ISSUE_REPO;

  const cutoffMs = now.getTime() - STALE_WINDOW_MS;
  const cutoffIso = new Date(cutoffMs).toISOString().slice(0, 10); // YYYY-MM-DD
  logger.info(
    {
      fn: "cron-stale-deferred-scope-outs",
      cutoff: cutoffIso,
      dryRun,
    },
    "stale-deferred-scope-out sweep starting",
  );

  const candidates = await fetchCandidates({ octokit, cutoffIso });
  let closed = 0;
  let skipped = 0;

  for (const candidate of candidates) {
    const num = candidate.number;

    // Replay-safety (I7): the search `is:open` filter is eventually
    // consistent (~30s lag); on Inngest retry, a just-closed issue may
    // briefly resurface. Short-circuit here so we never re-comment a
    // closed issue.
    if (candidate.state === "closed") continue;

    const hasKillSwitch = candidate.labels.some(
      (l) => l.name === KILLSWITCH_LABEL,
    );
    if (hasKillSwitch) {
      logger.info(
        {
          fn: "cron-stale-deferred-scope-outs",
          number: num,
          title: candidate.title,
        },
        `SKIP #${num} (${KILLSWITCH_LABEL})`,
      );
      skipped += 1;
      continue;
    }

    logger.info(
      {
        fn: "cron-stale-deferred-scope-outs",
        number: num,
        updatedAt: candidate.updatedAt,
        title: candidate.title,
      },
      `CANDIDATE #${num}`,
    );

    if (dryRun) continue;

    try {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        {
          owner,
          repo,
          issue_number: num,
          body: COMMENT_BODY,
        },
      );
      await octokit.request(
        "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
        {
          owner,
          repo,
          issue_number: num,
          state: "closed",
          state_reason: "not_planned",
        },
      );
      closed += 1;
    } catch (err) {
      reportSilentFallback(err as Error, {
        feature: "cron-stale-deferred-scope-outs",
        op: "comment-and-close",
        message: "comment-or-close failed for one issue; sweep continues",
        extra: {
          fn: "cron-stale-deferred-scope-outs",
          number: num,
        },
      });
      // Counter does NOT advance on failure — surfaces in the final
      // total vs. closed delta so operators can spot persistent errors.
    }
  }

  return {
    total: candidates.length,
    closed,
    skipped,
    dryRun,
  };
}

// =============================================================================
// Handler entry point
// =============================================================================

interface HandlerArgs {
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
  event?: {
    data?: { dry_run?: unknown };
  };
}

export async function cronStaleDeferredScopeOutsHandler({
  step,
  logger,
  event,
}: HandlerArgs): Promise<SweepResult> {
  // dry_run lives on the event payload for manual-trigger fires. The cron
  // trigger has no event.data, so dryRun is false by default.
  const dryRun = event?.data?.dry_run === true;

  let result: SweepResult = {
    total: 0,
    closed: 0,
    skipped: 0,
    dryRun,
  };
  let sweepFailed = false;

  try {
    result = await step.run(
      "sweep-stale-deferred-scope-outs",
      async (): Promise<SweepResult> => {
        const octokit = await createProbeOctokit();
        return sweepStaleScopeOuts({
          octokit: octokit as unknown as Octokit,
          now: new Date(),
          dryRun,
          logger,
        });
      },
    );
  } catch (err) {
    sweepFailed = true;
    reportSilentFallback(err as Error, {
      feature: "cron-stale-deferred-scope-outs",
      op: "sweep",
      message: "stale-deferred-scope-out sweep threw",
      extra: { fn: "cron-stale-deferred-scope-outs", dryRun },
    });
    // Heartbeat below routes status="error"; we do NOT rethrow yet.
  }

  // Sentry heartbeat — single end-of-job POST mirroring drift-guard substrate.
  // Env-unset / malformed → graceful skip (heartbeat is OPTIONAL second-net;
  // missing it must not stop the function from completing).
  await step.run("sentry-heartbeat", async () => {
    const domain = process.env.SENTRY_INGEST_DOMAIN;
    const projectId = process.env.SENTRY_PROJECT_ID;
    const publicKey = process.env.SENTRY_PUBLIC_KEY;
    if (!domain || !projectId || !publicKey) {
      logger.info(
        { fn: "cron-stale-deferred-scope-outs" },
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
        { fn: "cron-stale-deferred-scope-outs" },
        "Sentry env malformed — skipping heartbeat",
      );
      return;
    }
    const status = sweepFailed ? "error" : "ok";
    const url = `https://${domain}/api/${projectId}/cron/${SENTRY_MONITOR_SLUG}/${publicKey}/?status=${status}`;
    try {
      await fetch(url, {
        method: "POST",
        signal: AbortSignal.timeout(SENTRY_HEARTBEAT_TIMEOUT_MS),
      });
    } catch (err) {
      reportSilentFallback(err as Error, {
        feature: "cron-sentry-heartbeat",
        op: "fetch",
        message: "Sentry Crons heartbeat POST failed",
        extra: {
          fn: "cron-stale-deferred-scope-outs",
          status,
          aborted: (err as Error).name === "TimeoutError",
        },
      });
    }
  });

  if (sweepFailed) {
    // Surface the sweep failure to the operator AFTER the heartbeat has
    // reported status=error. Throwing here triggers Inngest's retry policy.
    throw new Error("stale-deferred-scope-out sweep failed; see Sentry");
  }

  logger.info(
    {
      fn: "cron-stale-deferred-scope-outs",
      ...result,
    },
    `Auto-closed ${result.closed} stale ${TARGET_LABEL} issues (${result.skipped} skipped via ${KILLSWITCH_LABEL} label)`,
  );

  return result;
}

// =============================================================================
// Registration
// =============================================================================

// Twin triggers (mirror cron-github-app-drift-guard): cron at 12:00 UTC
// daily (matches the original GHA workflow's `0 12 * * *` schedule) plus
// an event-triggered manual fire so operators can dry-run or kick the
// sweep on demand without a separate function.
export const cronStaleDeferredScopeOuts = inngest.createFunction(
  {
    id: "cron-stale-deferred-scope-outs",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 12 * * *" },
    { event: "cron/stale-deferred-scope-outs.manual-trigger" },
  ],
  cronStaleDeferredScopeOutsHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);

// Test surface — exported only for vitest.
export const __TESTING__ = {
  TARGET_LABEL,
  KILLSWITCH_LABEL,
  sweepStaleScopeOuts,
};
