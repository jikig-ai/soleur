import { NextResponse } from "next/server";
import { SlidingWindowCounter } from "@/server/rate-limiter";
import { createChildLogger } from "@/server/logger";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

// Phase 5.2: same-origin-checked, per-IP rate-limited analytics forwarder.
//
// The Plausible Events API has no PII requirement, so this route does NOT
// require a session cookie — that would over-constrain it for future anon
// surfaces (landing page, share pages). Auth = Origin allow-list + per-IP
// rate cap. We strip any `user_id`/`userId` from forwarded props so a stable
// identifier never reaches a third-party tool without a documented salt
// rotation strategy (see plan 5.2 + learning 2026-03-30-plausible-http-402).

const log = createChildLogger("analytics-track");

const RATE_PER_MIN = parseInt(
  process.env.ANALYTICS_TRACK_RATE_PER_MIN ?? "120",
  10,
);

export const analyticsTrackThrottle = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: RATE_PER_MIN,
});

function clientIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0]!.trim();
  const real = req.headers.get("x-real-ip");
  if (real) return real;
  return "unknown";
}

interface TrackBody {
  goal: string;
  props?: Record<string, unknown>;
}

function isTrackBody(v: unknown): v is TrackBody {
  if (!v || typeof v !== "object") return false;
  const g = (v as { goal?: unknown }).goal;
  return typeof g === "string" && g.length > 0 && g.length <= 120;
}

function stripUserIds(props: Record<string, unknown> | undefined): Record<string, unknown> {
  if (!props) return {};
  const clean: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(props)) {
    if (k === "user_id" || k === "userId") continue;
    clean[k] = v;
  }
  return clean;
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

  const ip = clientIp(req);
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

  const payload = {
    name: parsed.goal,
    domain: siteId,
    url: origin ?? "",
    props: stripUserIds(parsed.props),
  };

  try {
    const res = await fetch(eventsUrl, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "user-agent": req.headers.get("user-agent") ?? "soleur-analytics/1.0",
        "x-forwarded-for": ip,
      },
      body: JSON.stringify(payload),
    });

    if (res.status === 402) {
      // Learning 2026-03-30: free plans reject custom props with 402. Treat
      // as graceful skip so the client never sees the error.
      log.warn({ goal: parsed.goal }, "Plausible returned 402 — plan quota exhausted");
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
    log.warn({ err: String(err), goal: parsed.goal }, "Plausible forward failed");
  }

  return new NextResponse(null, { status: 204 });
}

export async function GET(): Promise<Response> {
  return NextResponse.json({ error: "method_not_allowed" }, { status: 405 });
}

/** Test-only helper: clear the in-memory throttle between tests. */
export function __resetAnalyticsTrackThrottleForTest(): void {
  analyticsTrackThrottle.reset();
}
