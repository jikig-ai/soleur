// GET  /api/account/export/[jobId] — status (RLS-scoped read).
// POST /api/account/export/[jobId] — reissue (per S9 inline; resets
// session+IP-bind and extends TTL when the original download URL was
// abandoned due to a network/device change).
//
// Phase 6 of feat-dsar-art15-export-endpoint (#3637, plan rev-2).
// FR5 + FR6 + AC4 + AC5 + AC20.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { createServiceClient } from "@/lib/supabase/service";
import { extractClientIpFromHeaders } from "@/server/rate-limiter";
import { getActiveSessionId, ReauthEventInvalid } from "@/server/dsar-reauth";

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ jobId: string }> },
) {
  const { jobId } = await params;
  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData?.user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // RLS policy `dsar_export_jobs_owner_select` restricts SELECT to
  // auth.uid() = user_id, so this read is owner-only by construction.
  // Any non-owner who learns the jobId still sees 404.
  const { data, error } = await supabase
    .from("dsar_export_jobs")
    .select(
      "id, status, requested_at, acknowledged_at, started_at, completed_at, " +
        "delivered_at, signed_url_expires_at, failure_reason, bundle_size_bytes",
    )
    .eq("id", jobId)
    .maybeSingle();
  if (error) {
    return NextResponse.json(
      { error: "Failed to fetch job status" },
      { status: 500 },
    );
  }
  if (!data) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  return NextResponse.json(data);
}

export async function POST(
  request: Request,
  { params }: { params: Promise<{ jobId: string }> },
) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/account/export/[jobId]", origin);

  const { jobId } = await params;
  const supabase = await createClient();

  // Session id derived from the JWT `session_id` claim — throws if
  // either user or session_id is missing (fail-loud rather than degrade
  // to user-bind, per security-sentinel P1 on PR #3634).
  let userId: string;
  let sessionId: string;
  try {
    const resolved = await getActiveSessionId(supabase);
    userId = resolved.userId;
    sessionId = resolved.sessionId;
  } catch (err) {
    if (err instanceof ReauthEventInvalid) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }
    throw err;
  }

  // Use service-role to fetch the row and update session+IP bind; the
  // RLS policy only allows SELECT, so reissue must be service-role.
  const service = createServiceClient();
  const { data: job, error: fetchErr } = await service
    .from("dsar_export_jobs")
    .select("id, user_id, status, signed_url_expires_at")
    .eq("id", jobId)
    .eq("user_id", userId)
    .maybeSingle();
  if (fetchErr) {
    return NextResponse.json({ error: "Lookup failed" }, { status: 500 });
  }
  if (!job) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  if (job.status !== "completed") {
    return NextResponse.json(
      {
        error: "Cannot reissue a job that is not in `completed` status.",
        status: job.status,
      },
      { status: 409 },
    );
  }

  // Reset session_id binding to the current session + extend TTL 7d.
  const newExpiry = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);
  const { error: updateErr } = await service
    .from("dsar_export_jobs")
    .update({
      owner_session_id: sessionId,
      signed_url_expires_at: newExpiry.toISOString(),
    })
    .eq("id", jobId)
    .eq("user_id", userId);
  if (updateErr) {
    return NextResponse.json({ error: "Reissue failed" }, { status: 500 });
  }

  // Audit row for the reissue event.
  await service.rpc("write_dsar_export_audit_pii", {
    p_job_id: jobId,
    p_user_id: userId,
    p_event_type: "reissue",
    p_requester_ip: extractClientIpFromHeaders(request.headers),
    p_user_agent: request.headers.get("user-agent") ?? "",
  });

  return NextResponse.json({
    job_id: jobId,
    signed_url_expires_at: newExpiry.toISOString(),
  });
}
