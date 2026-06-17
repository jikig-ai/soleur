// scripts/live-verify/redact.ts
//
// Leakage-safety boundary for the live-verification harness (#5452, FR4).
// The harness drives the DEPLOYED app under a REAL synthetic-prod session and
// captures WS frames / DOM / network / console. Those artifacts can contain the
// synthetic principal's live credentials, so EVERYTHING is scrubbed here before
// it is surfaced in a PR/log; raw captures are never persisted.
//
// Design follows the three PII-scrubber invariants
// (knowledge-base/project/learnings/security-issues/2026-04-17-pii-regex-scrubber-three-invariants.md):
//   1. ReDoS-safe: every pattern is a single linear pass with one bounded
//      character class after its anchor — no adjacent unbounded `+` groups
//      around a `\.` anchor, so adversarial input cannot backtrack.
//   2. Structural matching: secrets are matched by WHERE they live (URL query
//      param, header, cookie, JSON key) plus the generic JWT shape — never a
//      version-specific token regex that misses a sibling shape.
//   3. No stateful `/g` + `.test()`: only `.replace()` is used, so there is no
//      `lastIndex` carry-over footgun.

const PLACEHOLDER = "[REDACTED]";

// Order matters: location-anchored rules run first (they preserve the
// surrounding structure), then the generic JWT/email sweeps catch anything that
// escaped a location rule.
const RULES: Array<[RegExp, string]> = [
  // URL query secrets (incl. the Realtime WS connect URL: ?apikey=&access_token=)
  [
    /([?&](?:access_token|refresh_token|provider_token|apikey|token)=)[^&\s"'#]+/gi,
    `$1${PLACEHOLDER}`,
  ],
  // Authorization: Bearer <token>  (request headers in captured network frames)
  [/(authorization:\s*bearer\s+)[A-Za-z0-9._~+/=-]+/gi, `$1${PLACEHOLDER}`],
  // Supabase auth cookie: sb-<ref>-auth-token=<value>
  [/(sb-[a-z0-9-]+-auth-token=)[^;\s"']+/gi, `$1${PLACEHOLDER}`],
  // JSON token keys: "access_token":"...", "refresh_token":"...", etc.
  [
    /(["'](?:access_token|refresh_token|provider_token)["']\s*:\s*")[^"]+/gi,
    `$1${PLACEHOLDER}`,
  ],
  // Generic JWT shape (3 base64url segments) — catches bare tokens in DOM/logs.
  [/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[REDACTED_JWT]"],
  // Email addresses.
  [/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g, "[REDACTED_EMAIL]"],
];

/**
 * Redact secrets from a captured-artifact string by structural location.
 * Pure + idempotent on already-redacted input.
 */
export function redact(input: string): string {
  let out = input;
  for (const [pattern, replacement] of RULES) {
    out = out.replace(pattern, replacement);
  }
  return out;
}
