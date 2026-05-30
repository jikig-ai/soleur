import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { revokeWorkspaceInvitation } from "@/server/workspace-invitations";

// POST /api/workspace/cancel-invite
// Body: { workspaceId, invitationId }
//
// Owner-side cancellation of a pending invite (feat-cancel-pending-invite,
// #4634). Mirrors remove-member's auth chain. Owner-only; the invitation must
// belong to the caller's workspace. The revoke RPC re-checks ownership as
// defense-in-depth against a cross-workspace service-role call.
export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/cancel-invite", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const service = createServiceClient();
  const pageData = await resolveTeamMembershipPageData(supabase, service);
  if (!pageData.ok) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  const identity: Identity = { userId: user.id, role: "prd", orgId: pageData.data.organizationId };
  if (!(await isTeamWorkspaceInviteEnabled(pageData.data.organizationId, identity))) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: { workspaceId?: unknown; invitationId?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const workspaceId = body.workspaceId;
  const invitationId = body.invitationId;
  if (
    typeof workspaceId !== "string" ||
    typeof invitationId !== "string" ||
    workspaceId.length === 0 ||
    invitationId.length === 0
  ) {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }
  if (workspaceId !== pageData.data.workspaceId) {
    return NextResponse.json({ error: "workspace_mismatch" }, { status: 403 });
  }
  const callerRow = pageData.data.members.find((m) => m.userId === user.id);
  if (!callerRow || callerRow.role !== "owner") {
    return NextResponse.json({ error: "not_owner" }, { status: 403 });
  }

  const result = await revokeWorkspaceInvitation(invitationId, user.id);

  if (!result.ok) {
    const status =
      result.reason === "invitation_not_found"
        ? 404
        : result.reason === "caller_not_owner"
          ? 403
          : result.reason === "already_accepted" ||
              result.reason === "already_declined" ||
              result.reason === "already_revoked"
            ? 409
            : 500;
    return NextResponse.json({ error: result.reason }, { status });
  }
  return NextResponse.json({ ok: true });
}
