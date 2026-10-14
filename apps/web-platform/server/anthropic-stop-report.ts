// How an Anthropic turn ended, read ONE way for every caller (Haiku 5.5, 2026-10-08).
//
// Haiku 5.5 runs adaptive thinking by default and thinking tokens count against
// max_tokens, so a small-budget call can end with no text block, be cut at max_tokens,
// or be refused (`stop_reason: "refusal"` with a `stop_details.category`). The domain
// router, the email summarizer and the leader loop each need to (a) decide whether the
// turn produced a usable answer and (b) report the stop without leaking anything but a
// closed vocabulary. They used to carry three copies with three gating rules; this is the
// one copy. PURE: no imports, so it is safe on the interactive request path (the router
// must stay leaf-light).
//
// Every value that reaches a log sink comes from this allowlist. The strings originate in
// an API response (over TLS), not from a user, but a closed vocabulary costs nothing and
// removes the question of what a proxy or a future API revision could put there.

/** `stop_reason` values the API documents; anything else is reported as "unknown". */
export const KNOWN_STOP_REASONS = [
  "end_turn",
  "max_tokens",
  "stop_sequence",
  "tool_use",
  "pause_turn",
  "refusal",
  "model_context_window_exceeded",
] as const;

/** `stop_details.category` values for a refusal; anything else is "unrecognized". */
export const KNOWN_REFUSAL_CATEGORIES = ["cyber", "bio", "frontier_llm", "general_harms"] as const;

/** Stops that mean the answer is unusable even when some text came back. */
const UNUSABLE_STOPS: ReadonlySet<string> = new Set([
  "max_tokens",
  "refusal",
  "model_context_window_exceeded",
]);

export function safeStopReason(value: unknown): string {
  return typeof value === "string" && (KNOWN_STOP_REASONS as readonly string[]).includes(value)
    ? value
    : "unknown";
}

/**
 * The refusal category, or null. Reported ONLY for a refusal stop (stop_details is a
 * refusal detail; on any other stop a category is not a statement about this turn), and
 * ONLY the category: the rest of stop_details (e.g. a model-written `explanation`) never
 * rides along.
 */
export function refusalCategory(stopReason: unknown, stopDetails: unknown): string | null {
  if (stopReason !== "refusal") return null;
  if (typeof stopDetails !== "object" || stopDetails === null) return null;
  const category = (stopDetails as { category?: unknown }).category;
  if (typeof category !== "string") return null;
  return (KNOWN_REFUSAL_CATEGORIES as readonly string[]).includes(category)
    ? category
    : "unrecognized";
}

/**
 * The `extra` for a "no usable answer" report, or null when the turn is fine. A turn is
 * unusable when its text is empty/whitespace OR it ended at max_tokens, a refusal or a
 * context-window stop (non-empty text there is a fragment or a refusal message). The
 * caller owns `feature`/`op`/`message`; the key set is exactly stop_reason, [category],
 * model — never the user's message, subject, sender, body, or an error object.
 */
export function noTextBlockExtra(args: {
  text: string;
  stopReason: unknown;
  stopDetails: unknown;
  model: string;
}): { stop_reason: string; category?: string; model: string } | null {
  const stop = safeStopReason(args.stopReason);
  if (args.text.trim() !== "" && !UNUSABLE_STOPS.has(stop)) return null;
  const category = refusalCategory(args.stopReason, args.stopDetails);
  return { stop_reason: stop, ...(category ? { category } : {}), model: args.model };
}
