// GET /api/account/export/[jobId]/download — stream the bundle.
//
// Phase 6 of feat-dsar-art15-export-endpoint (#3637, plan rev-2).
// FR5 + AC5 + AC16 + AC19 + AC20 + AC24.
//
// Lifecycle:
//   pending/running     -> 409 (not ready)
//   completed (in TTL)  -> 200 + stream + hard-delete + UPDATE delivered
//   completed (TTL gone) -> 410 (TR14 sweep flips status='expired'
//                                next tick; if we're between sweep and
//                                signed_url_expires_at being honoured
//                                we still 410 by checking the clock)
//   expired/delivered/failed/unknown -> 410 Gone with re-request copy
//
// Session+IP-bind (AC5):
//   owner_session_id     — checked against the caller's session id.
//   requester_ip /24 (or /48 for v6) — checked against the issuance IP
//     recorded in dsar_export_audit_pii (event_type='enqueue').
//
// Headers (AC16):
//   Content-Type: application/zip
//   X-Content-Type-Options: nosniff
//   Content-Disposition: attachment; filename="soleur-data-export.zip";
//                        filename*=UTF-8''soleur-data-export.zip
//
// Atomic single-use: UPDATE … SET status='delivered' WHERE status =
// 'completed' RETURNING id. Loser of the race gets the post-update
// 410.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient, serverUrl } from "@/lib/supabase/service";
import { extractClientIpFromHeaders } from "@/server/rate-limiter";
import { getActiveSessionId, ReauthEventInvalid } from "@/server/dsar-reauth";

const STORAGE_BUCKET = "dsar-exports";

/**
 * Canonicalize an IPv4 or IPv6 address into a stable /24 (IPv4) or
 * /48 (IPv6) prefix string for AC5 comparison. Naive `"::1".split(":")`
 * yields `["", "", "1"]` which would equate `::1` with `::2` despite
 * being completely different addresses (fix from security-sentinel P1
 * on PR #3634).
 */
function ipPrefix(ip: string): string {
  // IPv4 — easy: first 3 octets.
  if (!ip.includes(":")) {
    const parts = ip.split(".");
    if (parts.length !== 4) return ip; // malformed → compare verbatim
    return parts.slice(0, 3).join(".");
  }

  // IPv6 — expand "::" once, then take the first 3 hextets (/48).
  const ipNoZone = ip.split("%")[0]; // strip zone identifier if any
  const [head, tail] = ipNoZone.split("::");
  const headParts = head ? head.split(":") : [];
  const tailParts = tail !== undefined ? tail.split(":").filter(Boolean) : [];
  // No "::" -> exactly one part, may already be 8 hextets.
  if (tail === undefined) {
    return headParts.slice(0, 3).join(":");
  }
  // "::" present — expand to 8 hextets total with zero-fill in the middle.
  const missing = 8 - headParts.length - tailParts.length;
  if (missing < 0) return ip; // malformed
  const expanded = [
    ...headParts,
    ...Array<string>(missing).fill("0"),
    ...tailParts,
  ];
  return expanded.slice(0, 3).join(":");
}

function goneResponse(): Response {
  return NextResponse.json(
    {
      error: "export_expired",
      remediation: "Visit /settings/privacy to request a fresh export.",
    },
    { status: 410 },
  );
}

export async function GET(
  request: Request,
  { params }: { params: Promise<{ jobId: string }> },
) {
  const { jobId } = await params;
  const supabase = await createClient();
  // session-id from JWT claim; fail-loud when missing (security-
  // sentinel P1 on PR #3634).
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

  // Service-role: the user-visible RLS only allows SELECT on the jobs
  // table; the atomic single-use UPDATE + Storage operations require
  // service role.
  const service = createServiceClient();
  const { data: job, error: fetchErr } = await service
    .from("dsar_export_jobs")
    .select(
      "id, user_id, status, owner_session_id, signed_url_expires_at",
    )
    .eq("id", jobId)
    .eq("user_id", userId)
    .maybeSingle();
  if (fetchErr) {
    return NextResponse.json({ error: "Lookup failed" }, { status: 500 });
  }
  if (!job) return goneResponse();

  // Pre-binding lifecycle gates.
  if (job.status !== "completed") return goneResponse();
  if (
    !job.signed_url_expires_at ||
    new Date(job.signed_url_expires_at).getTime() < Date.now()
  ) {
    return goneResponse();
  }

  // Session bind.
  if (job.owner_session_id !== sessionId) {
    return NextResponse.json(
      {
        error: "session_mismatch",
        remediation:
          "This download link is bound to the session that requested " +
          "the export. Re-issue from /settings/privacy on the original " +
          "device.",
      },
      { status: 409 },
    );
  }

  // IP bind — look up the enqueue event's requester_ip.
  const { data: auditRows } = await service
    .from("dsar_export_audit_pii")
    .select("requester_ip")
    .eq("job_id", jobId)
    .eq("event_type", "enqueue")
    .order("event_at", { ascending: true })
    .limit(1);
  const issuanceIp = (auditRows?.[0]?.requester_ip as string | null) ?? null;
  const callerIp = extractClientIpFromHeaders(request.headers);
  if (issuanceIp && ipPrefix(callerIp) !== ipPrefix(issuanceIp)) {
    return NextResponse.json(
      {
        error: "ip_mismatch",
        remediation:
          "This download link is bound to the network the export was " +
          "requested from. Re-issue from /settings/privacy.",
      },
      { status: 409 },
    );
  }

  // Atomic single-use: UPDATE … RETURNING. Loser of the race gets 410.
  const { data: claimed, error: claimErr } = await service
    .from("dsar_export_jobs")
    .update({
      status: "delivered",
      delivered_at: new Date().toISOString(),
    })
    .eq("id", jobId)
    .eq("status", "completed")
    .select("id")
    .maybeSingle();
  if (claimErr) {
    return NextResponse.json({ error: "Claim failed" }, { status: 500 });
  }
  if (!claimed) return goneResponse();

  // Stream the Storage object via raw fetch with the service-role key.
  const storagePath = `${userId}/${jobId}.zip`;
  const url = `${serverUrl()}/storage/v1/object/${STORAGE_BUCKET}/${storagePath}`;
  const upstream = await fetch(url, {
    headers: {
      Authorization: `Bearer ${process.env.SUPABASE_SERVICE_ROLE_KEY ?? ""}`,
    },
  });
  if (!upstream.ok || !upstream.body) {
    return NextResponse.json(
      { error: "Bundle missing from Storage" },
      { status: 500 },
    );
  }

  // Fire-and-forget Storage hard-delete + audit row. Doing this AFTER
  // the response stream completes would be cleaner but Next.js's
  // Response model returns immediately; we issue the delete request
  // concurrently and accept that on rare crash-mid-stream the
  // pg_cron TR14 sweep is the backstop.
  void (async () => {
    try {
      await service.storage.from(STORAGE_BUCKET).remove([storagePath]);
    } catch {
      // Logged in service client; TR14 backstop sweeps stale objects.
    }
    await service.rpc("write_dsar_export_audit_pii", {
      p_job_id: jobId,
      p_user_id: userId,
      p_event_type: "download_complete",
      p_requester_ip: callerIp,
      p_user_agent: request.headers.get("user-agent") ?? "",
    });
  })();

  return new Response(upstream.body, {
    status: 200,
    headers: {
      "Content-Type": "application/zip",
      "X-Content-Type-Options": "nosniff",
      // RFC 6266 — fixed sanitised filename, no user-controlled tokens,
      // no CR/LF injection vector.
      "Content-Disposition":
        'attachment; filename="soleur-data-export.zip"; ' +
        "filename*=UTF-8''soleur-data-export.zip",
      // Disable proxy caching of the bundle.
      "Cache-Control": "no-store",
    },
  });
}
