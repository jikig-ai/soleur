import logger from "@/server/logger";

const PRODUCTION_ORIGINS = new Set(["https://app.soleur.ai"]);
const DEV_ORIGINS = new Set([
  "https://app.soleur.ai",
  "http://localhost:3000",
  ...(process.env.NEXT_PUBLIC_APP_URL ? [process.env.NEXT_PUBLIC_APP_URL] : []),
]);

export function getAllowedOrigins(): Set<string> {
  return process.env.NODE_ENV === "development" ? DEV_ORIGINS : PRODUCTION_ORIGINS;
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
  const sanitized = (origin ?? "none").slice(0, 100).replace(/[\x00-\x1f]/g, "");
  logger.warn({ route, rejectedOrigin: sanitized }, "CSRF: rejected origin");
  return Response.json({ error: "Forbidden" }, { status: 403 });
}
