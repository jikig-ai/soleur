import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { rejectCsrf, validateOrigin } from "@/lib/auth/validate-origin";
import { isLegalChoice } from "@/lib/legal-acceptance-wire";
import { TEXT_HASH_RE } from "@/server/legal-acceptance/canonical";
import type { VerifiedUser } from "@/server/request-auth";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { reportLegalOp } from "@/server/approval/ops";
import { decideLegal, LegalServiceError, normaliseNote, type LegalRpcClient } from "@/server/legal-acceptance/service";
import { guardLegalRequest, type IdentityClient } from "@/server/legal-acceptance/reauth";

/**
 * POST /api/legal-acceptance/[key]/decide — the founder's decision on a legal text (#12011 PR-C, ADR-319).
 *
 * Body: {choice, textHash, note?}. `textHash` is the hash the page showed; the route compares it with the registry and
 * never accepts text. Responses: 200 LegalDecideResult (recorded, already_recorded, replaced, expired, code_expired:
 * the last three mean nothing was recorded) · 400 malformed body · 401 · 403 CSRF, a non-web token, or no live intent /
 * email code required (SQLSTATE 42501) · 404 flag off or unknown key · 415 · 429 · 500.
 *
 * The decision is recorded by `record_legal_acceptance` on the USER-context client (the actor is `auth.uid()`); the
 * service client only opens the intent for Decline and Request changes. Thin HTTP-only export.
 */

export const dynamic = "force-dynamic";

async function decideHandler(req: Request, user: VerifiedUser): Promise<Response> {
  try {
    const supabase = await createClient();
    const g = await guardLegalRequest(req, user.id, {
      supabase: supabase as unknown as IdentityClient,
      isEnabled: (userId) => isApprovalQueueEnabled({ userId, workspaceId: null }),
    });
    if (!g.ok) return NextResponse.json({ error: g.error }, { status: g.status });

    const { choice, textHash, note } = g.body as { choice?: unknown; textHash?: unknown; note?: unknown };
    if (!isLegalChoice(choice) || typeof textHash !== "string" || !TEXT_HASH_RE.test(textHash)) {
      return NextResponse.json({ error: "Invalid body" }, { status: 400 });
    }
    const n = normaliseNote(choice, note);
    if (!n.ok) return NextResponse.json({ error: "Invalid body" }, { status: 400 });

    const out = await decideLegal(
      { service: createServiceClient() as unknown as LegalRpcClient, user: supabase as unknown as LegalRpcClient },
      { userId: g.id.userId, sessionId: g.id.sessionId, entry: g.entry, choice, textHash, note: n.note },
    );
    if (out.kind === "forbidden") return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    if (out.kind === "rate_limited") return NextResponse.json({ error: "Too many requests" }, { status: 429 });
    return NextResponse.json(out.result);
  } catch (err) {
    // A database failure on the decision path: nothing was recorded. Routed by the legal-acceptance failure alert.
    reportLegalOp("decideRejected", err instanceof LegalServiceError ? err : null, { userId: user.id, tags: { reason: "db_error" } });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }
}

const rateLimited = withUserRateLimit(decideHandler, { perMinute: 20, feature: "legal-acceptance.decide" });

export async function POST(request: Request): Promise<Response> {
  // Fail closed on an absent Origin (see the reauth route).
  if (!request.headers.get("origin")) return rejectCsrf("api/legal-acceptance/[key]/decide", null);
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/legal-acceptance/[key]/decide", origin);
  return rateLimited(request);
}
