// Allowlist-based prop sanitization + log sanitization for
// /api/analytics/track. Sibling module per cq-nextjs-route-files-http-only-exports.

// Adding a key requires security review — keep this module as the single chokepoint.
const ALLOWED_PROP_KEYS = new Set<string>(["path"]);

const MAX_PROP_STRING_LEN = 200;
// Cap the dropped-key log to prevent log flooding when an attacker crafts
// props with thousands of random keys (each call still iterates the full map
// because isTrackBody caps key count upstream, but the log line itself must
// stay bounded regardless).
const MAX_DROPPED_KEYS_LOGGED = 20;

// PII scrub patterns for the `path` prop (#2462). Order matters: email first
// (catches `@` which is unique to emails), then UUID v4, then 6+ digit runs.
// The email character class excludes whitespace AND forward slashes:
// `\S+@\S+\.\S+` would match the ENTIRE multi-segment path as one giant
// email (because `\S` matches `/`), collapsing `/users/a@b.com/settings` to
// `[email]`. Excluding `/` bounds matches to the containing path segment.
const EMAIL_RE = /[^\s/]+@[^\s/]+\.[^\s/]+/g;
const UUID_V4_RE = /[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/gi;
const LONG_DIGIT_RUN_RE = /\d{6,}/g;

function scrubPath(value: string): { clean: string; scrubbed: string[] } {
  const fired: string[] = [];
  let out = value;
  if (EMAIL_RE.test(out)) {
    fired.push("email");
    out = out.replace(EMAIL_RE, "[email]");
  }
  if (UUID_V4_RE.test(out)) {
    fired.push("uuid");
    out = out.replace(UUID_V4_RE, "[uuid]");
  }
  if (LONG_DIGIT_RUN_RE.test(out)) {
    fired.push("id");
    out = out.replace(LONG_DIGIT_RUN_RE, "[id]");
  }
  return { clean: out, scrubbed: fired };
}

export function sanitizeProps(
  props: Record<string, unknown> | undefined,
): {
  clean: Record<string, unknown>;
  dropped: string[];
  scrubbed: string[];
} {
  if (!props) return { clean: {}, dropped: [], scrubbed: [] };
  const clean: Record<string, unknown> = {};
  const dropped: string[] = [];
  const scrubbedSet = new Set<string>();
  for (const [k, v] of Object.entries(props)) {
    if (!ALLOWED_PROP_KEYS.has(k)) {
      if (dropped.length < MAX_DROPPED_KEYS_LOGGED) dropped.push(k);
      continue;
    }
    if (k === "path" && typeof v === "string") {
      // Scrub FIRST (FR4) — emails can extend past the 200-char cap, and
      // slicing first would split a pattern mid-match, leaking a partial
      // email. Scrub-then-slice guarantees full sentinel replacement.
      const { clean: scrubbedVal, scrubbed } = scrubPath(v);
      for (const name of scrubbed) scrubbedSet.add(name);
      clean[k] = scrubbedVal.slice(0, MAX_PROP_STRING_LEN);
    } else {
      clean[k] = typeof v === "string" ? v.slice(0, MAX_PROP_STRING_LEN) : v;
    }
  }
  // Set iterator preserves insertion order, which matches scrub-application
  // order (email → uuid → id). Downstream operator dashboards can count
  // pattern frequency deterministically.
  return { clean, dropped, scrubbed: [...scrubbedSet] };
}

// Strip C0 control characters, DEL, and Unicode line/paragraph separators
// before strings reach structured logs. U+2028 and U+2029 are especially
// important: JSON loggers pass them through, but many log viewers and
// JavaScript consumers treat them as line terminators — re-enabling log
// injection through a "sanitized" goal. Pattern source: rejectCsrf in
// lib/auth/validate-origin.ts.
export function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f\x7f\u2028\u2029]/g, "");
}
