import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import type { VerifiedUser } from "@/server/request-auth";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { APPROVAL_DECISIONS, decideApproval, type ApprovalDecision } from "@/server/approval/decide";
import { ApprovalServiceError, type ApprovalRpcClient } from "@/server/approval/service";
import { logApprovalMarker, reportApprovalOp } from "@/server/approval/ops";

/**
 * POST /api/approvals/[id]/decide — the Owner's decision from the away-user landing page (#4672).
 *
 * Auth posture (cookie session, so NOT a PUBLIC_PATHS entry): CSRF origin check, then `withUserRateLimit` (401 when
 * unauthenticated), then the decision runs on the USER-CONTEXT client. The actor is `auth.uid()` inside
 * `decide_approval`; there is no user field in the body and the service client is never used here (it has no
 * `auth.uid()`, the RPC would refuse it, and an Owner check made with it would be meaningless).
 *
 * Responses: 200 { outcome, approval } · 400 malformed id or decision · 401 (wrapper) · 403 CSRF · 404 not found OR not
 * an Owner (the RPC raises one error for both, so the response is not an existence oracle) · 429 (wrapper) · 500.
 * `approval` carries ids, status and timestamps only: never the action text.
 *
 * Thin HTTP-only export (cq-nextjs-route-files-http-only-exports). Unlike the WebSocket path this route cannot wake the
 * in-process waiter (a different module instance than the socket server): the waiter's own poll sees the row within
 * one interval, which is the designed cross-host path.
 */

export const dynamic = "force-dynamic";

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function decideHandler(req: Request, user: VerifiedUser): Promise<Response> {
  // Path shape: /api/approvals/<id>/decide (withUserRateLimit does not thread Next's dynamic params).
  const id = new URL(req.url).pathname.split("/").filter(Boolean).at(-2) ?? "";
  if (!UUID_PATTERN.test(id)) return NextResponse.json({ error: "Invalid id" }, { status: 400 });

  const body = (await req.json().catch(() => null)) as { decision?: unknown } | null;
  const decision = body?.decision;
  if (typeof decision !== "string" || !(APPROVAL_DECISIONS as readonly string[]).includes(decision)) {
    return NextResponse.json({ error: "Invalid decision" }, { status: 400 });
  }

  try {
    const supabase = await createClient();
    const result = await decideApproval(supabase as unknown as ApprovalRpcClient, { id, decision: decision as ApprovalDecision });
    const row = result.approval;
    logApprovalMarker("SOLEUR_APPROVAL_DECIDED", {
      approval_id: row.id,
      tool: row.tool_name,
      conversation_id: row.conversation_id,
      decision,
      outcome: result.outcome,
      status: row.status,
      path: "http",
    });
    return NextResponse.json({
      outcome: result.outcome,
      approval: {
        id: row.id,
        status: row.status,
        expires_at: row.expires_at,
        created_at: row.created_at,
        decided_at: row.decided_at,
        decided_by: row.decided_by,
      },
    });
  } catch (err) {
    // 42501: a missing row and a non-owner collapse to the same response.
    if (err instanceof ApprovalServiceError && err.code === "42501") {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    reportApprovalOp("decideFailed", err, { approvalId: id, userId: user.id });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}

const rateLimited = withUserRateLimit(decideHandler, { perMinute: 30, feature: "approvals.decide" });

export async function POST(request: Request): Promise<Response> {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/approvals/[id]/decide", origin);
  return rateLimited(request);
}
