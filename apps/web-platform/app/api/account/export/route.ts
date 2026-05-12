// POST /api/account/export — enqueue a DSAR export job.
//
// Phase 6 of feat-dsar-art15-export-endpoint (#3637, plan rev-2).
// FR3 + AC3 + AC4 + AC20 + AC21 + AC27.
//
// Flow:
//   1. CSRF origin check.
//   2. supabase.auth.getUser() — return 401 if unauthenticated.
//   3. Abuse rate-limit (1 req / 60s per user) via SlidingWindowCounter.
//   4. Consume reauth event (single-use, <=5min, auth_time<=300s OAuth)
//      via requireFreshReauth(req) per AC21 + AC27.
//   5. enqueueExport — INSERT job + audit-PII row.
//   6. Return 202 with {jobId, acknowledged_at}.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import {
  SlidingWindowCounter,
  extractClientIpFromHeaders,
} from "@/server/rate-limiter";
import { ReauthEventInvalid, requireFreshReauth } from "@/server/dsar-reauth";
import { enqueueExport } from "@/server/dsar-export";

// 1 request per 60 seconds per user — abuse gate (TR7).
const dsarLimiter = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: 1,
});

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/account/export", origin);

  const supabase = await createClient();
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const user = userData.user;

  if (!dsarLimiter.isAllowed(user.id)) {
    return NextResponse.json(
      {
        error: "Too many requests. Please wait before trying again.",
      },
      { status: 429 },
    );
  }

  // Step-up reauth — AC3 + AC21 + AC27. The helper returns the
  // consumed eventId so we can persist the actual UUID downstream
  // (the prior literal "consumed-via-body" placeholder threw on the
  // uuid column for every body-mode call — security-sentinel P1 fix).
  let reauthSession: { userId: string; sessionId: string; eventId: string };
  try {
    reauthSession = await requireFreshReauth(request);
  } catch (err) {
    if (err instanceof ReauthEventInvalid) {
      const reason = err.reason;
      const status = reason === "session_mismatch" ? 403 : 401;
      return NextResponse.json(
        {
          error: "Step-up reauthentication required",
          reason,
        },
        { status },
      );
    }
    throw err;
  }

  try {
    const { jobId, acknowledgedAt } = await enqueueExport({
      userId: reauthSession.userId,
      sessionId: reauthSession.sessionId,
      reauthEventId: reauthSession.eventId,
      requesterIp: extractClientIpFromHeaders(request.headers),
      userAgent: request.headers.get("user-agent") ?? "",
    });
    return NextResponse.json(
      { job_id: jobId, acknowledged_at: acknowledgedAt },
      { status: 202 },
    );
  } catch (err) {
    return NextResponse.json(
      {
        error: "Failed to enqueue export. Please try again.",
        detail: (err as Error).message,
      },
      { status: 500 },
    );
  }
}
