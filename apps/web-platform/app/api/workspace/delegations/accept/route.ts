import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { getCurrentOrganizationId } from "@/server/workspace-resolver";
import { createHash } from "node:crypto";

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/delegations/accept", origin);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const orgId = getCurrentOrganizationId({ user: { id: user.id, app_metadata: user.app_metadata as Record<string, unknown> } });
  if (!orgId) return NextResponse.json({ error: "no_org" }, { status: 403 });

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isByokDelegationsEnabled(orgId, identity))) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: { delegationId?: string; sideLetterVersion?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!body.delegationId || !body.sideLetterVersion) {
    return NextResponse.json({ error: "missing_fields" }, { status: 400 });
  }

  const service = createServiceClient();
  const { data: delegation, error: fetchErr } = await service
    .from("byok_delegations")
    .select("id, grantee_user_id, revoked_at")
    .eq("id", body.delegationId)
    .maybeSingle();

  if (fetchErr || !delegation) {
    return NextResponse.json({ error: "delegation_not_found" }, { status: 404 });
  }

  if ((delegation.grantee_user_id as string) !== user.id) {
    return NextResponse.json({ error: "not_grantee" }, { status: 403 });
  }

  if (delegation.revoked_at) {
    return NextResponse.json({ error: "delegation_revoked" }, { status: 400 });
  }

  const forwarded = request.headers.get("x-forwarded-for");
  const ipHash = forwarded
    ? createHash("sha256").update(forwarded.split(",")[0].trim()).digest("hex")
    : null;
  const userAgent = request.headers.get("user-agent")?.slice(0, 512) ?? null;

  const { error: insertErr } = await supabase
    .from("byok_delegation_acceptances")
    .insert({
      user_id: user.id,
      delegation_id: body.delegationId,
      side_letter_version: body.sideLetterVersion,
      ip_hash: ipHash,
      user_agent: userAgent,
    });

  if (insertErr) {
    if (insertErr.code === "23505") {
      return NextResponse.json({ ok: true, alreadyAccepted: true });
    }
    return NextResponse.json({ error: insertErr.message }, { status: 400 });
  }

  return NextResponse.json({ ok: true });
}
