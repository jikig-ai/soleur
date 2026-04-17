/**
 * Validate an untrusted `contextPath` string before using it in DB equality
 * filters. Returns the path when valid, else null.
 *
 * Uses a blocklist approach (reject dangerous patterns) rather than an
 * allowlist regex, so spaces, unicode filenames, and non-.md extensions
 * all pass — matching isSafePath in context-validation.ts.
 *
 * Shared across `app/api/conversations/route.ts`, `app/api/chat/thread-info/route.ts`,
 * and `server/ws-handler.ts`. Accepts `unknown` so WS callers don't have to
 * pre-narrow message fields; HTTP routes can pass `URLSearchParams.get(...)`
 * directly (returns `string | null`).
 *
 * See review #2381 — the field previously went straight into `.eq()` with no
 * typeof/length/prefix guard.
 */

export const CONTEXT_PATH_MAX_LEN = 512;
export const CONTEXT_PATH_PREFIX = "knowledge-base/";

export function validateContextPath(v: unknown): string | null {
  if (typeof v !== "string") return null;
  if (v.length === 0 || v.length > CONTEXT_PATH_MAX_LEN) return null;
  if (!v.startsWith(CONTEXT_PATH_PREFIX)) return null;
  // Block traversal and null bytes.
  if (v.includes("..") || v.includes("\0")) return null;
  // Must have a file extension (dot in filename that is not the first char).
  const filename = v.split("/").pop() ?? "";
  if (filename.lastIndexOf(".") <= 0) return null;
  return v;
}
