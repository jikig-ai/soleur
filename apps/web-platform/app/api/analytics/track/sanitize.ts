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

// Re-export the shared log sanitizer. Body lives in lib/log-sanitize.ts so
// rejectCsrf (in lib/auth/validate-origin.ts) shares the same regex.
export { sanitizeForLog } from "@/lib/log-sanitize";
