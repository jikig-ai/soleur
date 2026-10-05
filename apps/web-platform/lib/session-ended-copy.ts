// Founder-facing copy for the WS `session_ended` lifecycle frame.
//
// The wire `reason` is a free-form `z.string()`
// (ws-zod-schemas.ts › sessionEndedSchema). Live emitters send
// `turn_complete` (agent-runner.ts per-turn end), `closed`
// (ws-handler.ts › case "close_conversation"), `user_aborted`
// (agent-runner.ts abort ack), or a terminal `WorkflowEndStatus`
// routed through cc-dispatcher.ts › TERMINAL_WORKFLOW_END_STATUSES
// (6 of the 9 variants today — the rest route to `{ type: "error" }`
// frames; the full-union keying below is deliberate forward-compat so
// promoting a status to terminal never lands copy-less).
// Rendering the raw token leaked internal enum names to founders
// ("Session ended: internal_error") — this module is the single
// source of truth for the transcript line, following the
// CONTEXT_RESET_COPY pattern in components/chat/chat-copy.ts
// (ADR-025 lifecycle-notice family).
//
// Voice mirrors server/cc-workflow-end-messages.ts ›
// WORKFLOW_END_USER_MESSAGES verbatim (pinned by the parity test in
// test/session-ended-copy.test.tsx): that map feeds the non-terminal
// `{ type: "error" }` path, this one feeds the terminal
// `session_ended` path.

import type { WorkflowEndStatus } from "./types";

/**
 * Every `reason` value the `session_ended` frame can carry: the
 * `WorkflowEndStatus` variants (whether they route to `session_ended`
 * today or could be promoted to it), plus the two lifecycle reasons
 * emitted outside the runner (`turn_complete`, `closed`).
 */
export type SessionEndedReason = WorkflowEndStatus | "turn_complete" | "closed";

/**
 * Reasons that never produce a visible transcript line. `turn_complete`
 * fires on EVERY normal turn — a per-turn lifecycle signal, not an
 * event worth narrating (pre-existing suppression in ws-client.ts).
 */
export type SessionEndedSuppressedReason = "turn_complete";

export type SessionEndedRenderableReason = Exclude<
  SessionEndedReason,
  SessionEndedSuppressedReason
>;

export const SESSION_ENDED_SUPPRESSED: ReadonlySet<string> = new Set([
  "turn_complete",
]);

/**
 * Copy per renderable reason. The `Record<SessionEndedRenderableReason,
 * string>` constraint keeps this map exhaustive — a new
 * `WorkflowEndStatus` or `session_ended` reason without a copy row is a
 * `tsc` error here.
 */
export const SESSION_ENDED_COPY: Record<SessionEndedRenderableReason, string> =
  {
    completed: "This run finished.",
    user_aborted: "Conversation stopped at your request.",
    cost_ceiling:
      "This conversation reached the per-workflow cost cap. Start a new conversation to continue.",
    idle_timeout:
      "This conversation was idle for too long and was closed. Start a new conversation to continue.",
    plugin_load_failure:
      "The agent could not start because a plugin failed to load. Try again shortly.",
    runner_runaway:
      "The agent went idle without finishing. Try sending another message to nudge it forward.",
    internal_error:
      "Something went wrong on our side. Try sending the message again.",
    session_revoked:
      "Your session was revoked by an operator. Contact support to restore access.",
    worktree_enter_failed:
      "Couldn't open a workspace to run that step. Try sending your message again.",
    closed: "This conversation was closed.",
  };

/**
 * Fallback for a `reason` outside the known set. The wire type is
 * `z.string()`, so a new emitter can ship a reason this map does not
 * know; the founder still gets an honest, actionable line instead of a
 * raw token. ws-client.ts reports a warning-level Sentry event when
 * this fires so the unmapped reason is triaged rather than silently
 * absorbed.
 */
export const SESSION_ENDED_GENERIC_COPY =
  "This session ended. Send a new message to continue.";

/**
 * Runtime membership test over SESSION_ENDED_COPY — the
 * `hasOwnProperty` idiom from lib/messages/workflow-copy.ts ›
 * isWorkflowBucket. A bare `SESSION_ENDED_COPY[reason]` lookup is NOT
 * safe here: `reason` is a free-form `z.string()`, and a value matching
 * an `Object.prototype` key ("constructor", "toString", "__proto__")
 * resolves a non-nullish inherited member, defeating the generic
 * fallback and dispatching a non-string into `ChatMessage.content`
 * (a React render crash). Consumers: check membership with this guard,
 * then index.
 */
export function hasSessionEndedCopy(
  reason: string,
): reason is SessionEndedRenderableReason {
  return Object.prototype.hasOwnProperty.call(SESSION_ENDED_COPY, reason);
}

/**
 * Resolve the transcript line for a wire `reason`. `mapped` tells the
 * caller whether the reason had its own copy row — the unmapped branch
 * is the one worth a Sentry breadcrumb (an unmapped reason means a new
 * emitter shipped without copy). Membership-gated via
 * hasSessionEndedCopy, never a bare index.
 */
export function sessionEndedCopy(reason: string): {
  copy: string;
  mapped: boolean;
} {
  return hasSessionEndedCopy(reason)
    ? { copy: SESSION_ENDED_COPY[reason], mapped: true }
    : { copy: SESSION_ENDED_GENERIC_COPY, mapped: false };
}
