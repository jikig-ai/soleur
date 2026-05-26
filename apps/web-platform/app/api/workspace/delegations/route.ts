import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { getCurrentOrganizationId } from "@/server/workspace-resolver";
import { resolveGrantorDelegations } from "@/server/byok-delegation-ui-resolver";

export async function GET(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/delegations", origin);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const orgId = getCurrentOrganizationId({ user: { id: user.id, app_metadata: user.app_metadata as Record<string, unknown> } });
  if (!orgId) return NextResponse.json({ error: "no_org" }, { status: 403 });

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isByokDelegationsEnabled(orgId, identity))) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  const url = new URL(request.url);
  const workspaceId = url.searchParams.get("workspaceId");
  if (!workspaceId) return NextResponse.json({ error: "missing_workspace_id" }, { status: 400 });

  const service = createServiceClient();
  const { data: membership } = await service
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", workspaceId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership) return NextResponse.json({ error: "not_member" }, { status: 403 });

  const delegations = await resolveGrantorDelegations(user.id, workspaceId, orgId, identity);
  return NextResponse.json({ delegations });
}

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/delegations", origin);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const orgId = getCurrentOrganizationId({ user: { id: user.id, app_metadata: user.app_metadata as Record<string, unknown> } });
  if (!orgId) return NextResponse.json({ error: "no_org" }, { status: 403 });

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isByokDelegationsEnabled(orgId, identity))) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: { workspaceId?: string; granteeUserId?: string; dailyCapCents?: number; hourlyCapCents?: number };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!body.workspaceId || !body.granteeUserId || !body.dailyCapCents) {
    return NextResponse.json({ error: "missing_fields" }, { status: 400 });
  }

  const service = createServiceClient();
  const { data: membership } = await service
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", body.workspaceId)
    .eq("user_id", user.id)
    .maybeSingle();
  if (!membership || membership.role !== "owner") {
    return NextResponse.json({ error: "not_owner" }, { status: 403 });
  }

  const { data, error } = await service.rpc("grant_byok_delegation", {
    p_grantor_user_id: user.id,
    p_grantee_user_id: body.granteeUserId,
    p_workspace_id: body.workspaceId,
    p_daily_cap_cents: body.dailyCapCents,
    p_hourly_cap_cents: body.hourlyCapCents ?? null,
    p_created_by_user_id: user.id,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ delegationId: data });
}

export async function DELETE(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/delegations", origin);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const orgId = getCurrentOrganizationId({ user: { id: user.id, app_metadata: user.app_metadata as Record<string, unknown> } });
  if (!orgId) return NextResponse.json({ error: "no_org" }, { status: 403 });

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isByokDelegationsEnabled(orgId, identity))) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: { delegationId?: string; reason?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!body.delegationId) {
    return NextResponse.json({ error: "missing_delegation_id" }, { status: 400 });
  }

  const service = createServiceClient();
  const { error } = await service.rpc("revoke_byok_delegation", {
    p_delegation_id: body.delegationId,
    p_revoked_by_user_id: user.id,
    p_revocation_reason: body.reason ?? "grantor_revoke",
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
