import { NextResponse } from "next/server";
import { createChildLogger } from "@/server/logger";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { extractClientIpFromHeaders } from "@/server/rate-limiter";
import { analyticsTrackThrottle } from "./throttle";
import { sanitizeProps, sanitizeForLog } from "./sanitize";

// Phase 5.2: same-origin-checked, per-IP rate-limited analytics forwarder.
//
// The Plausible Events API has no PII requirement, so this route does NOT
// require a session cookie — that would over-constrain it for future anon
// surfaces (landing page, share pages). Auth = Origin allow-list + per-IP
// rate cap.
//
// Forwarded props are allowlisted (see ./sanitize.ts) so new PII-like keys
// cannot leak to a third party without an explicit code review.
//
// Non-HTTP-method exports are forbidden in Next.js 15 App Router route files.
// The throttle + prune interval live in ./throttle.ts; sanitization helpers
// live in ./sanitize.ts (see cq-nextjs-route-files-http-only-exports).

const log = createChildLogger("analytics-track");

interface TrackBody {
  goal: string;
  props?: Record<string, unknown>;
}

function isTrackBody(v: unknown): v is TrackBody {
  if (!v || typeof v !== "object") return false;
  const g = (v as { goal?: unknown }).goal;
  return typeof g === "string" && g.length > 0 && g.length <= 120;
}

export async function POST(req: Request): Promise<Response> {
  const { valid, origin } = validateOrigin(req);
  // This route is explicitly browser-only, so also reject missing Origin —
  // unlike the repo-wide validateOrigin default (which allows null Origin
  // for non-browser clients). Non-browser analytics would indicate either
  // misuse or a server-side caller that should emit goals directly.
  if (!valid || !origin) {
    return rejectCsrf("/api/analytics/track", origin);
  }

  // Trust cf-connecting-ip first; XFF is spoofable when traffic bypasses
  // Cloudflare (direct-to-origin). See server/rate-limiter.ts:180 and
  // learning websocket-rate-limiting-xff-trust-20260329.md.
  const ip = extractClientIpFromHeaders(req.headers);
  if (!analyticsTrackThrottle.isAllowed(ip)) {
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
  if (!isTrackBody(parsed)) {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }

  const siteId = process.env.PLAUSIBLE_SITE_ID;
  const eventsUrl = process.env.PLAUSIBLE_EVENTS_URL ?? "https://plausible.io/api/event";
  if (!siteId) {
    // Graceful skip — analytics must never block UX. No forwarding possible.
    return new NextResponse(null, { status: 204 });
  }

  const { clean: safeProps, dropped } = sanitizeProps(parsed.props);
  if (dropped.length > 0) {
    log.debug({ dropped }, "analytics.track dropped non-allowlisted props");
  }

  const payload = {
    name: parsed.goal,
    domain: siteId,
    url: origin ?? "",
    props: safeProps,
  };

  try {
    const res = await fetch(eventsUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "user-agent": req.headers.get("user-agent") ?? "soleur-analytics/1.0",
        // Forward the trusted IP so Plausible's geo-IP lookup gets the real
        // client. Plausible reads X-Forwarded-For specifically.
        "x-forwarded-for": ip,
      },
      body: JSON.stringify(payload),
    });

    if (res.status === 402) {
      // Learning 2026-03-30: free plans reject custom props with 402. Treat
      // as graceful skip so the client never sees the error.
      log.warn(
        { goal: sanitizeForLog(parsed.goal) },
        "Plausible returned 402 — plan quota exhausted",
      );
      return new NextResponse(null, { status: 204 });
    }

    // Learning 2026-04-02: tolerate non-JSON bodies. We never parse the
    // response body further; reading it here just drains the stream.
    try {
      const ct = res.headers.get("content-type") ?? "";
      if (ct.includes("application/json")) {
        await res.json().catch(() => undefined);
      } else {
        await res.text().catch(() => undefined);
      }
    } catch {
      /* ignore */
    }
  } catch (err) {
    log.warn(
      {
        err: sanitizeForLog(String(err)),
        goal: sanitizeForLog(parsed.goal),
      },
      "Plausible forward failed",
    );
  }

  return new NextResponse(null, { status: 204 });
}

export async function GET(): Promise<Response> {
  return NextResponse.json({ error: "method_not_allowed" }, { status: 405 });
}
