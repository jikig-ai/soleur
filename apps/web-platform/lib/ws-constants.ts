/**
 * Stage 4 review F19 (#2886): WS-client constants extracted to a leaf module
 * so non-React consumers (vitest test environment, server-side modules) can
 * import them without dragging in `useState` / `useReducer` from ws-client.
 *
 * Keep this module React-free.
 */

/**
 * Time-to-live for a "stuck" THINKING / TOOL_USE bubble before the
 * watchdog fires `applyTimeout`. See FR5 (#2861) for the two-stage
 * retry → error lifecycle.
 */
export const STUCK_TIMEOUT_MS = 45_000;

/**
 * Wire text of the server's `resume_session` refusal (unknown id, or a
 * cross-repo id deliberately indistinguishable from "not found"). SHARED by
 * `server/ws-handler.ts` (sender) and `lib/ws-client.ts` (the credential-rebind
 * fallback keys on it) so the two cannot drift. The wire text is unchanged.
 */
export const CONVERSATION_NOT_FOUND_MESSAGE = "Conversation not found";
