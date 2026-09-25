// #8719 — the leader-loop dead-letter marker for agent.spawn.requested.
//
// `persistFailure` in inngest/functions/agent-on-spawn-requested.ts reports every
// dead-lettered spawn here. `sentry_alert.spawn_agent_dead_letter`
// (infra/sentry/issue-alerts.tf) emails the operator for the reasons
// `PAGES_OPERATOR` (lib/failure-reason.ts) marks `true`, filtering on the
// `feature`, `op` and `reason` tags this module sets.
//
// COVERAGE (#8803): two paths report here. (1) `persistFailure`, for every
// failure the handler itself catches — no lifecycle suffix. (2) The lifecycle
// settle (`agent-on-spawn-settle`, reached from the handler's `onFailure` forward
// and from `inngest/function.cancelled`), for a run the handler never finished —
// a retry-exhausted throw, the `finish` timeout or an Inngest-level cancel —
// with a `(failed)`, `(cancelled)`, `(timed_out)` or `(settle_failed)` suffix.
// Two gaps remain: a run Inngest loses entirely (no lifecycle event fires), and a
// `persist-failure` UPDATE that fails inside `persistFailure` (it returns
// normally, so no lifecycle event fires; `reportSpawnPersistFailed` reports it,
// but the card stays on "Working"). Both are tracked in #8839.
//
// Triage per suffix: knowledge-base/engineering/operations/runbooks/spawn-dead-letter-triage.md.
//
// MESSAGE PATH ON PURPOSE — do not pass the Error through "for a stack trace". On
// the Error path, `reportSilentFallback` logs first, the pino mirror
// (server/logger.ts `mirrorToSentry`) captures the SAME Error instance as
// `feature=pino-mirror`, and @sentry/core's `checkOrSetAlreadyCaught` then drops
// the second, tagged capture, so the event arrives with no `feature`/`op`/`reason`
// and the alert never matches it (#8629). `toMessagePathError` turns the error
// into a plain object: `reportSilentFallback` then uses `captureMessage`, the pino
// hook has no Error to capture, and the SDK's message and stack still reach Sentry
// (`extra.err`) and the pino line for triage. It is one of several #8629
// workarounds (`git grep -n '#8629' -- apps/web-platform/server`); revert them
// together when #8629 lands.
//
// Never build the plain object with `...err`: that would carry the Anthropic SDK
// error's response `headers` and structured `error` body, and a PostgREST error's
// `details`/`hint`. Copy the named fields only. The SDK's own `message` still
// embeds the vendor body's JSON text; that is the triage payload #8717 chose.
//
// GROUPING: the event is a message event, so Sentry groups it by message text.
// The message carries the reason AND the action class, so each (reason, class)
// pair is its own issue with its own alert throttle — one class failing cannot
// hide a second class failing the same way inside an already-throttled issue.

import * as Sentry from "@sentry/nextjs";

import { PAGES_OPERATOR, type FailureReason } from "@/lib/failure-reason";
import logger from "@/server/logger";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";

/** Sentry tag literals. `sentry-spawn-dead-letter-alert-op-contract.test.ts` pins the alert filter to these. */
export const SPAWN_DEAD_LETTER_FEATURE = "spawn-agent";
export const SPAWN_DEAD_LETTER_OP = "agent-on-spawn-requested";

/** The reasons the alert's `reason` filter lists, sorted. Derived from PAGES_OPERATOR, never re-typed. */
export const PAGED_DEAD_LETTER_REASONS: readonly FailureReason[] = Object.freeze(
  (Object.keys(PAGES_OPERATOR) as FailureReason[]).filter((r) => PAGES_OPERATOR[r]).sort(),
);

/**
 * How a run the handler never finished ended (#8803). `settle_failed` is the
 * settle step itself failing, kept distinct so it never hides inside a real
 * crash's Sentry issue.
 */
export type SpawnLifecycle = "failed" | "cancelled" | "timed_out" | "settle_failed";

/**
 * The Sentry/pino message for one dead-letter. Grouping key: see GROUPING above.
 * A lifecycle is appended so each cause is its own issue and throttle; without
 * one (the in-body `persistFailure` path) the text is unchanged.
 */
export function spawnDeadLetterMessage(
  reason: FailureReason,
  actionClass: string,
  lifecycle?: SpawnLifecycle,
): string {
  const base = `agent-on-spawn deadlettered: ${reason} [${actionClass}]`;
  return lifecycle ? `${base} (${lifecycle})` : base;
}

interface MessagePathError {
  name: string;
  message: string;
  stack?: string;
  code?: string;
}

function readString(obj: object, key: string): string | undefined {
  // Plain property read: works on a prototype-less object and never calls a
  // toString. A throwing getter still throws; the caller's try/catch owns that.
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
  actionClass: string,
  lifecycle: SpawnLifecycle | undefined,
): Record<string, unknown> {
  const { founderId, ...rest } = extra ?? {};
  const out: Record<string, unknown> = { ...rest, reason, actionClass };
  if (lifecycle !== undefined) out.lifecycle = lifecycle;
  if (founderId !== undefined) out.userId = founderId;
  return out;
}

/**
 * Report a leader-loop dead-letter. Paged reasons are `error` events; the rest
 * are `warning` events, so they neither match the paging rule nor become
 * high-priority issues for Sentry's default alert. Never throws: a throw here
 * would skip the caller's `persist-failure` step and leave the founder's card
 * without a terminal state. A failure inside the report is itself reported,
 * tagged so the alert still matches a paged reason.
 */
export function reportSpawnDeadLetter(args: {
  reason: FailureReason;
  actionClass: string;
  err: unknown;
  lifecycle?: SpawnLifecycle;
  extra?: Record<string, unknown>;
}): void {
  const { reason, actionClass, lifecycle } = args;
  try {
    const emit = PAGES_OPERATOR[reason] ? reportSilentFallback : warnSilentFallback;
    emit(toMessagePathError(args.err), {
      feature: SPAWN_DEAD_LETTER_FEATURE,
      op: SPAWN_DEAD_LETTER_OP,
      message: spawnDeadLetterMessage(reason, actionClass, lifecycle),
      tags: { reason },
      extra: toReportExtra(args.extra, reason, actionClass, lifecycle),
    });
  } catch (caught) {
    const suffix = lifecycle ? ` (${lifecycle})` : "";
    const message = `agent-on-spawn deadlettered: report failed: ${reason} [${actionClass}]${suffix}`;
    try {
      logger.error(
        { err: caught, reason, actionClass, feature: SPAWN_DEAD_LETTER_FEATURE, op: SPAWN_DEAD_LETTER_OP },
        message,
      );
    } catch {
      // review: swallowed — the tagged captureMessage below is the remaining signal.
    }
    try {
      Sentry.captureMessage(message, {
        level: "error",
        tags: { feature: SPAWN_DEAD_LETTER_FEATURE, op: SPAWN_DEAD_LETTER_OP, reason },
        extra: { actionClass },
      });
    } catch {
      // review: swallowed — observability must never break the terminal write.
    }
  }
}

/**
 * The terminal `action_sends.failure_reason` write failed: the founder's card
 * has no terminal state. Reported on the message path with the row id and a
 * pseudonymized founder id (the Inngest ctx logger is not pino, so it would
 * log the raw id). Never throws.
 */
export function reportSpawnPersistFailed(args: {
  reason: FailureReason;
  actionSendId: string;
  founderId: string;
  err: unknown;
}): void {
  try {
    reportSilentFallback(toMessagePathError(args.err), {
      feature: SPAWN_DEAD_LETTER_FEATURE,
      op: "persist-failure",
      message: "agent-on-spawn: persist-failure UPDATE failed; terminal state not recorded",
      tags: { reason: args.reason },
      extra: { actionSendId: args.actionSendId, userId: args.founderId, reason: args.reason },
    });
  } catch {
    // review: swallowed — observability must never break the dead-letter return.
  }
}
