import { getAllowedOrigins } from "./allowed-origins";

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

  return { valid: false, origin: null };
}

export function rejectCsrf(route: string, origin: string | null): Response {
  const sanitized = (origin ?? "none").slice(0, 100).replace(/[\x00-\x1f]/g, "");
  console.warn(`[${route}] CSRF: rejected origin ${sanitized}`);
  return Response.json({ error: "Forbidden" }, { status: 403 });
}
