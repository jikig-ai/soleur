import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { rejectCsrf, validateOrigin } from "@/lib/auth/validate-origin";
import { isLegalChoice } from "@/lib/legal-acceptance-wire";
import { TEXT_HASH_RE } from "@/server/legal-acceptance/canonical";
import type { VerifiedUser } from "@/server/request-auth";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { reportLegalOp } from "@/server/approval/ops";
import { ACK_FLUSH_TIMEOUT_MS, decideLegal, LegalServiceError, normaliseNote, type LegalRpcClient } from "@/server/legal-acceptance/service";
import { runOffRequestPath } from "@/server/legal-acceptance/off-path";
import { guardLegalRequest, type IdentityClient } from "@/server/legal-acceptance/reauth";

/**
 * POST /api/legal-acceptance/[key]/decide — the founder's decision on a legal text (#12011 PR-C, ADR-319).
 *
 * Body: {choice, textHash, note?}. `textHash` is the hash the page showed; the route compares it with the registry and
 * never accepts text. Responses: 200 LegalDecideResult (recorded, already_recorded, replaced, expired, code_expired:
 * the last three mean nothing was recorded) · 400 malformed body · 401 · 403 `{error:"reverify"}` when no live intent /
 * email code counts (SQLSTATE 42501), 403 `{error:"Forbidden"}` for CSRF or a non-web token · 404 flag off or unknown
 * key · 413 body over 8 KiB · 415 · 429 · 500.
 *
 * The decision is recorded by `record_legal_acceptance` on the USER-context client (the actor is `auth.uid()`); the
 * service client only opens the intent for Decline and Request changes. Thin HTTP-only export.
 *
 * After a recorded decision, off the request path (`after()`), the route flushes the `accepted` event (2 s bound) and only
 * if that returned true writes the acknowledgement. A flush that throws or an ack write that fails is a `store_failed`
 * event (stage ack); a flush that answers false or times out writes a warning log line only. None of them changes the
 * response; `already_recorded` never acks. (`Sentry.flush` also answers true when there is no transport, so a true answer
 * proves the queue drained, not that Sentry received the event.)
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
      {
        service: createServiceClient() as unknown as LegalRpcClient,
        user: supabase as unknown as LegalRpcClient,
        // After a recorded decision the `accepted` event is flushed and, only if that succeeded, the row is acknowledged
        // (the check endpoint's `row_without_event` reconciliation). Both run after the response and never change it.
        flushEvents: () => Sentry.flush(ACK_FLUSH_TIMEOUT_MS),
        runOffPath: runOffRequestPath,
      },
      { userId: g.id.userId, sessionId: g.id.sessionId, entry: g.entry, choice, textHash, note: n.note },
    );
    // Contract with the dialog: the code check no longer counts, so it returns to the send step.
    if (out.kind === "forbidden") return NextResponse.json({ error: "reverify" }, { status: 403 });
    if (out.kind === "rate_limited") return NextResponse.json({ error: "Too many requests" }, { status: 429 });
    return NextResponse.json(out.result);
  } catch (err) {
    // Nothing was recorded. Routed by the legal-acceptance failure alert. The helper keeps only the code, RPC name and
    // class of the caught value; `reason` separates a database failure from anything else.
    reportLegalOp("decideRejected", err, {
      userId: user.id,
      tags: { reason: err instanceof LegalServiceError ? "db_error" : "unexpected" },
    });
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
