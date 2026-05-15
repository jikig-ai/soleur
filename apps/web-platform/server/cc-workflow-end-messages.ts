// User-facing copy for each `WorkflowEndStatus`. Extracted from
// `cc-dispatcher.ts` per the #3243 status comment recommendation
// (`apps/web-platform/scripts/3243-status-comment.md`). See ADR-031.
//
// Type source: `./soleur-go-runner`'s `WorkflowEnd["status"]` — matches
// the local re-derive at `cc-dispatcher.ts:212`. NOT `@/lib/types`
// `WorkflowEndStatus`, which has 9 wire-protocol values (`sandbox_denial`,
// `runner_crash` included) that the runner's `WorkflowEnd` union does not
// currently emit. Importing from `@/lib/types` would fire the
// exhaustiveness rail below on two missing keys. The lib/types-vs-runner
// enum drift is real and tracked separately — out of scope for this pure
// extraction.

import type { WorkflowEnd } from "./soleur-go-runner";

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
};

// Compile-time exhaustiveness rail. If a new variant lands in
// `WorkflowEnd["status"]` without an entry above, this assertion will
// fail (the type narrows to `never` for the missing key).
const _workflowEndExhaustive: Record<WorkflowEndStatus, string> =
  WORKFLOW_END_USER_MESSAGES;
void _workflowEndExhaustive;
