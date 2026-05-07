// Single source of truth for copywriter-approved chat-surface strings.
// Tests import these consts directly so render and assertion cannot drift
// silently. New variants land here, not inline at the render site.

/**
 * #3269 — copy variants for the WS `context_reset` lifecycle notice.
 * Keyed by `reason` from the wire event. The render in
 * `chat-surface.tsx` reads `CONTEXT_RESET_COPY[msg.reason]`; tests assert
 * against this const verbatim. See plan §4.5.
 */
export const CONTEXT_RESET_COPY = {
  "prefill-guard":
    "Context was lost. Re-state your request if it built on earlier turns.",
  "tool_use_orphan":
    "Context was lost before the last proposed action ran — name the action and re-state it to continue.",
} as const;
