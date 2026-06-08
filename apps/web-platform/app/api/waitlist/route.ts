import { NextResponse } from "next/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { warnSilentFallback } from "@/server/observability";
import {
  waitlistThrottle,
  HONEYPOT_FIELD,
  subscribeToWaitlist,
} from "./waitlist";

// Same-origin-checked, per-IP rate-limited proxy that forwards an anonymous
// visitor's email to Buttondown's public embed-subscribe endpoint (marketing
// waitlist). Lives here rather than as a direct client POST because prod CSP
// `connect-src` (lib/csp.ts) excludes buttondown.com and `form-action 'self'`
// would block a native cross-origin form; a same-origin route needs no CSP
// change and lets the honeypot + rate-limit be enforced server-side.
//
// Success contract is `200 {ok:true}` (NOT 204) so the client can parse a body
// to drive its idle→success state machine. All errors share `{error:"<code>"}`.

// RFC-5321 max local+domain; a cheap upper bound before the regex runs.
const MAX_EMAIL_LEN = 254;
// No nested quantifiers over overlapping classes — linear, no catastrophic
// backtracking even on pathological input.
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function POST(req: Request): Promise<Response> {
  const { valid, origin } = validateOrigin(req);
  // Browser-only form: reject a null Origin too (validateOrigin allows it for
  // non-browser clients, but nothing legitimate hits this route without one).
  if (!valid || !origin) {
    return rejectCsrf("/api/waitlist", origin);
  }

  // Fail-closed rate-limit key: trust ONLY Cloudflare's edge-set connecting IP,
  // never the client-controllable x-forwarded-for. For this unauthenticated
  // public email-relay the rate limit is the SOLE abuse control — an XFF
  // fallback would let an attacker rotate the header to mint fresh buckets and
  // use this route to spam Buttondown opt-in confirmations at arbitrary
  // addresses. Absent the CF header (direct-to-origin / non-CF path) → one
  // shared "unknown" bucket, so a flood is capped at the per-window limit total.
  const ip = req.headers.get("cf-connecting-ip")?.trim() || "unknown";
  if (!waitlistThrottle.isAllowed(ip)) {
    return NextResponse.json(
      { error: "rate_limited" },
      { status: 429, headers: { "Retry-After": "60" } },
    );
  }

  let parsed: unknown;
  try {
    parsed = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const body = (parsed ?? {}) as Record<string, unknown>;

  // Honeypot: a real browser never fills the hidden field. Silent 200 so a bot
  // can't learn which field is the trap (a 400 would teach it).
  const trap = body[HONEYPOT_FIELD];
  if (typeof trap === "string" && trap !== "") {
    return NextResponse.json({ ok: true }, { status: 200 });
  }

  const email = typeof body.email === "string" ? body.email.trim() : "";
  if (email.length > MAX_EMAIL_LEN || !EMAIL_RE.test(email)) {
    return NextResponse.json({ error: "invalid_email" }, { status: 400 });
  }

  try {
    await subscribeToWaitlist(email);
    return NextResponse.json({ ok: true }, { status: 200 });
  } catch (err) {
    // Unexpected Buttondown failure (network throw / non-ok status). Mirror to
    // Sentry (warn-level — best-effort marketing forward) and return a generic
    // 502; the raw upstream body never reaches the client.
    warnSilentFallback(err, { feature: "waitlist-subscribe", op: "subscribe" });
    return NextResponse.json(
      { error: "upstream_unavailable" },
      { status: 502 },
    );
  }
}
