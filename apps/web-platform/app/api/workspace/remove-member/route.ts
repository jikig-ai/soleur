import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isTeamWorkspaceInviteEnabled } from "@/lib/feature-flags/server";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { removeWorkspaceMember } from "@/server/workspace-membership";

// POST /api/workspace/remove-member
// Body: { workspaceId, userId }
//
// AC-FLOW2: triggers in-flight agent SIGTERM + WS close with
// MEMBERSHIP_REVOKED preamble. AC-FLOW4: refuses owner-removes-self.
export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/remove-member", origin);

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
  if (!isTeamWorkspaceInviteEnabled(pageData.data.organizationId)) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: { workspaceId?: unknown; userId?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const workspaceId = body.workspaceId;
  const inviteeUserId = body.userId;
  if (
    typeof workspaceId !== "string" ||
    typeof inviteeUserId !== "string" ||
    workspaceId.length === 0 ||
    inviteeUserId.length === 0
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

  // Resolve organization name for the WS preamble (drives the terminal screen).
  let organizationName: string | null = null;
  try {
    const orgRow = (await service
      .from("organizations")
      .select("name")
      .eq("id", pageData.data.organizationId)
      .limit(1)) as { data: { name: string | null }[] | null; error: unknown };
    organizationName = orgRow.data?.[0]?.name ?? null;
  } catch {
    // Silent — falls back to "this workspace" UX copy on the client.
  }

  const result = await removeWorkspaceMember({
    callerUserId: user.id,
    workspaceId,
    inviteeUserId,
    organizationName,
  });

  if (!result.ok) {
    const status =
      result.reason === "owner_cannot_remove_self"
        ? 403
        : result.reason === "not_a_member"
          ? 404
          : result.reason === "caller_not_owner"
            ? 403
            : 500;
    return NextResponse.json(
      { error: result.reason, detail: result.detail },
      { status },
    );
  }
  return NextResponse.json({ ok: true });
}
