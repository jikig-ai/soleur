// Allowlist-based prop sanitization + log sanitization for
// /api/analytics/track. Lives in a sibling module (not route.ts) because
// Next.js 15 App Router route files may export only HTTP method handlers
// (see cq-nextjs-route-files-http-only-exports / PR #2401).

// Every key here must be audited for PII risk. Adding a key requires a
// security review — keep this module as the single chokepoint.
const ALLOWED_PROP_KEYS = new Set<string>(["path"]);

const MAX_PROP_STRING_LEN = 200;

export function sanitizeProps(
  props: Record<string, unknown> | undefined,
): { clean: Record<string, unknown>; dropped: string[] } {
  if (!props) return { clean: {}, dropped: [] };
  const clean: Record<string, unknown> = {};
  const dropped: string[] = [];
  for (const [k, v] of Object.entries(props)) {
    if (!ALLOWED_PROP_KEYS.has(k)) {
      dropped.push(k);
      continue;
    }
    clean[k] = typeof v === "string" ? v.slice(0, MAX_PROP_STRING_LEN) : v;
  }
  return { clean, dropped };
}

// Strip C0 control characters (\x00–\x1f, includes \n, \r, \t) from strings
// routed to structured logs. Mirrors the pattern in rejectCsrf
// (lib/auth/validate-origin.ts) and prevents log-line injection via user input.
export function sanitizeForLog(s: string): string {
  return s.replace(/[\x00-\x1f]/g, "");
}
