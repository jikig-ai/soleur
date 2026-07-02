// PR-B (#4379) AC10 — operator-facing copy + Retry-eligibility per
// `action_sends.failure_reason` value.
//
// Mirrors the `DENY_REASON_COPY` pattern in `today-card.tsx`. Source-of-
// truth for the per-reason strings rendered by the Today card state
// matrix (AC11). Adding a new failure_reason: extend the
// `FailureReason` union, add a row to `FAILURE_REASON_COPY`, extend the
// exhaustive test in `failure-reason-copy.test.ts`. The exhaustive type-
// level check on `FAILURE_REASON_COPY: Record<FailureReason, ...>`
// catches a missing row at `tsc` time.

export type FailureReason =
  // PR-A failure reasons (inherited from agent-on-spawn-requested.ts).
  | "github_installation_unauthorized"
  | "github_target_not_found"
  | "github_api_error"
  | "malformed_source_ref"
  | "acknowledgment_persist_failed"
  // PR-B failure reasons.
  | "byok_cap_exceeded"
  | "cost_ceiling_exceeded"
  | "byok_lease_unavailable"
  | "anthropic_timeout"
  | "anthropic_rate_limited"
  | "leader_max_turns_exceeded"
  | "leader_response_truncated"
  | "leader_tool_invalid"
  | "leader_class_disabled"
  | "cancelled_by_operator"
  // feat-l5-runaway-guard PR-A reasons.
  | "run_paused"
  | "cap_check_unavailable";

export interface FailureReasonRow {
  /**
   * Operator-facing copy rendered on the Today card. Per CPO-2 (AC22):
   * no raw `failure_reason` string ever surfaces. Single sentence; first
   * sentence states what happened, second states the recovery path.
   */
  copy: string;
  /**
   * Whether the Today card surfaces a "Retry" button. Per AC10:
   *   - "Retry" is shown for transient failures the operator can re-fire
   *     (anthropic_timeout, anthropic_rate_limited's copy says try later
   *     but the button itself is NOT shown — clicking re-triggers).
   *   - "Retry" is NOT shown for failures the operator must resolve out-
   *     of-band (byok_cap_exceeded → raise cap; cost_ceiling_exceeded →
   *     manual review; cancelled_by_operator → user-initiated;
   *     leader_max_turns_exceeded → task refinement;
   *     leader_tool_invalid → CTO investigates).
   */
  retryEligible: boolean;
}

export const FAILURE_REASON_COPY: Record<FailureReason, FailureReasonRow> = {
  // PR-A reasons.
  github_installation_unauthorized: {
    copy:
      "Couldn't reach GitHub on your behalf. Reconnect the GitHub app in Settings → Integrations.",
    retryEligible: false,
  },
  github_target_not_found: {
    copy:
      "The PR or issue this card pointed to is gone (deleted or never existed).",
    retryEligible: false,
  },
  github_api_error: {
    copy: "GitHub returned an error. Retry usually works.",
    retryEligible: true,
  },
  malformed_source_ref: {
    copy:
      "This card's source reference couldn't be parsed. Discard the card; a fresh one will reappear on the next event.",
    retryEligible: false,
  },
  acknowledgment_persist_failed: {
    copy:
      "The agent finished but couldn't record the result. The artifact on GitHub is the canonical record.",
    retryEligible: false,
  },
  // PR-B reasons.
  byok_cap_exceeded: {
    copy:
      "BYOK cap reached. Raise your cap in Settings → BYOK → Raise Cap, then re-click Spawn.",
    retryEligible: false,
  },
  cost_ceiling_exceeded: {
    copy:
      "Per-spawn cost ceiling ($2.00) reached. The partial artifact is preserved — Undo to remove it.",
    retryEligible: false,
  },
  byok_lease_unavailable: {
    copy:
      "Couldn't acquire your BYOK key. Verify your API key in Settings → BYOK.",
    retryEligible: true,
  },
  anthropic_timeout: {
    copy: "Anthropic API timeout. Retry usually works.",
    retryEligible: true,
  },
  anthropic_rate_limited: {
    // Retry is intentionally NOT eligible — a second click would re-fire
    // the same rate-limited request. The copy tells the operator to wait.
    copy: "Anthropic rate-limited. Try again in a minute.",
    retryEligible: false,
  },
  leader_max_turns_exceeded: {
    copy: "Agent ran out of turns. Refine the task or contact CTO.",
    retryEligible: false,
  },
  leader_response_truncated: {
    copy:
      "Model response truncated (max_tokens). Retry usually works.",
    retryEligible: true,
  },
  leader_tool_invalid: {
    copy: "Agent tried an unauthorized action. CTO has been notified.",
    retryEligible: false,
  },
  leader_class_disabled: {
    copy:
      "Autonomous agent for this card class is not enabled yet. CTO has been notified.",
    retryEligible: false,
  },
  cancelled_by_operator: {
    // Per AC10 + M5 — surface the in-flight turn cost so the operator
    // isn't surprised by non-zero spend on "Stopped". The actual cost is
    // injected by the consumer (see today-card.tsx state-matrix row).
    copy:
      "Stopped. The current turn finished before stopping. Undo any artifacts below.",
    retryEligible: false,
  },
  // feat-l5-runaway-guard PR-A reasons.
  run_paused: {
    // The founder's account is paused (a cost cap tripped earlier). No
    // spend on this attempt. Recovery is out-of-band: clear the pause.
    copy:
      "Your account is paused because a spending cap was reached earlier. Clear the pause from the halt banner to start a fresh run.",
    retryEligible: false,
  },
  cap_check_unavailable: {
    // A transient budget-check failure — NOT a budget breach (P2-H). Honest
    // copy: temporary, try again shortly.
    copy:
      "We couldn't check your spending against your cap due to a temporary issue, so the run was stopped as a precaution. Try again in a moment.",
    retryEligible: false,
  },
};
