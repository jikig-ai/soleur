// PR-B (#4379) AC11 — Today card state matrix.
//
// Pure derivation from an `action_sends` row (the canonical state the
// Realtime subscription delivers) to the operator-facing card state:
// label copy + button affordances (Stop / Undo / Retry).
//
// Render priority (first match wins) per AC11 table:
//
//   1. failure_reason IS NOT NULL AND reversal_handles IS NOT NULL →
//      "Failed — {copy}. Partial artifact preserved." + Undo +
//      Retry (if Retry-eligible per AC10).
//   2. failure_reason IS NOT NULL AND reversal_handles IS NULL →
//      "Failed — {copy}." + Retry (if Retry-eligible).
//   3. undone_at IS NOT NULL → "Undone."
//   4. acknowledged_at IS NOT NULL AND reversal_handles IS NOT NULL →
//      "Done — {artifact_kind} at {artifact_url}." + Undo.
//   5. cancellation_requested_at IS NOT NULL AND acknowledged_at IS NULL
//      AND failure_reason IS NULL →
//      "Stopping — turn N of MAX." (Stop disabled.)
//   6. current_turn IS NOT NULL AND acknowledged_at IS NULL AND
//      failure_reason IS NULL → "Working — turn N of MAX, elapsed."
//      + Stop.
//   7. current_turn IS NULL AND acknowledged_at IS NULL AND
//      failure_reason IS NULL → "Acknowledged — agent starting…"
//
// Pure function; consumed by today-card.tsx and tested directly without
// rendering. Adding a new state row: extend `TodayCardState`, add the
// row to deriveTodayCardState, extend the test.

import {
  FAILURE_REASON_COPY,
  type FailureReason,
} from "@/components/dashboard/failure-reason-copy";

export const LEADER_MAX_TURNS_FOR_DISPLAY = 8;

export type TodayCardStateKind =
  | "failure_with_artifact"
  | "failure_no_artifact"
  | "undone"
  | "done"
  | "stopping"
  | "working"
  | "acknowledged_starting";

export interface TodayCardActionSendInput {
  failure_reason: string | null;
  reversal_handles: unknown[] | null;
  undone_at: string | null;
  acknowledged_at: string | null;
  artifact_url: string | null;
  cancellation_requested_at: string | null;
  current_turn: number | null;
}

export interface TodayCardState {
  kind: TodayCardStateKind;
  /** Operator-facing copy rendered as the card body. */
  copy: string;
  /** Whether to render the Stop button (operator can cancel the loop). */
  showStop: boolean;
  /** Whether the Stop button is disabled (post-click, awaiting next turn boundary). */
  stopDisabled: boolean;
  /** Whether to render the Undo button (artifact present, not yet undone). */
  showUndo: boolean;
  /** Whether to render the Retry button (Retry-eligible failure). */
  showRetry: boolean;
  /**
   * Whether to render the Resume button (feat-l5-runaway-guard PR-A). True
   * only for the paused-state failure reasons — the two that set
   * users.runtime_paused_at (run_paused, byok_cap_exceeded). Resume clears
   * the founder's pause via POST /api/dashboard/runtime/resume, then the
   * founder starts a fresh run (terminal-halt).
   */
  showResume: boolean;
}

// The failure reasons that leave the founder's account paused (the only two
// that write runtime_paused_at). Distinct from cost_ceiling_exceeded (a
// per-spawn ceiling that pauses nothing) and cap_check_unavailable (a
// transient error that pauses nothing).
const PAUSED_STATE_REASONS: ReadonlySet<string> = new Set([
  "run_paused",
  "byok_cap_exceeded",
]);

function isKnownFailureReason(s: string): s is FailureReason {
  return Object.prototype.hasOwnProperty.call(FAILURE_REASON_COPY, s);
}

function failureCopy(reason: string): string {
  if (isKnownFailureReason(reason)) {
    return FAILURE_REASON_COPY[reason].copy;
  }
  // Unknown failure_reason from a future schema. Don't leak the raw
  // string (CPO-2); use a generic operator-facing fallback. The
  // failure-reason-copy.test.ts exhaustive-coverage assertion catches
  // a missing reason at CI time.
  return "Something went wrong. Try again or contact CTO.";
}

function failureRetryEligible(reason: string): boolean {
  if (isKnownFailureReason(reason)) {
    return FAILURE_REASON_COPY[reason].retryEligible;
  }
  return false;
}

export function deriveTodayCardState(
  row: TodayCardActionSendInput,
): TodayCardState {
  const hasArtifact = !!row.reversal_handles && row.reversal_handles.length > 0;

  // Row 1 & 2: failure_reason wins over later states even if a partial
  // acknowledged_at / cancellation_requested_at is present.
  if (row.failure_reason) {
    const copy = failureCopy(row.failure_reason);
    const retry = failureRetryEligible(row.failure_reason);
    const resume = PAUSED_STATE_REASONS.has(row.failure_reason);
    if (hasArtifact) {
      return {
        kind: "failure_with_artifact",
        copy: `Failed — ${copy} Partial artifact preserved.`,
        showStop: false,
        stopDisabled: false,
        showUndo: true,
        showRetry: retry,
        showResume: resume,
      };
    }
    return {
      kind: "failure_no_artifact",
      copy: `Failed — ${copy}`,
      showStop: false,
      stopDisabled: false,
      showUndo: false,
      showRetry: retry,
      showResume: resume,
    };
  }

  // Row 3: undone.
  if (row.undone_at) {
    return {
      kind: "undone",
      copy: "Undone.",
      showStop: false,
      stopDisabled: false,
      showUndo: false,
      showRetry: false,
      showResume: false,
    };
  }

  // Row 4: acknowledged with artifact.
  if (row.acknowledged_at && hasArtifact) {
    return {
      kind: "done",
      copy: row.artifact_url
        ? `Done — artifact at ${row.artifact_url}.`
        : "Done.",
      showStop: false,
      stopDisabled: false,
      showUndo: true,
      showRetry: false,
      showResume: false,
    };
  }

  // Row 5: stopping (Stop clicked, agent finishing current turn).
  if (row.cancellation_requested_at && !row.acknowledged_at) {
    const turn = row.current_turn ?? 0;
    return {
      kind: "stopping",
      copy: `Stopping — turn ${turn} of ${LEADER_MAX_TURNS_FOR_DISPLAY}.`,
      showStop: true,
      stopDisabled: true,
      showUndo: false,
      showRetry: false,
      showResume: false,
    };
  }

  // Row 6: working (in-flight turn).
  if (row.current_turn && !row.acknowledged_at) {
    return {
      kind: "working",
      copy: `Working — turn ${row.current_turn} of ${LEADER_MAX_TURNS_FOR_DISPLAY}.`,
      showStop: true,
      stopDisabled: false,
      showUndo: false,
      showRetry: false,
      showResume: false,
    };
  }

  // Row 7: pre-turn-1 (acknowledged at the route, agent starting).
  return {
    kind: "acknowledged_starting",
    copy: "Acknowledged — agent starting…",
    showStop: false,
    stopDisabled: false,
    showUndo: false,
    showRetry: false,
    showResume: false,
  };
}
