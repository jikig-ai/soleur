// One-time Inngest oneshot: verify the cron-cloud-task-heartbeat watchdog
// recovery after PR #4881 (false-positive calibration), on/after the
// 2026-06-04 09:30 UTC heartbeat run.
//
// PR #4881 fixed two false-positive [cloud-task-silence] alerts:
//   - legal-audit (#4875): never-produced grace (zero-rows → pending-first-run).
//   - strategy-review (#4874): removed from TASK_INVENTORY (conditional producer).
// This oneshot confirms in production that neither false positive RE-FIRES on
// the first post-deploy heartbeat run, and reports whether the genuine
// community-monitor failure (#4876) has recovered. It posts a verification
// summary to the tracking issue #2714 and routes a REGRESSION (a false positive
// that came back) to Sentry at error level.
//
// Self-armed from server/index.ts boot block (deploy-and-forget) — no manual
// `inngest send`. Mirrors oneshot-4650-monitor-close.ts (ADR-046).
//
// ADR-033 invariants:
//   I1 — all outbound IO inside step.run (replay memoization).
//   I2 — operator-owned data only (installation token, no BYOK lease).
//   I5 — deterministic step.run return shapes (plain JSON union).
//   I6 — event payload carries actor:"platform".
// Per ADR-033's prefix table, oneshots get NO Sentry cron monitor (would
// false-alert on a non-recurring fn); errors route via reportSilentFallback.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import {
  mintInstallationToken,
  REPO_OWNER,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";

const FUNCTION_NAME = "oneshot-heartbeat-recovery-verify";

// The tracking issue this oneshot reports its verdict to.
const TRACKING_ISSUE = 2714;

// The two false-positive silence-issue titles that MUST NOT reappear after
// PR #4881. Their presence as an OPEN issue is a regression (error-level).
const FALSE_POSITIVE_TITLES = [
  "[cloud-task-silence] legal-audit silent",
  "[cloud-task-silence] strategy-review silent",
] as const;

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

interface EventData {
  expected_date: string;
  date_override?: string;
  actor?: "platform";
}

type HandlerResult = { ok: false; reason: string } | { ok: true; reason: string };

// Validate a YYYY-MM-DD string is both well-shaped AND a real calendar date.
function isValidYmd(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}

export async function oneshotHeartbeatRecoveryVerifyHandler({
  event,
  step,
}: HandlerArgs & { event: { data: EventData } }): Promise<HandlerResult> {
  const { data } = event;

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
  if (!isValidYmd(data.expected_date)) {
    reportSilentFallback(
      new Error(`Invalid expected_date: ${JSON.stringify(data.expected_date)}`),
      {
        feature: FUNCTION_NAME,
        op: "expected-date-validation",
        message: "expected_date must be a real YYYY-MM-DD date",
        extra: { fn: FUNCTION_NAME, raw: String(data.expected_date).slice(0, 20) },
      },
    );
    return { ok: false, reason: "invalid-expected-date" };
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

  // --- Step 1: gather verification facts via the installation token --------
  const facts = await step.run("gather-facts", async () => {
    const token = await mintInstallationToken({
      tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
    });
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: token });

    // (a) my-fix invariant: NO open silence issue for the two false positives.
    const openSilence = await octokit.request(
      "GET /repos/{owner}/{repo}/issues",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        labels: "cloud-task-silence",
        state: "open",
        per_page: 100,
      },
    );
    const openTitles = (openSilence.data as Array<{ title: string }>).map(
      (i) => i.title,
    );
    const regressed = FALSE_POSITIVE_TITLES.filter((t) =>
      openTitles.includes(t),
    );

    // (b) community-monitor genuine recovery: did its daily run produce a
    // recent scheduled-community-monitor issue, and is its silence issue closed?
    const cmIssues = await octokit.request(
      "GET /repos/{owner}/{repo}/issues",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        labels: "scheduled-community-monitor",
        state: "all",
        per_page: 1,
        sort: "created",
        direction: "desc",
      },
    );
    const cmLatest = (cmIssues.data as Array<{ created_at: string }>)[0];
    const cmLatestCreatedAt = cmLatest?.created_at ?? null;
    const cmDaysSince = cmLatestCreatedAt
      ? Math.floor(
          (Date.parse(`${today}T23:59:59Z`) - Date.parse(cmLatestCreatedAt)) /
            (86400 * 1000),
        )
      : null;
    const communityMonitorRecovered =
      cmDaysSince !== null && cmDaysSince <= 1;

    return {
      regressed,
      openSilenceCount: openTitles.length,
      cmLatestCreatedAt,
      communityMonitorRecovered,
    };
  });

  // --- Step 2: post the verdict to the tracking issue ----------------------
  await step.run("post-verdict", async () => {
    const token = await mintInstallationToken({
      tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
    });
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: token });

    const myFixPass = facts.regressed.length === 0;
    const body = [
      `## Watchdog recovery verification — ${today} (PR #4881)`,
      "",
      `**Calibration fix (deterministic):** ${myFixPass ? "✅ PASS" : "🔴 REGRESSION"}`,
      myFixPass
        ? `- No open \`[cloud-task-silence]\` issue for legal-audit or strategy-review reappeared on the post-deploy heartbeat run.`
        : `- A false positive RE-FIRED: ${facts.regressed.map((t) => `\`${t}\``).join(", ")}. This is a regression in PR #4881.`,
      "",
      `**community-monitor genuine recovery:** ${facts.communityMonitorRecovered ? "✅ recovered" : "⏳ not yet"}`,
      `- Latest \`scheduled-community-monitor\` issue: ${facts.cmLatestCreatedAt ?? "none found"}.`,
      facts.communityMonitorRecovered
        ? `- The daily run produced a fresh digest issue (#4770/#4870 deploy effective).`
        : `- No fresh digest issue yet — community-monitor's daily run may still be failing (tracked by the in-flight community-monitor spawn-liveness work; not a new issue).`,
      "",
      `_Open \`cloud-task-silence\` issues at check time: ${facts.openSilenceCount}. content-generator/roadmap-review staying open is EXPECTED (their crons fire after this heartbeat)._`,
      "",
      `_Posted by \`${FUNCTION_NAME}\` at ${new Date().toISOString()}. actor: platform._`,
    ].join("\n");

    try {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        { owner: REPO_OWNER, repo: REPO_NAME, issue_number: TRACKING_ISSUE, body },
      );
    } catch (err) {
      reportSilentFallback(err, {
        feature: FUNCTION_NAME,
        op: "post-verdict",
        message: `failed to comment verdict on #${TRACKING_ISSUE}`,
        extra: { fn: FUNCTION_NAME, issue: TRACKING_ISSUE },
      });
    }
  });

  // --- Regression is an error; a clean pass is just an info return. --------
  if (facts.regressed.length > 0) {
    reportSilentFallback(
      new Error(
        `PR #4881 regression: false-positive silence issue(s) re-fired: ${facts.regressed.join(", ")}`,
      ),
      {
        feature: FUNCTION_NAME,
        op: "calibration-regression",
        message: "a [cloud-task-silence] false positive re-fired after PR #4881",
        extra: { fn: FUNCTION_NAME, regressed: facts.regressed },
      },
    );
    return { ok: false, reason: "calibration-regression" };
  }

  return { ok: true, reason: "verified" };
}

export const oneshotHeartbeatRecoveryVerify = inngest.createFunction(
  {
    id: "oneshot-heartbeat-recovery-verify",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "oneshot/heartbeat-recovery-verify.fire" },
  oneshotHeartbeatRecoveryVerifyHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
