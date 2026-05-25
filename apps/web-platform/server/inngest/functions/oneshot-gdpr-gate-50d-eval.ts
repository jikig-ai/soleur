// TR9 PR-G (#3948, #4461) — one-shot Inngest function: 50-day GDPR-gate eval.
//
// Fires once on 2026-06-29 09:00 UTC (or re-armed 90-day checkpoint), counts
// escaped gdpr-gate Critical findings over the post-#3501 window, and posts
// a structured comment on #3516.
//
// ADR-033 invariants:
//   I1 — Octokit reads inside step.run (memoized across replays).
//   I2 — Operator-owned data only; never founder BYOK.
//   I5 — Deterministic step.run return shapes.
//   I6 — Re-arm event carries actor: "platform".
//
// Handler template: cron-strategy-review.ts (pure-TS Octokit, no clone,
// no claude-eval spawn).

import { inngest } from "@/server/inngest/client";
import { createProbeOctokit } from "@/server/github/probe-octokit";
import { generateInstallationToken } from "@/server/github-app";
import { reportSilentFallback } from "@/server/observability";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "oneshot-gdpr-gate-50d-eval";
const SENTRY_HEARTBEAT_TIMEOUT_MS = 10_000;

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const REPO_OWNER = "jikig-ai";
const REPO_NAME = "soleur";

const SENTRY_DOMAIN_RE = /^[a-z0-9.-]+\.sentry\.io$/i;
const SENTRY_PROJECT_RE = /^\d+$/;
const SENTRY_PUBLIC_KEY_RE = /^[a-f0-9]{32}$/;

const TELEMETRY_MARKER = "cq-gdpr-gate-critical-finding";
const ESCAPED_PR_LABELS_RE = /compliance|gdpr|pii/i;
const MAX_PAGES = 10;
const PER_PAGE = 100;

// =============================================================================
// Types
// =============================================================================

interface EventData {
  issue: number;
  comment_id: number;
  expected_date: string;
  expectedAuthor: string;
  date_override?: string;
  actor?: "platform";
}

interface HandlerArgs {
  event: { data: EventData };
  step: { run<T>(name: string, cb: () => Promise<T>): Promise<T> };
  logger: {
    info: (...a: unknown[]) => void;
    warn: (...a: unknown[]) => void;
    error: (...a: unknown[]) => void;
  };
}

type HandlerResult =
  | { ok: false; reason: string }
  | { ok: true; telemetryCount: number; escapedCount: number; recommendation: string };

// =============================================================================
// Helpers
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
      { fn: SENTRY_MONITOR_SLUG },
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
      { fn: SENTRY_MONITOR_SLUG },
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
      feature: SENTRY_MONITOR_SLUG,
      op: "sentry-heartbeat",
      message: "Sentry heartbeat POST failed",
      extra: { fn: SENTRY_MONITOR_SLUG, status, aborted: e.name === "TimeoutError" },
    });
  }
}

function buildCommentBody(args: {
  telemetryCount: number;
  escapedCount: number;
  recommendation: string;
  expectedDate: string;
}): string {
  const { telemetryCount, escapedCount, recommendation, expectedDate } = args;
  const now = new Date().toISOString();
  let action: string;
  if (recommendation === "data-incomplete") {
    action = "**Data incomplete** — escaped PR count failed (API error). Manual review required.";
  } else if (recommendation === "re-schedule-90d") {
    action = "Re-arm 90-day checkpoint. Zero escapes detected.";
  } else if (recommendation === "re-schedule-90d-with-cases") {
    action = `Re-arm 90-day checkpoint. ${escapedCount} escape(s) detected — review individually.`;
  } else {
    action = `**Recommend wiring Check 10 now.** ${escapedCount} escape(s) detected.`;
  }

  return [
    `## GDPR-Gate 50-Day Eval — ${expectedDate}`,
    "",
    `| Metric | Value |`,
    `|--------|-------|`,
    `| Telemetry count (\`${TELEMETRY_MARKER}\`) | ${telemetryCount === -1 ? "N/A (file not found)" : telemetryCount} |`,
    `| Escaped PRs (merged with compliance/gdpr/pii label) | ${escapedCount} |`,
    `| Recommendation | \`${recommendation}\` |`,
    "",
    `**Action:** ${action}`,
    "",
    `---`,
    `_Automated by \`oneshot-gdpr-gate-50d-eval\` at ${now}. actor: platform._`,
  ].join("\n");
}

// =============================================================================
// Handler
// =============================================================================

export async function oneshotGdprGate50dEvalHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<HandlerResult> {
  const { data } = event;

  // --- D3 date guard ---------------------------------------------------------
  if (data.date_override !== undefined && !/^\d{4}-\d{2}-\d{2}$/.test(data.date_override)) {
    const err = new Error(
      `Invalid date_override format: ${JSON.stringify(data.date_override)}`,
    );
    reportSilentFallback(err, {
      feature: SENTRY_MONITOR_SLUG,
      op: "date-override-validation",
      message: "date_override must be YYYY-MM-DD",
      extra: { fn: SENTRY_MONITOR_SLUG, raw: String(data.date_override) },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, logger });
    });
    return { ok: false, reason: "invalid-date-override" };
  }
  const today = data.date_override ?? new Date().toISOString().slice(0, 10);
  if (today !== data.expected_date) {
    const err = new Error(
      `D3 date guard: today=${today} !== expected=${data.expected_date}`,
    );
    reportSilentFallback(err, {
      feature: SENTRY_MONITOR_SLUG,
      op: "date-guard",
      message: "D3 date guard rejected — wrong execution date",
      extra: { fn: SENTRY_MONITOR_SLUG, today, expected: data.expected_date },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, logger });
    });
    return { ok: false, reason: "date-guard" };
  }

  // --- Step 1: mint installation token ---------------------------------------
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      const octokit = await createProbeOctokit();
      const { data: installation } = await (octokit as any).request(
        "GET /repos/{owner}/{repo}/installation",
        { owner: REPO_OWNER, repo: REPO_NAME },
      );
      return generateInstallationToken(installation.id, {
        minRemainingMs: TOKEN_MIN_LIFETIME_MS,
      });
    },
  );

  // --- Step 2: eval-and-post -------------------------------------------------
  const result = await step.run("eval-and-post", async () => {
    const { Octokit: OctokitCtor } = await import("@octokit/core");
    const octokit = new OctokitCtor({ auth: installationToken });

    // Author check
    const commentRes = await octokit.request(
      "GET /repos/{owner}/{repo}/issues/comments/{comment_id}",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        comment_id: data.comment_id,
      },
    );
    const actualAuthor = (commentRes.data as any).user?.login;
    if (actualAuthor !== data.expectedAuthor) {
      const err = new Error(
        `Author mismatch: expected=${data.expectedAuthor}, actual=${actualAuthor}`,
      );
      reportSilentFallback(err, {
        feature: SENTRY_MONITOR_SLUG,
        op: "author-check",
        message: "Comment author does not match expected author",
        extra: { fn: SENTRY_MONITOR_SLUG, expected: data.expectedAuthor, actual: actualAuthor },
      });
      return { ok: false as const, reason: "author-mismatch" };
    }

    // Step (a): telemetry count via Contents API
    let telemetryCount: number;
    try {
      const contentsRes = await octokit.request(
        "GET /repos/{owner}/{repo}/contents/{path}",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          path: ".claude/hooks/incidents.log",
        },
      );
      const content = Buffer.from(
        (contentsRes.data as any).content,
        "base64",
      ).toString("utf8");
      telemetryCount = (content.match(new RegExp(TELEMETRY_MARKER, "g")) || []).length;
    } catch (err: any) {
      if (err?.status === 404) {
        telemetryCount = -1;
      } else {
        reportSilentFallback(err, {
          feature: SENTRY_MONITOR_SLUG,
          op: "telemetry-fetch",
          message: "Failed to fetch incidents.log via Contents API",
          extra: { fn: SENTRY_MONITOR_SLUG },
        });
        telemetryCount = -1;
      }
    }

    // Step (b): escaped PR count
    let escapedCount = 0;
    try {
      const startDate = "2026-05-10";
      const endDate = data.expected_date;
      for (let page = 1; page <= MAX_PAGES; page++) {
        const pullsRes = await octokit.request(
          "GET /repos/{owner}/{repo}/pulls",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            state: "closed",
            per_page: PER_PAGE,
            page,
          },
        );
        const pulls = pullsRes.data as any[];
        if (pulls.length === 0) break;

        for (const pr of pulls) {
          if (!pr.merged_at) continue;
          const mergedDate = pr.merged_at.slice(0, 10);
          if (mergedDate < startDate || mergedDate > endDate) continue;
          const labels: string[] = (pr.labels || []).map((l: any) => l.name || "");
          if (labels.some((l) => ESCAPED_PR_LABELS_RE.test(l))) {
            escapedCount++;
          }
        }

        if (pulls.length < PER_PAGE) break;
      }
    } catch (err) {
      reportSilentFallback(err, {
        feature: SENTRY_MONITOR_SLUG,
        op: "escaped-pr-count",
        message: "Failed to count escaped PRs via Pulls API",
        extra: { fn: SENTRY_MONITOR_SLUG },
      });
      escapedCount = -1;
    }

    // Step (c): outcome matrix
    let recommendation: string;
    if (escapedCount === -1) {
      recommendation = "data-incomplete";
    } else if (escapedCount === 0) {
      recommendation = "re-schedule-90d";
    } else if (escapedCount <= 2) {
      recommendation = "re-schedule-90d-with-cases";
    } else {
      recommendation = "wire-check-10-now";
    }

    // Step (d): post comment on #3516
    const body = buildCommentBody({
      telemetryCount,
      escapedCount,
      recommendation,
      expectedDate: data.expected_date,
    });
    try {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: data.issue,
          body,
        },
      );
    } catch (err) {
      reportSilentFallback(err, {
        feature: SENTRY_MONITOR_SLUG,
        op: "post-comment",
        message: "Failed to post eval comment on issue",
        extra: { fn: SENTRY_MONITOR_SLUG, issue: data.issue },
      });
      return { ok: false as const, reason: "comment-post-failed" };
    }

    return { ok: true as const, telemetryCount, escapedCount, recommendation };
  });

  // Early return if eval-and-post failed (author mismatch)
  if (!result.ok) {
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, logger });
    });
    return result as HandlerResult;
  }

  // --- Step 3: sentry-heartbeat ----------------------------------------------
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({ ok: true, logger });
  });

  // --- Conditional re-arm: 90-day checkpoint (inside step.run for replay safety) ---
  if (result.recommendation.startsWith("re-schedule")) {
    await step.run("re-arm-90d-checkpoint", async () => {
      await inngest.send({
        name: "oneshot/gdpr-gate-50d-eval.fire",
        id: "gdpr-gate-90d-eval-2026-08-10-v1",
        ts: new Date("2026-08-10T09:00:00Z").getTime(),
        data: {
          issue: data.issue,
          comment_id: data.comment_id,
          expected_date: "2026-08-10",
          expectedAuthor: data.expectedAuthor,
          actor: "platform" as const,
        },
      });
    });
    logger.info(
      { fn: SENTRY_MONITOR_SLUG },
      "Re-armed 90-day checkpoint for 2026-08-10",
    );
  }

  return result as HandlerResult;
}

// =============================================================================
// Registration
// =============================================================================

export const oneshotGdprGate50dEval = inngest.createFunction(
  {
    id: "oneshot-gdpr-gate-50d-eval",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "oneshot/gdpr-gate-50d-eval.fire" },
  oneshotGdprGate50dEvalHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
