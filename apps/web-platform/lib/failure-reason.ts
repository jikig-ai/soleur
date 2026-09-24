// The `action_sends.failure_reason` taxonomy and the operator paging decision
// (#8719). One declaration serves the leader-loop handler
// (server/inngest/functions/agent-on-spawn-requested.ts), the founder copy
// table (components/dashboard/failure-reason-copy.ts) and the dead-letter
// alert (server/spawn-dead-letter.ts → sentry_alert.spawn_agent_dead_letter).
//
// This module has NO imports on purpose: the Today card (client) and the
// server both import it, so it must never pull a server-only or client-only
// dependency.
//
// Adding a failure_reason: extend the union, add a PAGES_OPERATOR row below
// (`tsc` refuses a missing one), and when the row is `true` add the reason to
// the `in` list of sentry_alert.spawn_agent_dead_letter in
// infra/sentry/issue-alerts.tf. Then add the copy row in failure-reason-copy.ts.

export type FailureReason =
  // PR-A failure reasons.
  | "github_installation_unauthorized"
  | "github_target_not_found"
  | "github_api_error"
  | "malformed_source_ref"
  | "acknowledgment_persist_failed"
  // PR-B failure reasons (the leader loop).
  | "byok_cap_exceeded"
  | "cost_ceiling_exceeded"
  | "byok_lease_unavailable"
  | "anthropic_timeout"
  | "anthropic_rate_limited"
  // A request the API rejects deterministically (400/404/413/422…); retrying
  // fails the same way.
  | "anthropic_request_rejected"
  | "leader_max_turns_exceeded"
  | "leader_response_truncated"
  // The model declined the task (stop_reason=refusal).
  | "leader_refused"
  | "leader_tool_invalid"
  | "leader_class_disabled"
  | "cancelled_by_operator"
  // feat-l5-runaway-guard PR-A: spawn-entry pause gate + distinct
  // transient-cap-check reason (a DB error is not a budget breach).
  | "run_paused"
  | "cap_check_unavailable";

/**
 * Whether a dead-letter with this reason emails the operator. `true` when the
 * failure is a defect on our side, OR when the founder's copy promises the CTO
 * was notified (test/sentry-spawn-dead-letter-alert-op-contract.test.ts refuses
 * a promising row that is `false`). Cost breakers already notify the founder;
 * transient and founder-actionable reasons stay quiet.
 */
export const PAGES_OPERATOR: Record<FailureReason, boolean> = {
  // The GitHub side effect landed but our action_sends write failed.
  acknowledgment_persist_failed: true,
  // We built a request the API rejects deterministically. Copy promises a notification.
  anthropic_request_rejected: true,
  // Kill switch (LEADER_CLASSES_DISABLED) or a missing leader module. Copy promises a notification.
  leader_class_disabled: true,
  // A systematic refusal on one class is a prompt defect. Copy promises a notification.
  leader_refused: true,
  // A non-end_turn/tool_use stop: our token budget or prompt is wrong for the class.
  leader_response_truncated: true,
  // The prompt and the tool surface disagree. Copy promises a notification.
  leader_tool_invalid: true,
  anthropic_rate_limited: false,
  anthropic_timeout: false,
  byok_cap_exceeded: false,
  byok_lease_unavailable: false,
  cancelled_by_operator: false,
  cap_check_unavailable: false,
  cost_ceiling_exceeded: false,
  github_api_error: false,
  github_installation_unauthorized: false,
  github_target_not_found: false,
  leader_max_turns_exceeded: false,
  malformed_source_ref: false,
  run_paused: false,
};
