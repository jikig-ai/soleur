// Founder-facing copy for the WS `workflow_ended` lifecycle frame.
//
// Sibling of session-ended-copy.ts. The wire `status` is a closed
// `z.enum(WORKFLOW_END_STATUSES)` (ws-zod-schemas.ts ›
// workflowEndedSchema), so unknown statuses are dropped at
// `parseWSMessage` before any render — the `ws-zod-parse-failure`
// Sentry event is the unmapped-status report for the wire path. The
// membership-gated resolvers + generic fallbacks below cover the only
// remaining unmapped surface: direct construction (tests, future
// non-WS channels).
//
// Two consumers, two registers:
//   - Transcript card (chat-surface.tsx › case "workflow_ended") —
//     sentence register, delegated to SESSION_ENDED_COPY so the card
//     stays verbatim with the parity-pinned session_ended copy.
//   - Outcome badge (workflow-lifecycle-bar.tsx › ended branch) —
//     terse label register; the ~90-char sentences overflow the
//     `text-[10px]` pill.
// Rendering the raw token leaked internal enum names to founders
// ("internal_error") on the session_ended path until d715256ba0 —
// this module is the same guard for the dormant workflow_ended renders.

import type { WorkflowEndStatus } from "./types";
import { sessionEndedCopy } from "./session-ended-copy";

/**
 * Terse outcome labels for the lifecycle badge pill. The
 * `Record<WorkflowEndStatus, string>` constraint keeps this map
 * exhaustive — a new status without a badge row is a `tsc` error here.
 */
export const WORKFLOW_ENDED_BADGE_COPY: Record<WorkflowEndStatus, string> = {
  completed: "Completed",
  user_aborted: "Stopped",
  cost_ceiling: "Cost cap reached",
  idle_timeout: "Timed out",
  plugin_load_failure: "Could not start",
  runner_runaway: "Stalled",
  internal_error: "Error",
  session_revoked: "Revoked",
  worktree_enter_failed: "Workspace error",
};

/**
 * Badge fallback for a `status` outside the known set — reachable only
 * via direct construction (the Zod enum drops unknown wire statuses at
 * parse).
 */
export const WORKFLOW_ENDED_BADGE_GENERIC = "Ended";

/**
 * Transcript-card fallback for an unmapped `status`. Says "workflow",
 * not "session" — the card's own sentence register.
 */
export const WORKFLOW_ENDED_GENERIC_COPY =
  "This workflow ended. Start a new conversation to continue.";

/**
 * Runtime membership test over WORKFLOW_ENDED_BADGE_COPY — the
 * `hasOwnProperty` idiom from lib/messages/workflow-copy.ts ›
 * isWorkflowBucket. A bare `WORKFLOW_ENDED_BADGE_COPY[status]` lookup
 * is NOT safe: a value matching an `Object.prototype` key
 * ("constructor", "toString", "__proto__") resolves a non-nullish
 * inherited member, defeating the generic fallback and dispatching a
 * non-string into the render. Consumers: check membership with this
 * guard, then index.
 */
export function hasWorkflowEndedBadge(
  status: string,
): status is WorkflowEndStatus {
  return Object.prototype.hasOwnProperty.call(
    WORKFLOW_ENDED_BADGE_COPY,
    status,
  );
}

/**
 * Resolve the badge label for a wire `status`. `mapped` mirrors the
 * sessionEndedCopy resolver shape — the unmapped branch is the one a
 * caller can flag (new status shipped without copy).
 */
export function workflowEndedBadge(status: string): {
  copy: string;
  mapped: boolean;
} {
  return hasWorkflowEndedBadge(status)
    ? { copy: WORKFLOW_ENDED_BADGE_COPY[status], mapped: true }
    : { copy: WORKFLOW_ENDED_BADGE_GENERIC, mapped: false };
}

/**
 * Resolve the transcript-card sentence for a wire `status`. Delegates
 * to `sessionEndedCopy` for mapped statuses — SESSION_ENDED_COPY is
 * parity-pinned to server `WORKFLOW_END_USER_MESSAGES`, so reusing it
 * adds zero new sentence copy and inherits the drift guard. Unmapped
 * statuses get the workflow-generic fallback.
 */
export function workflowEndedCopy(status: string): {
  copy: string;
  mapped: boolean;
} {
  const resolved = sessionEndedCopy(status);
  return resolved.mapped
    ? resolved
    : { copy: WORKFLOW_ENDED_GENERIC_COPY, mapped: false };
}
