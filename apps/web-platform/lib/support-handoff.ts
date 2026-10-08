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
 * The canonical connect-a-repo flow (#9556) — the handoff's honest destination
 * for a repo-less user, whose `?msg=` deep link would dead-end on the Command
 * Center's repo gate. Matches `use-reconnect.ts`'s redirect target.
 */
export const SUPPORT_CONNECT_REPO_HREF = "/connect-repo";

/**
 * Canonical surface name — matches the product's own verb for the Command
 * Center (`help-overlay.tsx`, `command-palette.tsx`) so the affordance, the
 * model's prose, and the UI vocabulary converge.
 */
export const SUPPORT_AGENT_SESSION_LABEL = "Ask an agent";

/**
 * Plain-text (non-markdown) pointer for model-relayed deny messages — the
 * same destination as the rendered link so prose and affordance cannot drift.
 */
export const SUPPORT_AGENT_SESSION_HINT = `use "${SUPPORT_AGENT_SESSION_LABEL}" (the Command Center, ${SUPPORT_AGENT_SESSION_HREF})`;

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
  // UTF-16 length is an upper bound on the code-point count — skip the
  // `Array.from` allocation for the common short message.
  if (message.length <= maxChars) return message;
  const points = Array.from(message);
  if (points.length <= maxChars) return message;
  return `${points.slice(0, maxChars).join("")}…`;
}

/**
 * Fully-encoded `?msg=` deep-link markdown — tri-state on `repoConnected`
 * (#9556):
 *
 * - `false` → a link to the connect-repo flow ("Connect a repository to hand
 *   this task to an agent →"). A repo-less user's `?msg=` link would dead-end
 *   on the Command Center's repo gate; `?return_to=` is deliberately NOT added
 *   (the connect flow's own resume handles it, and the task text stays in the
 *   support bubble).
 * - `true` → the `?msg=` link WITHOUT the "(needs a connected repo)" caveat —
 *   the precondition was verified at deny time.
 * - `undefined` → the legacy copy byte-identical (dep-unwired emitters,
 *   wired-but-degraded reads, and pre-resolution denies carry no flag;
 *   additive-safe backward compat).
 *
 * `encodeURIComponent` deliberately leaves `!~*'()` literal — an unbalanced `)`
 * inside the task would close a bare markdown destination early and truncate
 * the carried text, so the destination uses the angle-bracket form (`<url>`)
 * AND the leftover set is percent-encoded for belt.
 */
export function buildSupportHandoffMarkdown(
  task: string,
  repoConnected?: boolean,
): string {
  if (repoConnected === false) {
    return `[Connect a repository to hand this task to an agent →](<${SUPPORT_CONNECT_REPO_HREF}>)`;
  }
  const encoded = encodeURIComponent(task).replace(
    /[!'()*~]/g,
    (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`,
  );
  return repoConnected === true
    ? `[${SUPPORT_AGENT_SESSION_LABEL} to do this →](<${SUPPORT_AGENT_SESSION_HREF}?msg=${encoded}>)`
    : `[${SUPPORT_AGENT_SESSION_LABEL} to do this (needs a connected repo) →](<${SUPPORT_AGENT_SESSION_HREF}?msg=${encoded}>)`;
}
