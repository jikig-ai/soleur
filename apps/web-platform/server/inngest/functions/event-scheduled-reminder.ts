// Generic scheduled-reminder primitive — the reusable "reminder workflow".
//
// Triggered by a `reminder.scheduled` event whose payload carries a future
// delivery `ts` (set by the emit endpoint, NOT a boot-arm). Inngest natively
// schedules the delayed delivery — no step.sleepUntil. Unlike the 5 bespoke
// oneshots (each self-armed in server/index.ts at boot for ONE fixed action),
// this single function dispatches an ALLOWLISTED action so a future-dated
// comment or a registered check fires with NO per-reminder deploy — only this
// one-time function deploy. Arm it via POST /api/internal/schedule-reminder.
//
// Canonical precedent: oneshot-4650-monitor-close.ts. ADR-046 = self-arm /
// registered-functions-only; ADR-033 = runtime invariants:
//   I1 — all outbound IO inside step.run (Inngest replay memoization).
//   I2 — operator-owned data only (installation token; no BYOK lease).
//   I5 — deterministic step.run return shapes (plain JSON union).
//   I6 — N/A (this function emits no Inngest events).
// Per ADR-033's prefix table a oneshot-class (non-recurring) function gets NO
// Sentry cron monitor (it would false-alert on missed check-ins); failures
// route via reportSilentFallback. The token is minted INSIDE step.run and never
// returned into persisted step state.
//
// ROUTE↔HANDLER ASYMMETRY (intentional defense-in-depth): the emit endpoint
// validates `check` is a non-empty string only — it must NOT import the
// server-only CHECK_REGISTRY (which pulls octokit). The HANDLER owns the
// registry-membership reject. So an unregistered check armed via the endpoint
// is accepted at the door (202) but rejected at fire time (reportSilentFallback
// + no-op). This is a guard, not a gap.

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  mintInstallationToken,
  REPO_OWNER,
  REPO_NAME,
  type HandlerArgs,
} from "./_cron-shared";
import {
  validateReminderAction,
  isValidIsoInstant,
  type ReminderEventData,
} from "@/lib/inngest/scheduled-reminder-action";

const FUNCTION_NAME = "event-scheduled-reminder";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

type CheckResult = { verdict: "pass" | "fail" | "info"; body: string };
type OctokitClient = { request: (route: string, params?: unknown) => Promise<unknown> };
type CheckFn = (
  octokit: OctokitClient,
  params: Record<string, unknown> | undefined,
) => Promise<CheckResult>;

// CHECK_REGISTRY — server-side, code-reviewed only. Seeded with ONE read-only
// demonstrator so the registry mechanism is exercised by a test. A `named-check`
// reminder dispatches ONLY to a key in this map; an unregistered check is
// rejected at fire time. v1 entries MUST be read-only or comment-only (no issue
// close/edit/label mutation). Adding an entry is a code-reviewed change.
export const CHECK_REGISTRY: Record<string, CheckFn> = {
  // Trivial demonstrator: how many `cloud-task-silence` issues are open.
  "open-silence-issue-count": async (octokit) => {
    const res = await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      labels: "cloud-task-silence",
      state: "open",
      per_page: 100,
    });
    const count = (res as { data: unknown[] }).data.length;
    return {
      verdict: "info" as const,
      body: `\`open-silence-issue-count\`: ${count} open \`cloud-task-silence\` issue(s) at ${new Date().toISOString()}.`,
    };
  },
};

type HandlerResult = { ok: false; reason: string } | { ok: true; reason: string };

export async function eventScheduledReminderHandler({
  event,
  step,
}: HandlerArgs & { event: { data: ReminderEventData } }): Promise<HandlerResult> {
  const { data } = event;

  // --- Guards FIRST (mirror oneshot-4650 ordering) -------------------------
  if (!isValidIsoInstant(data.fire_at)) {
    reportSilentFallback(
      new Error(`Invalid fire_at: ${JSON.stringify(data.fire_at)}`),
      {
        feature: FUNCTION_NAME,
        op: "invalid-fire-at",
        message: "fire_at must be a real ISO instant",
        extra: { fn: FUNCTION_NAME, raw: String(data.fire_at).slice(0, 30) },
      },
    );
    return { ok: false, reason: "invalid-fire-at" };
  }

  const validated = validateReminderAction(data.action);
  if (!validated.ok) {
    reportSilentFallback(
      new Error(`Rejected reminder action: ${validated.reason}`),
      {
        feature: FUNCTION_NAME,
        op: validated.reason,
        message: "reminder action failed the allowlist",
        extra: { fn: FUNCTION_NAME, reminder_id: data.reminder_id },
      },
    );
    return { ok: false, reason: validated.reason };
  }
  const action = validated.action;

  // --- issue-comment: post a comment via the installation token ------------
  if (action.type === "issue-comment") {
    return await step.run("post-comment", async () => {
      const token = await mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
      });
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: token });
      try {
        await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: action.issue,
            body: action.body,
          },
        );
        return { ok: true as const, reason: "issue-comment-posted" };
      } catch (err) {
        reportSilentFallback(err, {
          feature: FUNCTION_NAME,
          op: "issue-comment",
          message: `failed to post comment to #${action.issue}`,
          extra: { fn: FUNCTION_NAME, issue: action.issue },
        });
        return { ok: false as const, reason: "issue-comment-failed" };
      }
    });
  }

  // --- named-check: run a registered check, post its body, alert on fail ---
  return await step.run("run-check", async () => {
    const check = CHECK_REGISTRY[action.check];
    if (!check) {
      // Registry-membership reject (the route accepted a string `check`; the
      // server-only registry is the source of truth).
      reportSilentFallback(
        new Error(`Unregistered named-check: ${action.check}`),
        {
          feature: FUNCTION_NAME,
          op: "unregistered-check",
          message: "named-check is not in CHECK_REGISTRY",
          extra: { fn: FUNCTION_NAME, check: action.check },
        },
      );
      return { ok: false as const, reason: "unregistered-check" };
    }

    const token = await mintInstallationToken({
      tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
    });
    const { Octokit } = await import("@octokit/core");
    const octokit = new Octokit({ auth: token });

    let result: CheckResult;
    try {
      result = await check(octokit, action.params);
    } catch (err) {
      reportSilentFallback(err, {
        feature: FUNCTION_NAME,
        op: "named-check-threw",
        message: `check "${action.check}" threw`,
        extra: { fn: FUNCTION_NAME, check: action.check },
      });
      return { ok: false as const, reason: "named-check-threw" };
    }

    try {
      await octokit.request(
        "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          issue_number: action.report_to_issue,
          body: result.body,
        },
      );
    } catch (err) {
      reportSilentFallback(err, {
        feature: FUNCTION_NAME,
        op: "named-check-report",
        message: `failed to post check result to #${action.report_to_issue}`,
        extra: { fn: FUNCTION_NAME, issue: action.report_to_issue },
      });
      return { ok: false as const, reason: "named-check-report-failed" };
    }

    // A failing verdict is a real signal — route to Sentry at error level even
    // though the report comment was posted.
    if (result.verdict === "fail") {
      reportSilentFallback(
        new Error(`named-check "${action.check}" verdict=fail`),
        {
          feature: FUNCTION_NAME,
          op: "named-check-failed",
          message: `check "${action.check}" reported fail`,
          extra: { fn: FUNCTION_NAME, check: action.check },
        },
      );
    }
    return { ok: true as const, reason: `named-check-${result.verdict}` };
  });
}

export const eventScheduledReminder = inngest.createFunction(
  {
    id: "event-scheduled-reminder",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  { event: "reminder.scheduled" },
  eventScheduledReminderHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
