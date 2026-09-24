// #8719 — the leader-loop dead-letter marker for agent.spawn.requested.
//
// `persistFailure` in inngest/functions/agent-on-spawn-requested.ts reports every
// dead-lettered spawn here. `sentry_alert.spawn_agent_dead_letter`
// (infra/sentry/issue-alerts.tf) emails the operator for the reasons
// `PAGES_OPERATOR` (lib/failure-reason.ts) marks `true`, filtering on the
// `feature`, `op` and `reason` tags this module sets.
//
// MESSAGE PATH ON PURPOSE — do not pass the Error through "for a stack trace". On
// the Error path, `reportSilentFallback` logs first, the pino mirror
// (server/logger.ts `mirrorToSentry`) captures the SAME Error instance as
// `feature=pino-mirror`, and @sentry/core's `checkOrSetAlreadyCaught` then drops
// the second, tagged capture, so the event arrives with no `feature`/`op`/`reason`
// and the alert never matches it (#8629). `toMessagePathError` turns the error
// into a plain object: `reportSilentFallback` then uses `captureMessage`, the pino
// hook has no Error to capture, and the SDK's message and stack still reach Sentry
// (`extra.err`) and the pino line for triage. `server/anthropic-credit.ts` is the
// sibling workaround; revert both together when #8629 lands.
//
// Never build the plain object with `...err`: the Anthropic SDK error carries its
// response `headers` and vendor body, and a PostgREST error its `details`/`hint`.
// Copy the named fields only.

import * as Sentry from "@sentry/nextjs";

import type { FailureReason } from "@/lib/failure-reason";
import { PAGES_OPERATOR } from "@/lib/failure-reason";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

/** Sentry tag literals. `sentry-spawn-dead-letter-alert-op-contract.test.ts` pins the alert filter to these. */
export const SPAWN_DEAD_LETTER_FEATURE = "spawn-agent";
export const SPAWN_DEAD_LETTER_OP = "agent-on-spawn-requested";

/** The reasons the alert's `reason` filter lists, sorted. Derived from PAGES_OPERATOR, never re-typed. */
export const PAGED_DEAD_LETTER_REASONS: readonly FailureReason[] = (
  Object.keys(PAGES_OPERATOR) as FailureReason[]
)
  .filter((r) => PAGES_OPERATOR[r])
  .sort();

const REPORT_FAILED_MESSAGE = "agent-on-spawn deadlettered: report failed";

interface MessagePathError {
  name: string;
  message: string;
  stack?: string;
  code?: string;
}

function readString(obj: object, key: string): string | undefined {
  // Plain property read: works on a prototype-less object and never calls a
  // toString that could throw.
  const v = (obj as Record<string, unknown>)[key];
  return typeof v === "string" ? v : undefined;
}

/** A fresh plain object with the triage fields only — never an Error instance. */
function toMessagePathError(err: unknown): MessagePathError {
  if (err === null || err === undefined) return { name: "Error", message: String(err) };
  if (typeof err === "string") return { name: "Error", message: err };
  if (typeof err !== "object") return { name: "Error", message: String(err) };
  const out: MessagePathError = {
    name: readString(err, "name") ?? "Error",
    message: readString(err, "message") ?? "",
  };
  const stack = readString(err, "stack");
  if (stack !== undefined) out.stack = stack;
  // Keeps pg_code for a direct caller passing a PostgREST error. An error that
  // crossed a step boundary has lost `code` already (inngest's StepError).
  const code = readString(err, "code");
  if (code !== undefined) out.code = code;
  return out;
}

/** `founderId` → `userId`, which reportSilentFallback pseudonymizes to `userIdHash`. */
function toReportExtra(
  extra: Record<string, unknown> | undefined,
  reason: FailureReason,
): Record<string, unknown> {
  const { founderId, ...rest } = extra ?? {};
  const out: Record<string, unknown> = { ...rest, reason };
  if (founderId !== undefined) out.userId = founderId;
  return out;
}

/**
 * A model-chosen tool name, safe for a log line and a Sentry field: kept when it
 * matches the tool-name shape, otherwise replaced (no control characters, line
 * separators or unbounded length).
 */
export function safeToolName(name: string): string {
  return /^[A-Za-z0-9_-]{1,64}$/.test(name) ? name : "[invalid]";
}

/**
 * Report a leader-loop dead-letter. Never throws: a throw here would skip the
 * caller's `persist-failure` step and leave the founder's card without a
 * terminal state. A failure inside the report is itself reported, tagged so the
 * alert still matches a paged reason.
 */
export function reportSpawnDeadLetter(args: {
  reason: FailureReason;
  err: unknown;
  extra?: Record<string, unknown>;
}): void {
  const { reason } = args;
  try {
    reportSilentFallback(toMessagePathError(args.err), {
      feature: SPAWN_DEAD_LETTER_FEATURE,
      op: SPAWN_DEAD_LETTER_OP,
      message: `agent-on-spawn deadlettered: ${reason}`,
      tags: { reason },
      extra: toReportExtra(args.extra, reason),
    });
  } catch (caught) {
    try {
      logger.error(
        { err: caught, reason, feature: SPAWN_DEAD_LETTER_FEATURE, op: SPAWN_DEAD_LETTER_OP },
        REPORT_FAILED_MESSAGE,
      );
    } catch {
      // review: swallowed — the tagged captureMessage below is the remaining signal.
    }
    try {
      Sentry.captureMessage(REPORT_FAILED_MESSAGE, {
        level: "error",
        tags: { feature: SPAWN_DEAD_LETTER_FEATURE, op: SPAWN_DEAD_LETTER_OP, reason },
      });
    } catch {
      // review: swallowed — observability must never break the terminal write.
    }
  }
}
