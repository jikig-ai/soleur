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
import {
  parseSentryRateParams,
  buildSentryUrl,
  computeRatePerDay,
} from "@/lib/inngest/sentry-issue-rate";

const FUNCTION_NAME = "event-scheduled-reminder";
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;
const SENTRY_FETCH_TIMEOUT_MS = 10_000;

// `close?: boolean` is the v1→v1.1 capability: a check may REQUEST that the
// handler close `action.report_to_issue`. It is deliberately a boolean, NOT a
// `close_issue: number` — the close target is structurally the action's own
// report_to_issue, so a check can never name an arbitrary issue to close (the
// scope-violation is unrepresentable). See ADR-063.
type CheckResult = { verdict: "pass" | "fail" | "info"; body: string; close?: boolean };
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

  // Reusable, parametric Sentry-rate verification (#5417 follow-on). Reads the
  // events/day of the Sentry issue matched by `tag` over `window_hours`; PASS
  // (and optionally close report_to_issue) iff rate <= max_per_day. Uses fetch
  // (Sentry REST), NOT octokit — `octokit` is unused here. Reads fire-time prd
  // env (the whole point: a GHA runner could not). Fail-CLOSED (`info`, no
  // close) on any inability to verify: missing env, invalid params, Sentry HTTP
  // error, 0-or->1 matching issues, or a malformed stats shape. Errors are
  // constructed TOKEN-FREE (reportSilentFallback forwards err.message raw).
  "sentry-issue-rate": async (_octokit, params) => {
    const failClosed = (reason: string): CheckResult => ({
      verdict: "info" as const,
      body: `\`sentry-issue-rate\`: fail-closed — ${reason}. No action taken.`,
      close: false,
    });

    const parsed = parseSentryRateParams(params);
    if (!parsed.ok) return failClosed(parsed.reason);
    const { tag, maxPerDay, windowHours, closeOnPass } = parsed.value;

    const host = process.env.SENTRY_API_HOST;
    const org = process.env.SENTRY_ORG;
    const project = process.env.SENTRY_PROJECT;
    // The live Phase-0 probe established that SENTRY_AUTH_TOKEN/SENTRY_API_TOKEN
    // 403 on the org issues endpoint; SENTRY_ISSUE_RW_TOKEN is the issue-scoped
    // token with the required read. (We READ here; the close is a GitHub PATCH.)
    const token = process.env.SENTRY_ISSUE_RW_TOKEN;
    if (!host || !org || !project || !token) {
      return failClosed("Sentry env not configured");
    }

    // Single bounded fetch helper. The token lives ONLY in the Authorization
    // header — never in the URL or any thrown/returned string — so error text
    // is token-free by construction.
    const sentryGet = async (url: string): Promise<unknown> => {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(), SENTRY_FETCH_TIMEOUT_MS);
      try {
        const res = await fetch(url, {
          headers: { Authorization: `Bearer ${token}` },
          signal: ctrl.signal,
        });
        if (!res.ok) {
          throw new Error(`Sentry GET returned HTTP ${res.status}`);
        }
        return await res.json();
      } finally {
        clearTimeout(timer);
      }
    };

    try {
      const searchUrl = buildSentryUrl(
        host,
        `/api/0/organizations/${encodeURIComponent(org)}/issues/`,
        { query: tag, project },
      );
      const issues = await sentryGet(searchUrl);
      if (!Array.isArray(issues) || issues.length !== 1) {
        const n = Array.isArray(issues) ? issues.length : 0;
        return failClosed(`expected exactly 1 issue for tag \`${tag}\`, found ${n}`);
      }
      const issueId = (issues[0] as { id?: unknown }).id;
      if (typeof issueId !== "string" && typeof issueId !== "number") {
        return failClosed("matched issue has no id");
      }

      const statsUrl = buildSentryUrl(
        host,
        `/api/0/organizations/${encodeURIComponent(org)}/issues/${encodeURIComponent(String(issueId))}/stats/`,
        { stat: "14d" },
      );
      const stats = await sentryGet(statsUrl);
      if (!Array.isArray(stats)) {
        return failClosed("unexpected stats shape");
      }
      const { sum, days, ratePerDay } = computeRatePerDay(
        stats as Array<[number, number]>,
        windowHours,
      );

      const pass = ratePerDay <= maxPerDay;
      const rateStr = ratePerDay.toFixed(2);
      const verdict = pass ? ("pass" as const) : ("fail" as const);
      const tail = pass
        ? closeOnPass
          ? " Closing the report issue (close_on_pass)."
          : " Threshold met (close_on_pass not set — leaving open)."
        : " Still above threshold — leaving open.";
      return {
        verdict,
        close: pass && closeOnPass,
        body: `\`sentry-issue-rate\` **${verdict}**: tag \`${tag}\` ~${rateStr}/day over ${windowHours}h (sum ${sum} events / ${days}d; threshold ${maxPerDay}/day).${tail}`,
      };
    } catch (err) {
      // Token-free message: `err.message` is either our `HTTP <code>` string or
      // an AbortError/network error — none contain the Authorization header.
      const msg = err instanceof Error ? err.message : String(err);
      return failClosed(`Sentry query failed (${msg.slice(0, 80)})`);
    }
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

    // v1.1 close capability: when the check REQUESTS a close (result.close ===
    // true), close THIS action's report_to_issue — never a check-returned
    // number (the boolean shape makes an arbitrary-issue close unrepresentable).
    if (result.close === true) {
      try {
        await octokit.request(
          "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: action.report_to_issue,
            state: "closed",
            state_reason: "completed",
          },
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: FUNCTION_NAME,
          op: "named-check-close",
          message: `failed to close #${action.report_to_issue}`,
          extra: { fn: FUNCTION_NAME, issue: action.report_to_issue },
        });
        return {
          ok: true as const,
          reason: `named-check-${result.verdict}-close-failed`,
        };
      }
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
