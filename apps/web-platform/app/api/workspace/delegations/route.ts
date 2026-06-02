import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveCurrentOrganizationId } from "@/server/workspace-resolver";
import { resolveGrantorDelegations } from "@/server/byok-delegation-ui-resolver";
import { reportSilentFallback } from "@/server/observability";

export async function GET(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/delegations", origin);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
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

  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
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

  // Canonical 7-arg contract from migration 064 (mirrors scripts/byok-grant.ts).
  // PostgREST resolves rpc() by argument NAME — these MUST match the function
  // signature exactly or resolution fails (PGRST202 → 400 → silent toggle revert).
  // hourly defaults to the daily cap (RPC rejects NULL with 22003; the UI exposes
  // only a daily stepper). expires_at is null = never expires (UI-created grants).
  const { data, error } = await service.rpc("grant_byok_delegation", {
    p_grantor_user_id: user.id,
    p_grantee_user_id: body.granteeUserId,
    p_workspace_id: body.workspaceId,
    p_daily_usd_cap_cents: body.dailyCapCents,
    p_hourly_usd_cap_cents: body.hourlyCapCents ?? body.dailyCapCents,
    p_expires_at: null,
    p_actor_user_id: user.id,
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

  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
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

  const allowedReasons = ["grantor_revoke", "grantee_decline"] as const;
  const reason = body.reason ?? "grantor_revoke";
  if (!allowedReasons.includes(reason as typeof allowedReasons[number])) {
    return NextResponse.json({ error: "invalid_reason" }, { status: 400 });
  }

  const service = createServiceClient();

  const { data: delegation, error: probeError } = await service
    .from("byok_delegations")
    .select("grantor_user_id, grantee_user_id, revoked_at")
    .eq("id", body.delegationId)
    .maybeSingle();
  // A transient probe error must not masquerade as a 403 "forbidden" (the owner
  // would be told they may not stop their own spend). Mirror it and return 503
  // so the client retries (cq-silent-fallback-must-mirror-to-sentry).
  if (probeError) {
    reportSilentFallback(probeError, {
      feature: "byok-delegations",
      op: "DELETE.ownership-probe",
      extra: { userId: user.id, delegationId: body.delegationId },
    });
    return NextResponse.json({ error: "probe_failed" }, { status: 503 });
  }
  if (!delegation || (delegation.grantor_user_id !== user.id && delegation.grantee_user_id !== user.id)) {
    return NextResponse.json({ error: "forbidden" }, { status: 403 });
  }
  // Idempotent stop: if already revoked, the spend is already off. Returning
  // {ok:true} avoids the RPC's "already revoked" P0001 surfacing as a 400 →
  // "Couldn't stop sharing the key" on a double-click / concurrent decline.
  if (delegation.revoked_at !== null) {
    return NextResponse.json({ ok: true });
  }

  // Canonical 3-arg contract from migration 064 (064:495-498; mirrors
  // scripts/byok-revoke.ts:154-158). PostgREST resolves rpc() by argument NAME
  // — these MUST match the function signature exactly or resolution fails
  // (PGRST202 → 400 → the toggle can never be turned OFF). The legacy
  // p_revoked_by_user_id / p_revocation_reason names never existed on this RPC;
  // this is the same defect class #4761 fixed for the grant path.
  const { error } = await service.rpc("revoke_byok_delegation", {
    p_delegation_id: body.delegationId,
    p_actor_user_id: user.id,
    p_reason: reason,
  });

  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
