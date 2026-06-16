// User-facing copy for runner `WorkflowEnd` statuses.
// Type source is `./soleur-go-runner` — the runner is canonical post-ADR-031
// amendment (2026-05-15, #3827). The wire-protocol mirror in `@/lib/types`
// (`WORKFLOW_END_STATUSES`) is now kept in lockstep at 8 statuses via the
// bidirectional `_AssertWorkflowEndStatusMatches` rail in `soleur-go-runner.ts`.

import type { WorkflowEnd } from "./soleur-go-runner";
import type { ReprovisionOutcome } from "./ensure-workspace-repo";

type WorkflowEndStatus = WorkflowEnd["status"];

/**
 * User-facing copy for each `WorkflowEndStatus`. Replaces the previous
 * ad-hoc `"Workflow ended (${status}) — retry to continue."` template
 * which leaked an internal status enum to the user.
 *
 * Type-level exhaustiveness: `Record<WorkflowEndStatus, string>` forces
 * every union variant to have an entry — adding a new status to the
 * runner without updating this map is a TS error here. The
 * `_exhaustive: never` rail below is belt-and-suspenders for the rare
 * case where the union is widened via an intersection.
 *
 * Empty string for `"completed"` — that branch is handled via the
 * terminal `session_ended` WS event and never produces a user-visible
 * error message; the empty string is intentional and asserted by the
 * snapshot test.
 */
export const WORKFLOW_END_USER_MESSAGES: Record<WorkflowEndStatus, string> = {
  completed: "",
  cost_ceiling:
    "This conversation reached the per-workflow cost cap. Start a new conversation to continue.",
  runner_runaway:
    "The agent went idle without finishing. Try sending another message to nudge it forward.",
  user_aborted: "Conversation stopped at your request.",
  idle_timeout:
    "This conversation was idle for too long and was closed. Start a new conversation to continue.",
  plugin_load_failure:
    "The agent could not start because a plugin failed to load. Try again shortly.",
  internal_error: "Something went wrong on our side. Try sending the message again.",
  // #4440 follow-up to #4418 — surfaced to agents/API consumers via
  // session_ended (terminal family). Human-readable copy points to
  // operator contact because the deny-list reason is opaque from the
  // founder's perspective without context.
  session_revoked:
    "Your session was revoked by an operator. Contact support to restore access.",
  // #5313 (deferred #5240 FR-half) — honest copy for the worktree-rebind
  // loop. Routing this through the WorkflowEnd error path (not the client
  // activity-watchdog) is what displaces the misleading "Agent stopped
  // responding" banner: the operator sees an accurate, actionable status.
  worktree_enter_failed:
    "Couldn't open a workspace to run that step. Try sending your message again.",
};

// Compile-time exhaustiveness rail. If a new variant lands in
// `WorkflowEnd["status"]` without an entry above, this assertion will
// fail (the type narrows to `never` for the missing key).
const _workflowEndExhaustive: Record<WorkflowEndStatus, string> =
  WORKFLOW_END_USER_MESSAGES;
void _workflowEndExhaustive;

/**
 * Honest "workspace reclaimed" copy (#5340 / #5240 design item #2). Fires ONLY
 * when a `worktree_enter_failed` turn is paired with a GENUINELY-failed
 * re-provision recovery (`ReprovisionOutcome === "failed"`) — i.e. the repo was
 * gone and the automatic re-clone could not restore it (token expired / network
 * / repo deleted). NOT a new `WorkflowEndStatus` (that would trip the
 * exhaustiveness rails) — just a distinct message for the existing status.
 *
 * Voice mirrors the existing honest copy: the `worktree_enter_failed` generic
 * line above and the held-place reclaim banner in `chat-surface.tsx`
 * ("Your place is held — your full conversation is intact. Start a new message
 * to resume with full context."). Honest about the failure, actionable, and
 * never leaks the internal status enum.
 */
export const WORKSPACE_RECLAIMED_MESSAGE =
  "Your workspace was reclaimed and couldn't be restored automatically. Your conversation is intact — start a new message to resume with full context.";

/**
 * Routing decision for a `worktree_enter_failed` turn (the cc `onWorkflowEnded`
 * else-branch — `worktree_enter_failed` is NOT terminal, so it emits a
 * `{ type: "error", message }` frame, never `session_ended`).
 *
 * PLACEMENT (load-bearing — learning 2026-06-14-short-circuit-guard-must-sit-
 * after-the-recovery-it-gates.md): the honest reclaimed message is a
 * POST-recovery-failure concept. It is gated on `reprovisionOutcome === "failed"`
 * — evaluated AFTER the recovery ran — so a successful/benign recovery ("ok") or
 * an unresolved outcome (`undefined`, e.g. the per-dispatch resolve had not
 * settled before the turn failed) falls through to the generic, retryable copy.
 * This is what keeps the message from lying in the recoverable case.
 */
export function resolveWorktreeEnterFailedMessage(
  reprovisionOutcome: ReprovisionOutcome | undefined,
): string {
  return reprovisionOutcome === "failed"
    ? WORKSPACE_RECLAIMED_MESSAGE
    : WORKFLOW_END_USER_MESSAGES.worktree_enter_failed;
}
