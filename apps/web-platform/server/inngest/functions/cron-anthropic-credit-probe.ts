// #5674 — Anthropic credit/auth canary probe (hourly).
//
// The 2026-06-29 incident: the operator Anthropic API credit balance hit zero
// and EVERY claude-eval cron after that received `Credit balance is too low`
// (HTTP 400) and silently no-op'd with GREEN monitors. Nothing paged when the
// whole fleet went dark — the exhaustion was found only by manual log spelunking.
//
// This probe is the canary: an hourly 1-token message on the OPERATOR
// ANTHROPIC_API_KEY (the same key the claude-eval substrate already holds —
// ADR-033 I2; it MUST NOT take a founder BYOK lease, which is a different key
// and would not detect operator-credit exhaustion). A 1-token
// ping is the success contract here (unlike the audit crons, where output — not
// the exit code — is success): a clean reply proves the fleet can do work.
//
// NO BALANCE ENDPOINT EXISTS (verified live 2026-06-29 against the Anthropic
// usage/cost API docs): the only signals are the canary 400/401 (this probe) and
// the Admin cost_report spend trend (a deferred follow-up needing a new
// sk-ant-admin secret + an operator budget). So this probe alerts AT exhaustion,
// within one hourly interval — not before it. The pre-exhaustion spend-vs-budget
// alert is tracked as a `Ref #5674` follow-up.
//
// CLASSIFY, do NOT false-page: only a CLASSIFIED fatal body pages.
//   - body matches /credit balance is too low/i → op=anthropic-credit-exhausted, monitor RED
//   - 401 / auth marker                         → op=anthropic-key-invalid, monitor RED
//   - transient/unclassified (429/500/529/net)  → RE-THROW → Inngest retry; the
//     missed-checkin margin backstops. A 529 overloaded is NOT an empty wallet;
//     paging it as credit-exhausted would itself be the alert-fatigue bug.
//   - clean reply                               → ok:true (liveness AND success).

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  postSentryHeartbeat,
  postAnthropicMessage,
  AnthropicApiError,
  ANTHROPIC_CREDIT_EXHAUSTED_RE,
  ANTHROPIC_AUTH_FAILURE_RE,
  type HandlerArgs,
} from "./_cron-shared";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

const SENTRY_MONITOR_SLUG = "scheduled-anthropic-credit-probe";
const CRON_NAME = "cron-anthropic-credit-probe";

// 1-token canary timeout. Generous vs a normal ping so genuine network latency
// is a transient retry, not a false "fleet down" page.
const CANARY_TIMEOUT_MS = 30_000;

interface CanaryDecision {
  ok: boolean;
  errorSummary?: string;
  op?: "anthropic-credit-exhausted" | "anthropic-key-invalid";
}

export async function cronAnthropicCreditProbeHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean; errorSummary?: string }> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) {
    // Env misconfiguration, not credit exhaustion — page so the operator fixes
    // it (a probe that cannot run is itself a fleet-down signal).
    reportSilentFallback(new Error("ANTHROPIC_API_KEY not set"), {
      feature: CRON_NAME,
      op: "anthropic-key-missing",
      message: "Anthropic credit probe cannot run — ANTHROPIC_API_KEY unset",
      extra: { fn: CRON_NAME },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: CRON_NAME, logger });
    });
    return { ok: false, errorSummary: "ANTHROPIC_API_KEY not set" };
  }

  // The canary call + classification live INSIDE step.run so a transient re-throw
  // is retried by Inngest (the step retries, then the function throws on the final
  // attempt → run-log records it). A classified fatal returns a decision (no throw)
  // so the heartbeat below can flip the monitor red.
  const decision = await step.run(
    "anthropic-canary",
    async (): Promise<CanaryDecision> => {
      try {
        await postAnthropicMessage({
          apiKey,
          model: EXECUTION_MODEL,
          maxTokens: 1,
          messages: [{ role: "user", content: "ping" }],
          timeoutMs: CANARY_TIMEOUT_MS,
          // #cost-attribution (plan Phase 2, choke point #3): the canary's
          // tokens-only marker (cost_usd null — 1-token ping is ~$0).
          markerSource: CRON_NAME,
        });
        // Clean reply — liveness AND success.
        return { ok: true };
      } catch (err) {
        if (err instanceof AnthropicApiError) {
          const body = err.bodyExcerpt ?? "";
          if (ANTHROPIC_CREDIT_EXHAUSTED_RE.test(body)) {
            reportSilentFallback(
              new Error("Anthropic credit balance is too low (operator API credit exhausted)"),
              {
                feature: CRON_NAME,
                op: "anthropic-credit-exhausted",
                message:
                  "Operator Anthropic API credit is exhausted — the claude-eval fleet cannot do work until topped up",
                // bodyExcerpt is already redaction-scrubbed by the transport.
                extra: { fn: CRON_NAME, status: err.status, bodyExcerpt: err.bodyExcerpt },
              },
            );
            return {
              ok: false,
              errorSummary: "Anthropic credit balance is too low (operator credit exhausted)",
              op: "anthropic-credit-exhausted",
            };
          }
          if (err.status === 401 || ANTHROPIC_AUTH_FAILURE_RE.test(body)) {
            reportSilentFallback(
              new Error("Anthropic API authentication failure (invalid/revoked operator key)"),
              {
                feature: CRON_NAME,
                op: "anthropic-key-invalid",
                message:
                  "Operator Anthropic API key is invalid or revoked — the claude-eval fleet cannot do work",
                extra: { fn: CRON_NAME, status: err.status, bodyExcerpt: err.bodyExcerpt },
              },
            );
            return {
              ok: false,
              errorSummary: "Anthropic API key invalid/revoked",
              op: "anthropic-key-invalid",
            };
          }
        }
        // Transient / unclassified (429/500/529 overloaded / network / DNS, OR an
        // AnthropicApiError whose body matches no FATAL marker). RE-THROW so
        // Inngest retries and the missed-checkin margin backstops — do NOT page
        // as credit-exhausted (false-paging a 529 is itself the alert-fatigue bug).
        throw err;
      }
    },
  );

  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({ ok: decision.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: CRON_NAME, logger });
  });
  return { ok: decision.ok, errorSummary: decision.errorSummary };
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: hourly scheduled cron (:47, off-peak minute) + manual operator
// event `cron/anthropic-credit-probe.manual-trigger`. account-scope concurrency
// "cron-platform" limits to 1 simultaneous cron-* invocation across the node.

export const cronAnthropicCreditProbe = inngest.createFunction(
  {
    id: "cron-anthropic-credit-probe",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "47 * * * *" },
    { event: "cron/anthropic-credit-probe.manual-trigger" },
  ],
  cronAnthropicCreditProbeHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
