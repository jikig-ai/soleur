// Sibling helper for /api/waitlist per cq-nextjs-route-files-http-only-exports
// (route files may only export HTTP method handlers in Next.js 15 App Router).
// Holds the Buttondown client, the per-IP throttle singleton, and the honeypot
// field name.
import {
  SlidingWindowCounter,
  startPruneInterval,
} from "@/server/rate-limiter";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("waitlist-subscribe");

// Soleur's own public newsletter handle (already public in
// plugins/soleur/docs/_data/site.json). The Buttondown embed-subscribe endpoint
// needs no API key — this is a username-only, non-secret constant. A hardcoded
// constant rather than an env var: same handle in dev and prod, single consumer
// (YAGNI — add the env read the day a second handle is needed).
export const WAITLIST_USERNAME = "soleur";

// Same tag as the pricing-page waitlist form so shared-doc signups land in the
// existing Buttondown bucket (Art. 30 PA6, single waitlist purpose).
export const WAITLIST_TAG = "pricing-waitlist";

// Hidden input a real browser never fills. Named `url` to mirror the docs-site
// precedent; a password-manager / email autofill will not populate it.
export const HONEYPOT_FIELD = "url";

const MAX_PER_WINDOW = 5;
const WINDOW_MS = 60_000;

const BUTTONDOWN_EMBED_URL = `https://buttondown.com/api/emails/embed-subscribe/${WAITLIST_USERNAME}`;

// Single-instance in-memory counter — inherits the Redis-switch caveat
// documented in server/rate-limiter.ts (see analyticsTrackThrottle).
export const waitlistThrottle = new SlidingWindowCounter({
  windowMs: WINDOW_MS,
  maxRequests: MAX_PER_WINDOW,
});
startPruneInterval(waitlistThrottle);

/** Test-only helper: clear the in-memory throttle between tests. */
export function __resetWaitlistThrottleForTest(): void {
  waitlistThrottle.reset();
}

/**
 * Forward an email to Buttondown's public embed-subscribe endpoint with the
 * pricing-waitlist tag. Resolves on success OR already-subscribed (idempotent
 * from the visitor's perspective). Throws on any unexpected upstream status or
 * network error so the route maps it to 502 + a Sentry mirror — the raw
 * Buttondown body is never surfaced to the client.
 */
export async function subscribeToWaitlist(email: string): Promise<{ ok: true }> {
  const body = new URLSearchParams({
    email,
    tag: WAITLIST_TAG,
    embed: "1",
  });

  const res = await fetch(BUTTONDOWN_EMBED_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body,
  });

  if (res.ok) return { ok: true };

  // Buttondown returns 400 for an already-subscribed address — honest success
  // for the visitor (they are on the list; a re-submit shouldn't error).
  if (res.status === 400) {
    const text = await res.text().catch(() => "");
    if (/already/i.test(text)) return { ok: true };
  }

  // Unexpected upstream status — throw so the route mirrors to Sentry and
  // returns 502. Status only (never the raw body) reaches logs.
  log.warn({ status: res.status }, "Buttondown subscribe returned non-ok status");
  throw new Error(`Buttondown subscribe failed: ${res.status}`);
}
