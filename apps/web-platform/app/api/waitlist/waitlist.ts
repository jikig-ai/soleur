// Sibling helper for /api/waitlist per cq-nextjs-route-files-http-only-exports
// (route files may only export HTTP method handlers in Next.js 15 App Router).
// Holds the Buttondown client, the per-IP throttle singleton, and the honeypot
// field name.
import { isIP } from "node:net";
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

// A v1 collision (duplicate email) returns 400 with the machine code
// `email_already_exists` (and a "…already exists" detail); legacy/plaintext
// shapes read "already subscribed". Match the code EXACTLY plus a narrow
// "already subscribed/exists" phrase — deliberately NOT a bare `exists` /
// `subscrib` / `duplicate` token, which would misclassify a genuine validation
// 400 (e.g. "domain does not exist", "invalid subscriber") as success and
// silently drop the signup with no Sentry mirror.
const ALREADY_SUBSCRIBED_RE = /already\s+(subscribed|exists)/i;

// Reserved/private prefixes that can only reach us via direct-to-origin
// spoofing (cf-connecting-ip from Cloudflare is always the public peer IP).
// Buttondown's behavior on an invalid ip_address is undocumented — sending an
// implausible value risks a validation 400 that would break the very signup
// this hardens, so the validator is deliberately reject-biased: omit on doubt.
const PRIVATE_V4 =
  /^(0\.|10\.|100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.|127\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|192\.168\.)/;

// Returns the IP iff it is a plausible public peer address; undefined
// otherwise ("unknown" throttle sentinel, garbage, private/reserved ranges).
// Never logs: a rejected-IP log line could be timestamp-correlated with the
// email in adjacent lines, reconstructing the IP+email pair we never persist.
function plausiblePublicIp(raw: string | undefined): string | undefined {
  if (!raw) return undefined;
  let ip = raw.trim();
  if (ip.toLowerCase().startsWith("::ffff:")) ip = ip.slice(7); // v4-mapped v6
  const version = isIP(ip);
  if (version === 0) return undefined;
  if (version === 4) return PRIVATE_V4.test(ip) ? undefined : ip;
  const v6 = ip.toLowerCase();
  // loopback/unspecified/link-local/unique-local
  if (
    v6 === "::1" ||
    v6 === "::" ||
    v6.startsWith("fe8") ||
    v6.startsWith("fe9") ||
    v6.startsWith("fea") ||
    v6.startsWith("feb") ||
    v6.startsWith("fc") ||
    v6.startsWith("fd")
  ) {
    return undefined;
  }
  return ip;
}

function isAlreadySubscribed(body: string): boolean {
  try {
    const parsed = JSON.parse(body) as { code?: unknown; detail?: unknown };
    // JSON branch is authoritative — return from it rather than falling through
    // to a whole-body scan (which would also match field NAMES, not just text).
    if (parsed.code === "email_already_exists") return true;
    return typeof parsed.detail === "string" && ALREADY_SUBSCRIBED_RE.test(parsed.detail);
  } catch {
    // Legacy / non-JSON plaintext body shape.
    return ALREADY_SUBSCRIBED_RE.test(body);
  }
}

/**
 * Subscribe an email to the marketing waitlist via Buttondown's authenticated
 * v1 REST API (`POST /v1/subscribers`, `Authorization: Token`) with the
 * pricing-waitlist tag. Resolves on success (any 2xx) OR already-subscribed
 * (idempotent from the visitor's perspective). Throws on a missing API key, any
 * unexpected upstream status, an upstream timeout, or a network error so the
 * route maps it to 502 + a Sentry mirror — the raw Buttondown body and the API
 * key are never surfaced to the client.
 *
 * `type` is intentionally omitted from the body so Buttondown's DEFAULT double
 * opt-in is preserved: the visitor receives a confirmation email (the success
 * copy promises "check your inbox to confirm") which is also the GDPR Art.
 * 6(1)(a) consent step. Sending `type: "regular"` would silently skip both.
 *
 * `clientIp` (the route's cf-connecting-ip throttle key) is forwarded as
 * `ip_address` when it is a plausible public IP so Buttondown firewall-scores
 * the VISITOR's residential IP instead of this server's datacenter IP — the
 * server IP scores ~0.6, which blocks every signup the moment Buttondown's
 * attack mode re-escalates the account to aggressive auditing (the
 * WEB-PLATFORM-2F incident class). Implausible values are omitted (fail-safe
 * = pre-hardening behavior) and the IP+email pair is never logged.
 */
export async function subscribeToWaitlist(
  email: string,
  clientIp?: string,
): Promise<{ ok: true }> {
  // Fail-closed key read at call time (NOT module load) — a missing key throws
  // INSIDE the function so the route's try/catch maps it to a graceful JSON 502
  // and the worker never crashes at boot.
  const apiKey = process.env.BUTTONDOWN_API_KEY;
  if (!apiKey) {
    log.warn("BUTTONDOWN_API_KEY missing — waitlist subscribe disabled");
    throw new Error("waitlist subscribe unconfigured");
  }

  const ipAddress = plausiblePublicIp(clientIp);
  const res = await fetch(BUTTONDOWN_SUBSCRIBE_URL, {
    method: "POST",
    headers: {
      Authorization: `Token ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      email_address: email,
      tags: [WAITLIST_TAG],
      ...(ipAddress ? { ip_address: ipAddress } : {}),
    }),
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
