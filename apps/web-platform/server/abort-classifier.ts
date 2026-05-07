/**
 * Pure helper that classifies an `AbortController.signal.reason` value
 * for the for-await abort branch in `agent-runner.ts:startAgentSession`.
 *
 * Extracted so the branch's `user_requested_stop` vs disconnected vs
 * superseded routing can be unit-tested in isolation
 * (feat-abort-conversation-web PR1, plan §1.9).
 *
 * Design choice: the registry's `abortSession` embeds the reason in the
 * Error message rather than as a structured `cause` field because the
 * SDK / fetch layer surfaces `signal.reason` in places where we cannot
 * assume `cause` propagation (verified at plan time against
 * `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:816`). The
 * substring check below mirrors what the existing
 * `agent-runner.ts:1547-1565` outer-catch already does for
 * `superseded`, so this helper does not introduce new error-shape
 * coupling.
 */

export interface AbortReasonClassification {
  /** True iff the abort came from a user-initiated Stop (button or Esc).
   *  The for-await branch reads this to decide whether to keep the
   *  conversation status as 'active' (continuable) or flip to 'failed'. */
  isUserRequested: boolean;
}

/** Classify an `AbortController.signal.reason` value. Tolerant of
 *  non-Error values: anything that isn't a real Error with a matching
 *  substring is treated as a non-user abort (preserves today's
 *  disconnect behavior for crashed-client / shutdown paths). */
export function classifyAbortReason(reason: unknown): AbortReasonClassification {
  if (!(reason instanceof Error)) {
    return { isUserRequested: false };
  }
  return { isUserRequested: reason.message.includes("user_requested_stop") };
}
