import { INTERACTIVE_PROMPT_KINDS } from "@/lib/types";

/**
 * Single source of truth for the `session_started.capabilities` manifest.
 *
 * The manifest is *advisory*: it lets external agents and the browser
 * client feature-detect what this server build can emit (server→client
 * `interactive_prompt.kind` values via `WS_PROMPT_KINDS`) and what it
 * accepts (client→server message types via `WS_INCOMING_TYPES`). Adding
 * or removing an entry here does NOT change wire dispatch — the WS
 * router still matches on the variant tag regardless of advertisement.
 *
 * **Wire-presence invariant:** every emit site for `session_started`
 * MUST attach `capabilities: WS_CAPABILITIES`. Schema-optional fields
 * have a wire-drop history (`promptKinds` was declared but never
 * emitted; see PR for #3464 + the 2026-05-07 typed-optional-field
 * learning) — `ws-handler-session-started-capabilities.test.ts` pins
 * presence so the next field-addition can't silently bypass the wire.
 */

/**
 * Server→client `interactive_prompt.kind` values this build can emit.
 * Re-exported from the canonical `INTERACTIVE_PROMPT_KINDS` tuple so
 * the manifest cannot drift from the WSMessage union. The re-export
 * preserves the `as const` literal-tuple type so consumers retain
 * autocomplete and exhaustive-switch coverage.
 */
export const WS_PROMPT_KINDS = INTERACTIVE_PROMPT_KINDS;

/**
 * Client→server message types this build accepts that are intended as
 * a stable, agent-facing primitive. **Curated** — required-for-protocol
 * types (`auth`, `start_session`, `chat`, `resume_session`,
 * `close_conversation`) are not advertised because they are
 * prerequisites for any session, not feature-detectable capabilities.
 * Feature-internal variants (`review_gate_response`,
 * `interactive_prompt_response`) are not advertised either.
 *
 * **When adding a new entry:** weigh whether it is a stable agent
 * contract. If yes, add it here AND wire it into the WS router; if no,
 * keep it out of this manifest even if you wire the router. The
 * curated subset is the public surface external agents rely on for
 * feature-detection.
 */
export const WS_INCOMING_TYPES = ["abort_turn"] as const;

export const WS_CAPABILITIES = {
  promptKinds: WS_PROMPT_KINDS,
  incomingTypes: WS_INCOMING_TYPES,
} as const;
