import { NextResponse } from "next/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { verifiedUserId } from "@/server/request-auth";
import { resolveWebEgress } from "@/server/resolve-web-egress";
import {
  setWebEgress,
  WebEgressOwnerDeniedError,
} from "@/server/set-web-egress";
import { teardownEgressForwardersForWorkspace } from "@/server/egress-forwarder";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

// feat-open-web-egress (#9534) — per-workspace "Agent web access" toggle
// (active-workspace). Cookie-authenticated browser route; the read/write
// helpers resolve the active workspace server-side and the SECURITY DEFINER
// RPCs enforce member-read / owner-write. NOT added to PUBLIC_PATHS
// (browser/session caller).

export async function GET(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/web-egress", origin);

  const userId = await verifiedUserId(request);
  if (!userId) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const webEgress = await resolveWebEgress(userId);
  return NextResponse.json({ webEgress });
}

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/web-egress", origin);

  const userId = await verifiedUserId(request);
  if (!userId) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  let body: { value?: unknown };
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }
  if (typeof body.value !== "boolean") {
    return NextResponse.json({ error: "value_must_be_boolean" }, { status: 400 });
  }

  try {
    // The owner check lives in the SECURITY DEFINER RPC; a non-owner caller
    // raises (P0001) → WebEgressOwnerDeniedError → 403. A genuine infra fault
    // is NOT an authz denial → 500 (so it surfaces in 5xx alerting rather than
    // hiding behind a 403).
    // #12585 (CTO D1) — resolve the workspace ONCE so the write and the
    // teardown act on the same one. Turning web access off revokes this
    // host's live forwarders for that workspace immediately: a sandboxed
    // request is then denied egress-not-running and an allowed connection
    // dies at the closed listener. The other web host's forwarders are
    // revoked by the next-dispatch re-resolve (#12903).
    const workspaceId = await resolveCurrentWorkspaceId(userId, await getFreshTenantClient(userId));
    const webEgress = await setWebEgress(userId, body.value, workspaceId);
    if (webEgress === false) teardownEgressForwardersForWorkspace(workspaceId);
    return NextResponse.json({ webEgress });
  } catch (err) {
    if (err instanceof WebEgressOwnerDeniedError) {
      return NextResponse.json({ error: "not_authorized" }, { status: 403 });
    }
    return NextResponse.json({ error: "set_failed" }, { status: 500 });
  }
}
