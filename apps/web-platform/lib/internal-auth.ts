// Shared fail-closed Bearer gate for /api/internal/* operator/agent routes
// (trigger-cron, schedule-reminder, cohort). These routes have NO cookie
// session — the shared INNGEST_MANUAL_TRIGGER_SECRET is the trust boundary.
// Server-side only: `node:crypto` keeps this out of any client bundle.
//
// One copy, three callers — this gate used to live in each route file
// verbatim; a fix that had to land in three places is a divergence waiting to
// happen, so the comparison is shared here instead (#8880).

import { timingSafeEqual } from "node:crypto";

// The unset-secret case is deliberately indistinguishable-from-absent to the
// caller (503), so a probe cannot tell "route disabled" from a bad token.
export function readInternalBearerSecret(): string | null {
  const v = process.env.INNGEST_MANUAL_TRIGGER_SECRET;
  return v && v.length > 0 ? v : null;
}

// Accept either a bare token or a `Bearer <token>` header — both feed the same
// length-guarded constant-time compare, so the lenient fallthrough is harmless
// (a non-`Bearer ` header compares verbatim). The length guard runs before
// timingSafeEqual because it throws on unequal-length buffers.
export function bearerMatches(header: string | null, secret: string): boolean {
  if (!header) return false;
  const token = header.startsWith("Bearer ")
    ? header.slice("Bearer ".length)
    : header;
  const a = Buffer.from(token, "utf8");
  const b = Buffer.from(secret, "utf8");
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}
