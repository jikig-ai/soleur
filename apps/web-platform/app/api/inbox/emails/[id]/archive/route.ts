import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

/**
 * POST /api/inbox/emails/[id]/archive — operator dismissed a triage item.
 *
 * Sibling of .../acknowledge (keep both files in lockstep); see that
 * route's header for the full contract. Same RPC, same DB-enforced
 * ownership + one-way transition matrix (new → acknowledged|archived),
 * same error mapping:
 *   404 ← RPC 42501 (not found / not owned — no existence oracle)
 *   409 ← RPC P0001 (invalid transition)
 *   500 ← anything else (Sentry-mirrored; no PII in logs)
 */

export const dynamic = "force-dynamic";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function postHandler(req: Request, user: User) {
  // Path shape: /api/inbox/emails/<id>/archive
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const id = segments.at(-2) ?? "";
  if (!UUID_PATTERN.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_email_triage_status", {
    p_id: id,
    p_status: "archived",
  });

  if (error) {
    if (error.code === "42501") {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    if (error.code === "P0001") {
      return NextResponse.json({ error: "Invalid transition" }, { status: 409 });
    }
    // No PII: never log sender/subject/summary — ids only.
    reportSilentFallback(error, {
      feature: "inbox-emails",
      op: "archive",
      message: "set_email_triage_status RPC failed",
      extra: { userId: user.id, emailId: id },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}

export const POST = withUserRateLimit(postHandler, {
  perMinute: 60,
  feature: "inbox.emails.archive",
});
