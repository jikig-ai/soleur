import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isTeamWorkspaceInviteEnabled } from "@/lib/feature-flags/server";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { inviteWorkspaceMember } from "@/server/workspace-membership";

// POST /api/workspace/invite-member
// Body: { workspaceId, identifier, role: "owner"|"member", attestationText }
//
// 2-key flag gate (AC-A + AC-F): the route is only reachable when both
// FLAG_TEAM_WORKSPACE_INVITE=1 AND the caller's current organization is in
// TEAM_WORKSPACE_ALLOWLIST_ORG_IDS. Returns 404 otherwise so the surface is
// indistinguishable from "route does not exist."
//
// CSRF: validateOrigin gated. AC-RATE-LIMIT: scope-out — see plan #4229
// follow-up; jikigai-only allowlist bounds exposure in this PR.
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

  // 2-key gate — resolveTeamMembershipPageData handles flag + allowlist check.
  // We reuse its result so the membership page and this endpoint cannot
  // diverge on whether the user has team-workspace access.
  const service = createServiceClient();
  const pageData = await resolveTeamMembershipPageData(supabase, service);
  if (!pageData.ok) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }
  // Belt-and-suspenders: re-check flag against the resolved org. The
  // resolver already short-circuits on flag-off but explicit is better here.
  if (!isTeamWorkspaceInviteEnabled(pageData.data.organizationId)) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: {
    workspaceId?: unknown;
    identifier?: unknown;
    role?: unknown;
    attestationText?: unknown;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const workspaceId = body.workspaceId;
  const identifier = body.identifier;
  const role = body.role;
  const attestationText = body.attestationText;
  if (
    typeof workspaceId !== "string" ||
    typeof identifier !== "string" ||
    (role !== "owner" && role !== "member") ||
    typeof attestationText !== "string" ||
    attestationText.length < 10
  ) {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }

  // Defense: ensure the requested workspaceId matches the caller's current
  // workspace. We don't want a malicious member of org-A to use this endpoint
  // to invite into org-B by passing org-B's workspace_id.
  if (workspaceId !== pageData.data.workspaceId) {
    return NextResponse.json({ error: "workspace_mismatch" }, { status: 403 });
  }

  // Verify the caller is an owner. We could rely on the RPC's check, but
  // surfacing 403 here is cleaner than waiting for the RPC's RAISE.
  const callerRow = pageData.data.members.find((m) => m.userId === user.id);
  if (!callerRow || callerRow.role !== "owner") {
    return NextResponse.json({ error: "not_owner" }, { status: 403 });
  }

  const identifierTrimmed = identifier.trim();
  const isEmail = identifierTrimmed.includes("@");
  const result = await inviteWorkspaceMember({
    callerUserId: user.id,
    workspaceId,
    invitee: isEmail
      ? { email: identifierTrimmed }
      : { userId: identifierTrimmed },
    role,
    attestationText,
  });

  if (!result.ok) {
    const status =
      result.reason === "invitee_not_found"
        ? 404
        : result.reason === "invitee_already_member"
          ? 409
          : result.reason === "caller_not_owner"
            ? 403
            : 500;
    return NextResponse.json(
      { error: result.reason, detail: result.detail },
      { status },
    );
  }
  return NextResponse.json({ ok: true, attestationId: result.attestationId });
}
