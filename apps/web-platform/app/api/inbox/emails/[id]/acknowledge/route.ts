import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

/**
 * POST /api/inbox/emails/[id]/acknowledge — operator saw a triage item.
 *
 * Verb-subresource per the codebase's lifecycle-transition family
 * (precedent: dashboard/today/[id]/cancel — POST-on-verb, never
 * PATCH /status). Sibling: .../archive (keep both files in lockstep).
 *
 * Auth: `withUserRateLimit` + user-context Supabase client (NEVER the
 * service client — RLS bypass). The `set_email_triage_status` SECURITY
 * DEFINER RPC enforces BOTH ownership (auth.uid() pin; missing row and
 * foreign row collapse to the same 42501 — no existence oracle) and the
 * one-way transition matrix (new → acknowledged|archived) IN the DB;
 * everything here is defense-in-depth.
 *
 * `withUserRateLimit`'s wrapper signature does not thread Next's dynamic
 * params, so the [id] segment is parsed from the URL path (UUID-validated
 * before the RPC).
 *
 * Responses:
 *   200 { ok: true }   transition applied
 *   400                malformed id segment
 *   401 / 429          wrapper
 *   404                not found / not owned (RPC 42501)
 *   409                invalid transition (RPC P0001)
 *   500                anything else (Sentry-mirrored; no PII in logs)
 */

export const dynamic = "force-dynamic";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function postHandler(req: Request, user: User) {
  // Path shape: /api/inbox/emails/<id>/acknowledge
  const segments = new URL(req.url).pathname.split("/").filter(Boolean);
  const id = segments.at(-2) ?? "";
  if (!UUID_PATTERN.test(id)) {
    return NextResponse.json({ error: "Invalid id" }, { status: 400 });
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("set_email_triage_status", {
    p_id: id,
    p_status: "acknowledged",
  });

  if (error) {
    // 42501 = ownership pin (missing + foreign rows collapse — keep the
    // no-existence-oracle property by answering 404 for both).
    if (error.code === "42501") {
      return NextResponse.json({ error: "Not found" }, { status: 404 });
    }
    // P0001 = one-way transition matrix rejection.
    if (error.code === "P0001") {
      return NextResponse.json({ error: "Invalid transition" }, { status: 409 });
    }
    // No PII: never log sender/subject/summary — ids only.
    reportSilentFallback(error, {
      feature: "inbox-emails",
      op: "acknowledge",
      message: "set_email_triage_status RPC failed",
      extra: { userId: user.id, emailId: id },
    });
    return NextResponse.json({ error: "Internal error" }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}

export const POST = withUserRateLimit(postHandler, {
  perMinute: 60,
  feature: "inbox.emails.acknowledge",
});
