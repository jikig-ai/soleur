// #10543 — the pre-gate decision for a founder re-click on a draft that already has an action_sends
// approval row. Pure: no I/O, no clock, no response objects (the route owns archive, Sentry and
// NextResponse). Ruled by CTO agent, 2026-10-26 (Q5, Q6): extracted so the age boundaries and the
// arm order can be unit-tested without mocks.
//
// Arm order is load-bearing (R2+S4): terminal and no-dispatch arms dispatch nothing so they run
// before any gate; expiry follows (a row older than the window must not replay); the draft-hash
// binding runs last, still before isGranted, so a refused replay never reaches the template gate's
// first-send-authorization side effect.

export interface ExistingApprovalRow {
  id: string;
  per_send_body_sha256: string | null;
  tier_at_send: string;
  clicked_at: string | null;
  acknowledged_at: string | null;
  failure_reason: string | null;
  undone_at: string | null;
  cancellation_requested_at: string | null;
}

// A replay older than this is refused: Inngest dedups an event id for roughly 24h (a plan-level
// assumption: not verified against the self-hosted instance; the consumer's function-level
// `idempotency: event.data.actionSendId` is the verified backstop) and the consumer can leave
// acknowledged_at/failure_reason NULL on a run that executed, so an older replay could post a second
// artifact. 23h leaves a 1h margin (CTO R1).
// Mirrored as `interval '23 hours'` in scripts/followthroughs/dispatch-recovery-sweeper-11211.sh; its suite pins the equality.
export const REPLAY_MAX_AGE_MS = 23 * 60 * 60 * 1000;

// Wire/Sentry vocabulary of a refused replay (the 409 `reason` field and the Sentry `extra.reason`). It differs on
// purpose from `ReplayDecision`'s kind `clock_skew`, which is a decision name, not a value that crosses the wire.
export type StaleReplayReason = "expired" | "future_clicked_at";

// `clicked_at` is a DB-clock `DEFAULT now()` read against the app server's clock. A few hundred ms
// of skew must not destroy an approval that was never dispatched, so a small NEGATIVE age replays;
// beyond this (or when the value does not parse) it is not a plausible click time and the replay fails
// closed WITHOUT archiving (CTO Q5). A future timestamp self-heals when the clock catches up; an
// unparseable one cannot occur in practice (`clicked_at` is NOT NULL DEFAULT now()) and stays refused.
export const CLOCK_SKEW_TOLERANCE_MS = 60_000;

export type ReplayDecision =
  | { kind: "terminal" }
  | { kind: "no_artifact" }
  | { kind: "expired" }
  | { kind: "clock_skew" }
  | { kind: "draft_changed" }
  | { kind: "replay" };

export function decideReplay(args: {
  existing: ExistingApprovalRow;
  /** Whether the message's source_ref parsed to a dispatchable target. */
  parsed: boolean;
  nowMs: number;
  draftPreviewHash: string;
}): ReplayDecision {
  const { existing, parsed, nowMs, draftPreviewHash } = args;

  const terminal =
    existing.acknowledged_at !== null ||
    existing.failure_reason !== null ||
    existing.undone_at !== null ||
    existing.cancellation_requested_at !== null;
  if (terminal) return { kind: "terminal" };

  if (!parsed) return { kind: "no_artifact" };

  // Date.parse of null/garbage is NaN: not finite, so it fails closed to clock_skew (never replays).
  const age = nowMs - Date.parse(existing.clicked_at ?? "");
  if (!Number.isFinite(age) || age < -CLOCK_SKEW_TOLERANCE_MS) {
    return { kind: "clock_skew" };
  }
  if (age > REPLAY_MAX_AGE_MS) return { kind: "expired" };

  // The approval is bound to the body the founder saw: a NULL or different stored hash means the
  // draft changed since (the draft is kept: see the route for the recovery story).
  if (existing.per_send_body_sha256 !== draftPreviewHash) {
    return { kind: "draft_changed" };
  }
  return { kind: "replay" };
}
