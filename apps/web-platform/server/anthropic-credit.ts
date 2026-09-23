// #8505 — the named operator-credit-exhaustion marker.
//
// Every production path that calls Anthropic with the OPERATOR key reports credit
// exhaustion here, under one Sentry marker that `sentry_alert.anthropic_credit_exhausted`
// (infra/sentry/issue-alerts.tf) routes to the operator. Two chokepoints call it:
// `postAnthropicMessage` in inngest/functions/_cron-shared.ts (the credit-probe
// canary, compound-promote, weekly-release-digest) and `summarizeEmail` in
// email-triage/summarize.ts (the only SDK caller of the operator key).
//
// MESSAGE PATH ON PURPOSE — do not switch this to `reportSilentFallback(new Error(…))`
// "for a stack trace". On the Error path, `reportSilentFallback` logs first, the pino
// mirror (server/logger.ts `mirrorToSentry`) captures the SAME Error instance as
// `feature=pino-mirror`, and @sentry/core's `checkOrSetAlreadyCaught` then drops the
// second, tagged capture, so the event arrives with no `feature`/`op` and the alert
// never matches it. With `err = null` the call goes through `captureMessage`, and the
// pino hook has no Error to capture. The fleet-wide defect is tracked separately.
//
// The user's own BYOK traffic never reaches here: a user's exhausted credit is not
// operator exhaustion and must not page as such.

import { reportSilentFallback } from "@/server/observability";

/**
 * Credit-exhaustion body marker. Single source of truth — `_cron-shared.ts`
 * re-exports it for `classifyEvalFatal` and the credit probe. Deliberately does
 * NOT match `specified API usage limits`: a workspace or org spend cap is not an
 * empty wallet, and the CI key hitting its cap is intended behavior.
 */
export const ANTHROPIC_CREDIT_EXHAUSTED_RE = /credit balance is too low/i;

/** Sentry tag literals. `sentry-anthropic-credit-alert-op-contract.test.ts` pins the alert filter to these. */
export const ANTHROPIC_CREDIT_EXHAUSTED_FEATURE = "anthropic-credit";
export const ANTHROPIC_CREDIT_EXHAUSTED_OP = "anthropic-credit-exhausted";

const MESSAGE = "Anthropic credit balance is too low — operator key exhausted";

export function isAnthropicCreditExhausted(text: string | undefined): boolean {
  return typeof text === "string" && ANTHROPIC_CREDIT_EXHAUSTED_RE.test(text);
}

/**
 * Report operator-key credit exhaustion. `source` is low-cardinality
 * (`cron:<name>` or `email-triage`). Never pass the vendor body: the event
 * carries the constant message, the source tag, and the HTTP status only.
 */
export function reportAnthropicCreditExhausted(args: { source: string; status?: number }): void {
  reportSilentFallback(null, {
    feature: ANTHROPIC_CREDIT_EXHAUSTED_FEATURE,
    op: ANTHROPIC_CREDIT_EXHAUSTED_OP,
    message: MESSAGE,
    tags: { source: args.source },
    extra: { status: args.status },
  });
}
