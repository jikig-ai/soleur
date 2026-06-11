// Display-sink sanitizer for attacker-controlled strings (email subject,
// sender, summary, notification titles) — feat-operator-inbox-delegation.
//
// `sanitizePromptString` (server/inngest/leader-prompts/prompt-assembly.ts)
// strips C0/U+2028/U+2029 for PROMPT sinks but does NOT remove bidi/Cf
// controls — an RLO (U+202E) inside a subject visually spoofs an inbox row
// or a push-notification title. This module is the RENDER/notification-sink
// contract: bidi/Cf strip + control strip + whitespace collapse + length cap.
//
// Per cq-regex-unicode-separators-escape-only: Unicode separator and control
// characters appear ONLY as escape sequences in regex sources, never as
// literals.

// Bidi embedding/override (U+202A-U+202E), bidi isolates (U+2066-U+2069),
// Arabic letter mark (U+061C), zero-width chars (U+200B-U+200D) and
// BOM/zero-width no-break space (U+FEFF): removed entirely.
const BIDI_CF_REGEX = /[\u202A-\u202E\u2066-\u2069\u061C\u200B-\u200D\uFEFF]/g;

// C0 controls (incl. CR/LF — header-injection hygiene), DEL, and NBSP:
// replaced with a space, then collapsed.
// eslint-disable-next-line no-control-regex
const CONTROL_REGEX = /[\x00-\x1f\x7f\u00A0]/g;

/**
 * Sanitize an attacker-controlled string for display sinks (UI rows,
 * notification titles/bodies, email subject lines). Strips bidi/Cf
 * controls, converts C0 + DEL + NBSP to spaces, collapses whitespace,
 * trims, and caps the length (default 200 chars).
 */
export function sanitizeDisplayString(s: string, maxLen = 200): string {
  return s
    .replace(BIDI_CF_REGEX, "")
    .replace(CONTROL_REGEX, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, maxLen);
}
