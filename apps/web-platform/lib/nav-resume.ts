/**
 * Pure helpers for nav-rail position resume (#4826 / ADR-047 RQ4).
 *
 * Stores chrome only (paths, conversation UUID, expanded dir set, scrollTop)
 * via sessionStorage keys shaped by callers using `resumeKey` + `safeSession`.
 * Never persists document bodies, message content, or tree JSON dumps.
 *
 * Sanitize every read — sessionStorage is untrusted input.
 */

export const MAX_EXPANDED_PATHS = 200;

/** UUID v1–v5-ish (hex groups with hyphens), matching project UUID_RE. */
const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * Relative path under `/dashboard/kb/`: alphanumerics, `._/-` only.
 * No leading `/`, no `..`, no `//`, no backslash.
 */
const SAFE_KB_REL_RE = /^[A-Za-z0-9._/-]+$/;

export type ResumeSegment = "kb" | "chat";

export function resumeKey(
  workspaceId: string,
  segment: ResumeSegment,
  field: string,
): string {
  return `soleur:nav.resume.${workspaceId}.${segment}.${field}`;
}

export function isResumeableConversationId(id: string): boolean {
  if (!id || id === "new") return false;
  return UUID_RE.test(id);
}

/**
 * Validate a relative KB path for use in href fragments.
 * Rejects traversal, protocol smuggling, query/hash, absolute paths.
 */
export function sanitizeKbRelativePath(raw: string | null): string | null {
  if (raw == null) return null;
  if (raw === "") return null;
  if (raw.startsWith("/")) return null;
  if (raw.includes("..") || raw.includes("//") || raw.includes("\\")) {
    return null;
  }
  if (raw.includes("?") || raw.includes("#")) return null;
  if (!SAFE_KB_REL_RE.test(raw)) return null;
  return raw;
}

/**
 * Extract relative KB path from a pathname when it is a doc view.
 * Returns the decoded relative path (still unsanitized — call
 * `sanitizeKbRelativePath` before interpolating into href).
 */
export function kbPathFromPathname(pathname: string): string | null {
  if (!pathname.startsWith("/dashboard/kb/")) return null;
  const raw = pathname.slice("/dashboard/kb/".length);
  if (!raw) return null;
  try {
    const decoded = decodeURIComponent(raw);
    return decoded || null;
  } catch {
    return null;
  }
}

/**
 * Extract a resumeable conversation id from `/dashboard/chat/<id>`.
 * Rejects `new`, bare chat, and non-UUID segments.
 */
export function chatIdFromPathname(pathname: string): string | null {
  if (!pathname.startsWith("/dashboard/chat/")) return null;
  const seg = pathname.slice("/dashboard/chat/".length);
  // Only first segment (ignore query leftovers if any slipped in)
  const id = seg.split(/[/?#]/)[0] ?? "";
  if (!isResumeableConversationId(id)) return null;
  return id;
}

/**
 * Parse expanded dir paths from session JSON. Corrupt → [].
 * Filters non-strings and unsafe path shapes (same guards as KB path).
 */
export function parseExpanded(raw: string | null): string[] {
  if (raw == null || raw === "") return [];
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return [];
  }
  if (!Array.isArray(parsed)) return [];
  const out: string[] = [];
  for (const item of parsed) {
    if (typeof item !== "string") continue;
    // Dir paths use the same relative safety as file paths.
    if (sanitizeKbRelativePath(item) == null) continue;
    out.push(item);
  }
  return out;
}

/** Serialize expanded paths, capping length to avoid unbounded growth. */
export function serializeExpanded(paths: Iterable<string>): string {
  const list: string[] = [];
  for (const p of paths) {
    if (sanitizeKbRelativePath(p) == null) continue;
    list.push(p);
    if (list.length >= MAX_EXPANDED_PATHS) break;
  }
  return JSON.stringify(list);
}

/** Integer ≥ 0 scrollTop; corrupt/non-integer → null. */
export function parseScrollTop(raw: string | null): number | null {
  if (raw == null || raw === "") return null;
  if (!/^\d+$/.test(raw)) return null;
  const n = Number(raw);
  if (!Number.isSafeInteger(n) || n < 0) return null;
  return n;
}

/** Sticky main-nav KB href from a stored relative path (or root). */
export function kbEntryHrefFromStored(stored: string | null): string {
  const safe = sanitizeKbRelativePath(stored);
  if (!safe) return "/dashboard/kb";
  // Encode each segment so spaces etc. survive in href
  const encoded = safe
    .split("/")
    .map((seg) => encodeURIComponent(seg))
    .join("/");
  return `/dashboard/kb/${encoded}`;
}

/** Last chat id for bare `/dashboard/chat` resume, or null → land on /new. */
export function chatEntryIdFromStored(stored: string | null): string | null {
  if (stored == null) return null;
  return isResumeableConversationId(stored) ? stored : null;
}
