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

export function sanitizeProps(
  props: Record<string, unknown> | undefined,
): { clean: Record<string, unknown>; dropped: string[] } {
  if (!props) return { clean: {}, dropped: [] };
  const clean: Record<string, unknown> = {};
  const dropped: string[] = [];
  for (const [k, v] of Object.entries(props)) {
    if (!ALLOWED_PROP_KEYS.has(k)) {
      if (dropped.length < MAX_DROPPED_KEYS_LOGGED) dropped.push(k);
      continue;
    }
    clean[k] = typeof v === "string" ? v.slice(0, MAX_PROP_STRING_LEN) : v;
  }
  return { clean, dropped };
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
