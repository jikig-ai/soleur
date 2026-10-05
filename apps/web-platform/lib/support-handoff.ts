// Shared "Ask an agent" handoff copy + URL construction for the support
// persona (#9539). One module owns the destination, the canonical surface
// name, the link markdown, and the task truncation so the four emit sites
// (Skill deny message, Bash deny message, support directive, and the
// `support_handoff` reducer) can never drift — the `SUPPORT_KB_HREF`
// centralization precedent in `components/support/support-persona.ts`.
//
// Shared `lib/` (not `server/`): the reducer that renders the markdown is
// client-side; the deny messages and directive that name the destination are
// server-side.

/** The write-capable agent surface a support turn hands off to. */
export const SUPPORT_AGENT_SESSION_HREF = "/dashboard/chat/new";

/**
 * Canonical surface name — matches the product's own verb for the Command
 * Center (`help-overlay.tsx`, `command-palette.tsx`) so the affordance, the
 * model's prose, and the UI vocabulary converge.
 */
export const SUPPORT_AGENT_SESSION_LABEL = "Ask an agent";

/** Cap on the user message carried into the `?msg=` deep link. */
const HANDOFF_TASK_MAX_CHARS = 500;

/**
 * Code-point-aware truncation of the handoff task. `String.prototype.slice`
 * cuts UTF-16 code units and can split a surrogate pair at the boundary —
 * `encodeURIComponent` then throws `URIError` inside the reducer, taking the
 * whole rendered reply down with it. `Array.from` iterates code points, so a
 * lone surrogate can never reach the encoder. Appends an ellipsis when the
 * task was cut so the seeded message doesn't read as silently truncated.
 */
export function truncateSupportHandoffTask(
  message: string,
  maxChars: number = HANDOFF_TASK_MAX_CHARS,
): string {
  const points = Array.from(message);
  if (points.length <= maxChars) return message;
  return `${points.slice(0, maxChars).join("")}…`;
}

/**
 * Fully-encoded `?msg=` deep-link markdown. `encodeURIComponent` deliberately
 * leaves `!~*'()` literal — an unbalanced `)` inside the task would close a
 * bare markdown destination early and truncate the carried text, so the
 * destination uses the angle-bracket form (`<url>`) AND the leftover set is
 * percent-encoded for belt.
 */
export function buildSupportHandoffMarkdown(task: string): string {
  const encoded = encodeURIComponent(task).replace(
    /[!'()*~]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
  return `[${SUPPORT_AGENT_SESSION_LABEL} to do this (needs a connected repo) →](<${SUPPORT_AGENT_SESSION_HREF}?msg=${encoded}>)`;
}
