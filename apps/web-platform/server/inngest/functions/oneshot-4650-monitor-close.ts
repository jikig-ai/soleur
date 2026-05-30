// One-time Inngest oneshot (#4654): autonomous bookkeeping close of #4650.
//
// On/after 2026-05-31 09:00 UTC, reads the Inngest /v1/functions registry and
// classifies the 3 cron functions whose Sentry monitors #4650 tracks. If all 3
// are re-planned (H9a/H9b cleared per the watchdog's taxonomy) AND #4650 is
// still OPEN, closes it with an explanatory comment via the GitHub App token.
//
// Self-armed from server/index.ts boot block (deploy-and-forget) — no manual
// `inngest send`. See ADR-046.
//
// CLOSE-CONDITION (NOT Sentry check-in): #4650's root cause is de-planned cron
// triggers. classifyRegistry "OK" proves the cron is PLANNED, not that it is
// successfully checking in — a planned-but-failing cron still classifies OK.
// Accepted gap: the watchdog's own `scheduled-inngest-cron-watchdog` Sentry
// monitor pages on real check-in failure, so a premature close (worst case) is
// bounded to a self-recovering internal issue. The close-comment wording
// reflects "cron triggers re-planned", not "monitors healthy".
//
// ADR-033 invariants:
//   I1 — all outbound IO inside step.run (replay memoization).
//   I2 — operator-owned data only (App token, no BYOK lease).
//   I5 — deterministic step.run return shapes (plain JSON union).
//   I6 — event payload carries actor:"platform".
// Per ADR-033's prefix table, oneshots get NO Sentry cron monitor (would
// false-alert on a non-recurring fn); errors route via reportSilentFallback.
// (oneshot-gdpr-gate-50d-eval.ts declares a monitor — a known deviation we do
// NOT follow here.)

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import {
  mintInstallationToken,
  REPO_OWNER,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  fetchRegistry,
  classifyRegistry,
  resolveInngestHost,
  type ClassifyResult,
} from "./cron-inngest-cron-watchdog";

const FUNCTION_NAME = "oneshot-4650-monitor-close";

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// The 3 cron functions backing #4650's Sentry monitors (1:1 with the monitor
// slugs scheduled-{gh-pages-cert-state,community-monitor,inngest-cron-watchdog}).
const TARGET_FN_IDS = [
  "cron-gh-pages-cert-state",
  "cron-community-monitor",
  "cron-inngest-cron-watchdog",
];

interface EventData {
  issue: number;
  expected_date: string;
  date_override?: string;
  actor?: "platform";
}

type HandlerResult = { ok: false; reason: string } | { ok: true; reason: string };

// Validate a YYYY-MM-DD string is both well-shaped AND a real calendar date
// ("2026-13-45" is well-shaped but not a real date — sf P2-2).
function isValidYmd(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

export async function oneshot4650MonitorCloseHandler({
  event,
  step,
}: HandlerArgs & { event: { data: EventData } }): Promise<HandlerResult> {
  const { data } = event;

  // --- D3 guard (on-or-after — explicit K5 override vs the strict-equality
  // pattern; the load-bearing idempotency guarantee is the already-closed check
  // below, not this guard). -------------------------------------------------
  if (data.date_override !== undefined && !isValidYmd(data.date_override)) {
    reportSilentFallback(
      new Error(`Invalid date_override: ${JSON.stringify(data.date_override)}`),
      {
        feature: FUNCTION_NAME,
        op: "date-override-validation",
        message: "date_override must be a real YYYY-MM-DD date",
        extra: { fn: FUNCTION_NAME, raw: String(data.date_override).slice(0, 20) },
      },
    );
    return { ok: false, reason: "invalid-date-override" };
  }
  const today = data.date_override ?? new Date().toISOString().slice(0, 10);
  if (today < data.expected_date) {
    // Early replay/desync — expected and benign, so warn-level (not error).
    warnSilentFallback(
      new Error(`date guard: today=${today} < expected=${data.expected_date}`),
      {
        feature: FUNCTION_NAME,
        op: "date-guard",
        message: "fired before expected_date — no-op",
        extra: { fn: FUNCTION_NAME, today, expected: data.expected_date },
      },
    );
    return { ok: false, reason: "date-guard" };
  }

  // --- Step 1: issue state + token (load-bearing idempotency) ---------------
  const issue = await step.run("check-issue-state", async () => {
    const token = await mintInstallationToken({
      tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
    });
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: token });
    const res = await octokit.request(
      "GET /repos/{owner}/{repo}/issues/{issue_number}",
      { owner: REPO_OWNER, repo: REPO_NAME, issue_number: data.issue },
    );
    return { token, state: (res.data as { state?: string }).state ?? "open" };
  });

  // --- Step 2: classify the 3 target cron functions ------------------------
  const classify = await step.run("classify-registry", async () => {
    try {
      const host = resolveInngestHost(process.env.INNGEST_BASE_URL);
      const registry = await fetchRegistry(host);
      const results = classifyRegistry(registry, TARGET_FN_IDS);
      return { ok: true as const, results };
    } catch (err) {
      reportSilentFallback(err, {
        feature: FUNCTION_NAME,
        op: "registry-fetch",
        message: "Inngest /v1/functions read failed",
        extra: { fn: FUNCTION_NAME },
      });
      return { ok: false as const, results: [] as ClassifyResult[] };
    }
  });

  const allOk = classify.ok && classify.results.every((r) => r.status === "OK");
  const unhealthy = classify.results.filter((r) => r.status !== "OK");

  // --- Already-closed: still audit health so a FOREIGN close over a real
  // de-plan is not silently masked as success (sf P1-2). --------------------
  if (issue.state === "closed") {
    if (classify.ok && unhealthy.length > 0) {
      reportSilentFallback(
        new Error(
          `#${data.issue} already closed but ${unhealthy.length} cron(s) not OK`,
        ),
        {
          feature: FUNCTION_NAME,
          op: "already-closed-unhealthy",
          message: "#4650 closed by another actor while a cron is de-planned",
          extra: { fn: FUNCTION_NAME, unhealthy },
        },
      );
    }
    return { ok: true, reason: "already-closed" };
  }

  // --- Open + registry unreadable → fail-safe (do NOT close) ----------------
  if (!classify.ok) {
    return { ok: false, reason: "registry-fetch-failed" };
  }

  // --- Open + not all healthy → leave open, alert, NO comment ---------------
  if (!allOk) {
    reportSilentFallback(
      new Error(`#${data.issue} not closed: ${unhealthy.length} cron(s) not OK`),
      {
        feature: FUNCTION_NAME,
        op: "not-all-healthy",
        message: "cron triggers not all re-planned — leaving #4650 open",
        extra: { fn: FUNCTION_NAME, unhealthy },
      },
    );
    return { ok: false, reason: "not-all-healthy" };
  }

  // --- Open + all 3 re-planned → close #4650 -------------------------------
  const closed = await step.run("close-issue", async () => {
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: issue.token });
    const body = [
      `## Autonomous close — all 3 cron triggers re-planned`,
      "",
      `The Inngest \`/v1/functions\` registry shows all 3 cron functions behind`,
      `this issue's monitors are present and cron-planned (H9a/H9b cleared):`,
      "",
      ...TARGET_FN_IDS.map((f) => `- \`${f}\` — OK`),
      "",
      `_Closed by \`${FUNCTION_NAME}\` on ${new Date().toISOString()}. actor: platform._`,
      `_Note: registry-presence proves the cron is re-planned, not that it is`,
      `checking in; the \`scheduled-inngest-cron-watchdog\` Sentry monitor remains`,
      `the page-on-real-check-in-failure backstop._`,
    ].join("\n");
    try {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        { owner: REPO_OWNER, repo: REPO_NAME, issue_number: data.issue, body },
      );
      await octokit.request(
        "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: data.issue,
          state: "closed",
        },
      );
      return { ok: true as const };
    } catch (err) {
      reportSilentFallback(err, {
        feature: FUNCTION_NAME,
        op: "close-issue",
        message: "failed to comment/close #4650",
        extra: { fn: FUNCTION_NAME, issue: data.issue },
      });
      return { ok: false as const };
    }
  });

  return closed.ok
    ? { ok: true, reason: "closed" }
    : { ok: false, reason: "close-failed" };
}

export const oneshot4650MonitorClose = inngest.createFunction(
  {
    id: "oneshot-4650-monitor-close",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "oneshot/monitor-close-4650.fire" },
  oneshot4650MonitorCloseHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
