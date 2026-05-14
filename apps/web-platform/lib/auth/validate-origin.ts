import { sanitizeForLog } from "@/lib/log-sanitize";

// This module is reached from edge middleware (`middleware.ts`) — do NOT
// import `@/server/logger`, which transitively pulls `node:crypto` via
// `server/observability.ts` (per ADR-029 §I10) and breaks the edge bundle.
// `console.warn` is supported in edge runtime; the `rejectedOrigin` field
// carries no user PII so the pino `userIdHash` rename hook is not needed.

const PRODUCTION_ORIGINS = new Set(["https://app.soleur.ai"]);

// PR-A (#2939): NEXT_PUBLIC_DEV_EXTRA_ORIGINS is a Playwright-only comma list
// of dev-mode origins (e.g. "http://localhost:3099,http://localhost:3100").
// Production behavior is unaffected — only PRODUCTION_ORIGINS is consulted
// when NODE_ENV !== "development".
//
// Entries are lowercased on insert so `HTTP://Localhost:3099` and the
// request-side lowercased lookup (line 38) agree. The `i` flag on the
// scheme regex is hygiene — without it `HTTP://x` survives the filter but
// would never match a lowercased Origin header, producing a silent-no-op
// allowlist entry.
function buildDevOrigins(): Set<string> {
  const extra = (process.env.NEXT_PUBLIC_DEV_EXTRA_ORIGINS ?? "")
    .split(",")
    .map((s) => s.trim().toLowerCase())
    .filter((s) => s.length > 0 && /^https?:\/\//i.test(s));
  return new Set([
    "https://app.soleur.ai",
    "http://localhost:3000",
    ...(process.env.NEXT_PUBLIC_APP_URL ? [process.env.NEXT_PUBLIC_APP_URL.toLowerCase()] : []),
    ...extra,
  ]);
}

export function getAllowedOrigins(): Set<string> {
  return process.env.NODE_ENV === "development" ? buildDevOrigins() : PRODUCTION_ORIGINS;
}

export function validateOrigin(request: Request): {
  valid: boolean;
  origin: string | null;
} {
  const origin = request.headers.get("origin");
  const referer = request.headers.get("referer");
  const allowed = getAllowedOrigins();

  if (origin) {
    return { valid: allowed.has(origin.toLowerCase()), origin };
  }

  if (referer) {
    try {
      const refererOrigin = new URL(referer).origin;
      return { valid: allowed.has(refererOrigin.toLowerCase()), origin: refererOrigin };
    } catch {
      return { valid: false, origin: referer };
    }
  }

  // No Origin or Referer header — this is a non-browser client (curl,
  // server-to-server, mobile app).  CSRF is a browser-only attack vector,
  // so allow the request through.  Authentication still gates access.
  return { valid: true, origin: null };
}

export function rejectCsrf(route: string, origin: string | null): Response {
  const sanitized = sanitizeForLog(origin ?? "none", 100);
  // eslint-disable-next-line no-console -- edge-runtime boundary; see comment above
  console.warn(
    "[validate-origin] CSRF: rejected origin",
    JSON.stringify({ route, rejectedOrigin: sanitized }),
  );
  return Response.json({ error: "Forbidden" }, { status: 403 });
}
