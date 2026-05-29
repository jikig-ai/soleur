import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { isByokDelegationsEnabled, type Identity } from "@/lib/feature-flags/server";
import { resolveCurrentOrganizationId } from "@/server/workspace-resolver";

// POST /api/workspace/delegations/withdraw — record a gate-side consent
// withdrawal (GDPR Art. 7(3); #4625 Phase 3). The withdraw is invoked AS
// the user: the SECURITY DEFINER RPC withdraw_byok_delegation_consent
// derives the grantee from auth.uid() (NO p_user_id — SS-F3) and is
// grantee-only. We therefore call the RPC on the USER-scoped client so
// auth.uid() resolves — NOT the service client.
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/delegations/withdraw", origin);

  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const orgId = await resolveCurrentOrganizationId(user.id, supabase);
  if (!orgId) return NextResponse.json({ error: "no_org" }, { status: 403 });

  const identity: Identity = { userId: user.id, role: "prd", orgId };
  if (!(await isByokDelegationsEnabled(orgId, identity))) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  let body: { delegationId?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!body.delegationId) {
    return NextResponse.json({ error: "missing_fields" }, { status: 400 });
  }

  // The RPC derives the user from auth.uid(); we pass ONLY the delegation
  // id. Grantee-only is enforced inside the RPC (raises P0002 otherwise).
  const { error } = await supabase.rpc("withdraw_byok_delegation_consent", {
    p_delegation_id: body.delegationId,
  });

  if (error) {
    if (error.code === "P0002") {
      return NextResponse.json({ error: "not_grantee" }, { status: 404 });
    }
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
