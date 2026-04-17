import { NextResponse } from "next/server";
import { createChildLogger } from "@/server/logger";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { extractClientIpFromHeaders } from "@/server/rate-limiter";
import { analyticsTrackThrottle } from "./throttle";
import { sanitizeProps, sanitizeForLog } from "./sanitize";

// Same-origin-checked, per-IP rate-limited Plausible forwarder. No session
// required — callers are browsers on allow-listed Origins. Props are
// allowlisted in ./sanitize.ts to keep PII out of third-party telemetry.

const log = createChildLogger("analytics-track");

const MAX_GOAL_LEN = 120;
const MAX_PROP_KEYS = 20;
const MAX_ERR_LOG_LEN = 500;

interface TrackBody {
  goal: string;
  props?: Record<string, unknown>;
}

function isTrackBody(v: unknown): v is TrackBody {
  if (!v || typeof v !== "object") return false;
  const g = (v as { goal?: unknown }).goal;
  if (typeof g !== "string" || g.length === 0 || g.length > MAX_GOAL_LEN) {
    return false;
  }
  const p = (v as { props?: unknown }).props;
  if (p !== undefined) {
    if (typeof p !== "object" || p === null || Array.isArray(p)) return false;
    if (Object.keys(p as Record<string, unknown>).length > MAX_PROP_KEYS) {
      return false;
    }
  }
  return true;
}

export async function POST(req: Request): Promise<Response> {
  const { valid, origin } = validateOrigin(req);
  // Browser-only: reject null Origin (validateOrigin otherwise allows it for
  // non-browser clients, but analytics from non-browsers should emit directly).
  if (!valid || !origin) {
    return rejectCsrf("/api/analytics/track", origin);
  }

  // cf-connecting-ip first; XFF is spoofable when traffic bypasses Cloudflare.
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
    // Graceful skip — analytics must never block UX.
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
        // Forward the trusted IP so Plausible geo-IP sees the real client.
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

    // Learning 2026-04-02: tolerate non-JSON bodies. We never parse further;
    // reading just drains the stream. Inner .catch() makes this safe on its own.
    const ct = res.headers.get("content-type") ?? "";
    if (ct.includes("application/json")) {
      await res.json().catch(() => undefined);
    } else {
      await res.text().catch(() => undefined);
    }
  } catch (err) {
    log.warn(
      {
        err: sanitizeForLog(String(err).slice(0, MAX_ERR_LOG_LEN)),
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
