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

// Same tag as the pricing-page waitlist form so shared-doc signups land in the
// existing Buttondown bucket (Art. 30 PA6, single waitlist purpose).
export const WAITLIST_TAG = "pricing-waitlist";

// Hidden input a real browser never fills. Named `url` to mirror the docs-site
// precedent; a password-manager / email autofill will not populate it.
export const HONEYPOT_FIELD = "url";

const MAX_PER_WINDOW = 5;
const WINDOW_MS = 60_000;

// Buttondown's AUTHENTICATED REST API. The previously-used keyless public
// embed-subscribe endpoint was moved behind Cloudflare Turnstile (returns a 400
// challenge page to any server-side caller), so a same-origin proxy can no
// longer use it. The authenticated v1 API is not behind Turnstile.
const BUTTONDOWN_SUBSCRIBE_URL = "https://api.buttondown.com/v1/subscribers";

// Mirror token-validators.ts:VALIDATION_TIMEOUT_MS — a bounded upstream call so
// a Buttondown stall degrades to the route's own JSON 502 instead of hanging
// the worker into a Cloudflare gateway 502.
const WAITLIST_TIMEOUT_MS = 5_000;

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

// A v1 collision (duplicate email) returns 400. The body is JSON with a
// `code` like `email_already_exists` and/or a `detail` message; older/plaintext
// shapes simply contain "already". Match tolerantly across both so a genuine
// duplicate is idempotent success, not a 502.
const ALREADY_SUBSCRIBED_RE = /already|exists|subscrib|duplicate/i;

function isAlreadySubscribed(body: string): boolean {
  try {
    const parsed = JSON.parse(body) as { code?: unknown; detail?: unknown };
    const signal = `${typeof parsed.code === "string" ? parsed.code : ""} ${
      typeof parsed.detail === "string" ? parsed.detail : ""
    }`;
    if (ALREADY_SUBSCRIBED_RE.test(signal)) return true;
  } catch {
    // Non-JSON body — fall through to the raw-text match.
  }
  return ALREADY_SUBSCRIBED_RE.test(body);
}

/**
 * Subscribe an email to the marketing waitlist via Buttondown's authenticated
 * v1 REST API (`POST /v1/subscribers`, `Authorization: Token`) with the
 * pricing-waitlist tag. Resolves on success (201) OR already-subscribed
 * (idempotent from the visitor's perspective). Throws on a missing API key, any
 * unexpected upstream status, an upstream timeout, or a network error so the
 * route maps it to 502 + a Sentry mirror — the raw Buttondown body and the API
 * key are never surfaced to the client.
 *
 * `type` is intentionally omitted from the body so Buttondown's DEFAULT double
 * opt-in is preserved: the visitor receives a confirmation email (the success
 * copy promises "check your inbox to confirm") which is also the GDPR Art.
 * 6(1)(a) consent step. Sending `type: "regular"` would silently skip both.
 */
export async function subscribeToWaitlist(email: string): Promise<{ ok: true }> {
  // Fail-closed key read at call time (NOT module load) — a missing key throws
  // INSIDE the function so the route's try/catch maps it to a graceful JSON 502
  // and the worker never crashes at boot.
  const apiKey = process.env.BUTTONDOWN_API_KEY;
  if (!apiKey) {
    log.warn("BUTTONDOWN_API_KEY missing — waitlist subscribe disabled");
    throw new Error("waitlist subscribe unconfigured");
  }

  const res = await fetch(BUTTONDOWN_SUBSCRIBE_URL, {
    method: "POST",
    headers: {
      Authorization: `Token ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ email_address: email, tags: [WAITLIST_TAG] }),
    signal: AbortSignal.timeout(WAITLIST_TIMEOUT_MS),
  });

  if (res.ok) return { ok: true };

  // Buttondown returns 400 for an already-subscribed address — honest success
  // for the visitor (they are on the list; a re-submit shouldn't error).
  if (res.status === 400) {
    const text = await res.text().catch(() => "");
    if (isAlreadySubscribed(text)) return { ok: true };
  }

  // Unexpected upstream status — throw so the route mirrors to Sentry and
  // returns 502. Status only (never the raw body, never the key) reaches logs.
  log.warn({ status: res.status }, "Buttondown subscribe returned non-ok status");
  throw new Error(`Buttondown subscribe failed: ${res.status}`);
}
