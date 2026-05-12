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
import { SlidingWindowCounter } from "@/server/rate-limiter";
import { ReauthEventInvalid, requireFreshReauth } from "@/server/dsar-reauth";
import { enqueueExport } from "@/server/dsar-export";

// 1 request per 60 seconds per user — abuse gate (TR7).
const dsarLimiter = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: 1,
});

function getRequesterIp(req: Request): string {
  const xff = req.headers.get("x-forwarded-for");
  if (xff) return xff.split(",")[0]!.trim();
  return req.headers.get("x-real-ip") ?? "0.0.0.0";
}

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

  // Step-up reauth — AC3 + AC21 + AC27.
  try {
    await requireFreshReauth(request);
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

  // Session id binding (FR3 + FR5 + AC5). The session id is available
  // on the access token; in environments where Supabase does not expose
  // it directly we fall back to the user id so the binding is at least
  // scoped to the user.
  const { data: sessionData } = await supabase.auth.getSession();
  const sessionId =
    (sessionData?.session as unknown as { session_id?: string } | null)
      ?.session_id ?? user.id;

  try {
    const { jobId, acknowledgedAt } = await enqueueExport({
      userId: user.id,
      sessionId,
      reauthEventId:
        request.headers.get("x-reauth-event") ?? "consumed-via-body",
      requesterIp: getRequesterIp(request),
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
