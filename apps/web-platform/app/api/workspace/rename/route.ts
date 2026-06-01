import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isTeamWorkspaceInviteEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveTeamMembershipPageData } from "@/server/team-membership-resolver";
import { renameOrganization } from "@/server/workspace-membership";

// POST /api/workspace/rename
// Body: { organizationId, name }
//
// Owner-gated rename of the organization display name (the org switcher label).
// Flag gate: reuses isTeamWorkspaceInviteEnabled (Flagsmith single-control) —
// returns 404 when disabled. CSRF: validateOrigin gated. Defense stack mirrors
// transfer-ownership/route.ts.
export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/rename", origin);

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

  let body: { organizationId?: unknown; name?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const organizationId = body.organizationId;
  const name = body.name;
  if (typeof organizationId !== "string" || typeof name !== "string") {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }
  const trimmed = name.trim();
  if (trimmed.length === 0 || trimmed.length > 60) {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }

  if (organizationId !== pageData.data.organizationId) {
    return NextResponse.json({ error: "org_mismatch" }, { status: 403 });
  }

  const callerRow = pageData.data.members.find((m) => m.userId === user.id);
  if (!callerRow || callerRow.role !== "owner") {
    return NextResponse.json({ error: "not_owner" }, { status: 403 });
  }

  const result = await renameOrganization({
    organizationId,
    name: trimmed,
    callerUserId: user.id,
  });

  if (!result.ok) {
    const status =
      result.reason === "invalid_name"
        ? 400
        : result.reason === "not_found"
          ? 404
          : result.reason === "caller_not_owner"
            ? 403
            : 500;
    return NextResponse.json(
      { error: result.reason, detail: result.detail },
      { status },
    );
  }
  return NextResponse.json({ ok: true, name: trimmed });
}
