import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { rejectCsrf, validateOrigin } from "@/lib/auth/validate-origin";
import type { VerifiedUser } from "@/server/request-auth";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { reportLegalOp } from "@/server/approval/ops";
import { LegalServiceError, type LegalRpcClient } from "@/server/legal-acceptance/service";
import {
  CODE_RE,
  createThrowawayAuthClient,
  guardLegalRequest,
  sendReauthCode,
  verifyReauthCode,
  type IdentityClient,
} from "@/server/legal-acceptance/reauth";

/**
 * POST /api/legal-acceptance/[key]/reauth — the in-place email-code check (#12011 PR-C, ADR-319).
 *
 * Body: {step:"send", resend?:boolean} or {step:"verify", code}. Responses (wire types in lib/legal-acceptance-wire.ts):
 * 200 LegalReauthSendResult | LegalReauthVerifyResult · 400 malformed body · 401 unauthenticated or no web session ·
 * 403 CSRF (absent or foreign Origin) or a non-web (runtime-audience) token · 404 flag off or unknown key · 415 not JSON ·
 * 429 (wrapper) · 500.
 *
 * Auth posture: cookie session (NOT a PUBLIC_PATHS entry). The founder id and address come from `getUser()` on the
 * user-context client; the body never carries an identity. The code is sent and verified on a throwaway anon client, so
 * the founder's own session (which the intent is bound to) never changes. Thin HTTP-only export
 * (cq-nextjs-route-files-http-only-exports); the logic is in server/legal-acceptance/reauth.ts.
 */

export const dynamic = "force-dynamic";

async function reauthHandler(req: Request, user: VerifiedUser): Promise<Response> {
  try {
    const supabase = await createClient();
    const g = await guardLegalRequest(req, user.id, {
      supabase: supabase as unknown as IdentityClient,
      isEnabled: (userId) => isApprovalQueueEnabled({ userId, workspaceId: null }),
    });
    if (!g.ok) return NextResponse.json({ error: g.error }, { status: g.status });

    const deps = { service: createServiceClient() as unknown as LegalRpcClient, authClient: createThrowawayAuthClient };
    const { step, resend, code } = g.body as { step?: unknown; resend?: unknown; code?: unknown };

    if (step === "send") {
      if (resend !== undefined && typeof resend !== "boolean") return NextResponse.json({ error: "Invalid body" }, { status: 400 });
      return NextResponse.json(await sendReauthCode(deps, { id: g.id, entry: g.entry, resend: resend === true }));
    }
    if (step === "verify") {
      if (typeof code !== "string" || !CODE_RE.test(code)) return NextResponse.json({ error: "Invalid body" }, { status: 400 });
      return NextResponse.json(await verifyReauthCode(deps, { id: g.id, entry: g.entry, code }));
    }
    return NextResponse.json({ error: "Invalid body" }, { status: 400 });
  } catch (err) {
    // A database failure: nothing was recorded. Static message; the SQLSTATE and RPC name only.
    reportLegalOp("reauthFailed", err instanceof LegalServiceError ? err : null, { userId: user.id, extra: { stage: "route" } });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}

const rateLimited = withUserRateLimit(reauthHandler, { perMinute: 20, feature: "legal-acceptance.reauth" });

export async function POST(request: Request): Promise<Response> {
  // Fail closed: the shared validateOrigin lets a request with neither Origin nor Referer through (non-browser clients).
  // A browser POST always sends Origin, and this route is cookie-authenticated, so an absent Origin is refused.
  if (!request.headers.get("origin")) return rejectCsrf("api/legal-acceptance/[key]/reauth", null);
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/legal-acceptance/[key]/reauth", origin);
  return rateLimited(request);
}
