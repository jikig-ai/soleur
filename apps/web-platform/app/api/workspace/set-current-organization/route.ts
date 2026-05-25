import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

// AC-FLOW3: org-switcher writes user_session_state via the set_current_organization_id
// RPC (migration 060). Caller's supabase session refresh then propagates the new
// app_metadata.current_organization_id claim to all tabs on the next access-token
// refresh (~1 hour TTL; orgSwitcher.tsx forces refreshSession() to make this <1s).
//
// The RPC enforces membership (caller must be a workspace_members row in the
// target org) — see migration 060 §1.4.5. The route returns the RPC result
// verbatim; on permission-denied the RPC raises which surfaces as HTTP 500
// here. No client-side org-spoofing surface exists because the RPC re-checks
// auth.uid() against workspace_members.
export async function POST(request: Request) {
  // CSRF protection — drift-guard enforced via lib/auth/csrf-coverage.test.ts.
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/set-current-organization", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { organizationId?: unknown };
  try {
    body = (await request.json()) as { organizationId?: unknown };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const organizationId = body.organizationId;
  if (typeof organizationId !== "string" || organizationId.length === 0) {
    return NextResponse.json({ error: "missing_organization_id" }, { status: 400 });
  }

  const { error } = await supabase.rpc("set_current_organization_id", {
    p_org_id: organizationId,
  });
  if (error) {
    return NextResponse.json(
      { error: "rpc_failed", detail: error.message },
      { status: 403 },
    );
  }
  return NextResponse.json({ ok: true });
}
