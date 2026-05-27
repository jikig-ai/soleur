import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { createWorkspaceInvitation } from "@/server/workspace-invitations";
import { sendInviteEmail } from "@/server/notifications";

// POST /api/workspace/invite-member
// Body: { workspaceId, email, role: "owner"|"member", attestationText }
export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/invite-member", origin);

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

  let body: {
    workspaceId?: unknown;
    email?: unknown;
    role?: unknown;
    attestationText?: unknown;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const workspaceId = body.workspaceId;
  const email = body.email;
  const role = body.role;
  const attestationText = body.attestationText;
  if (
    typeof workspaceId !== "string" ||
    typeof email !== "string" ||
    !email.includes("@") ||
    (role !== "owner" && role !== "member") ||
    typeof attestationText !== "string" ||
    attestationText.length < 10
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

  const result = await createWorkspaceInvitation({
    callerUserId: user.id,
    workspaceId,
    inviteeEmail: email.trim(),
    role: role as "owner" | "member",
    attestationText,
  });

  if (!result.ok) {
    const status =
      result.reason === "invitee_already_member"
        ? 409
        : result.reason === "duplicate_pending_invite"
          ? 409
          : result.reason === "caller_not_owner"
            ? 403
            : 500;
    return NextResponse.json({ error: result.reason }, { status });
  }

  const inviterName =
    user.user_metadata?.full_name ?? user.email ?? "A team member";

  sendInviteEmail(
    email.trim(),
    inviterName,
    pageData.data.workspaceName ?? "Workspace",
    result.token,
  ).catch(() => {});

  return NextResponse.json({
    ok: true,
    invitationId: result.invitationId,
    attestationId: result.attestationId,
  });
}
