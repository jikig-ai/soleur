/**
 * Shared handler factory for the email-triage lifecycle-transition routes
 * (POST /api/inbox/emails/[id]/{acknowledge,archive}). The two routes were
 * ~90% duplicates; the route files stay thin HTTP-only exports
 * (cq-nextjs-route-files-http-only-exports) and the contract lives here.
 *
 * Auth: callers wrap the returned handler in `withUserRateLimit` + the
 * user-context Supabase client (NEVER the service client — RLS bypass).
 * The `set_email_triage_status` SECURITY DEFINER RPC enforces BOTH
 * authorization (mig 111: any Owner of the row's workspace; missing row and
 * non-owned row collapse to the same 42501 — no existence oracle) and the
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

import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createClient } from "@/lib/supabase/server";
import { reportSilentFallback } from "@/server/observability";

const UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const OP_BY_STATUS = {
  acknowledged: "acknowledge",
  archived: "archive",
} as const;

export function makeEmailTriageStatusHandler(
  status: "acknowledged" | "archived",
) {
  return async function postHandler(req: Request, user: User) {
    // Path shape: /api/inbox/emails/<id>/<verb>
    const segments = new URL(req.url).pathname.split("/").filter(Boolean);
    const id = segments.at(-2) ?? "";
    if (!UUID_PATTERN.test(id)) {
      return NextResponse.json({ error: "Invalid id" }, { status: 400 });
    }

    const supabase = await createClient();
    const { error } = await supabase.rpc("set_email_triage_status", {
      p_id: id,
      p_status: status,
    });

    if (error) {
      // 42501 = ownership pin (missing + foreign rows collapse — keep the
      // no-existence-oracle property by answering 404 for both).
      if (error.code === "42501") {
        return NextResponse.json({ error: "Not found" }, { status: 404 });
      }
      // P0001 = one-way transition matrix rejection.
      if (error.code === "P0001") {
        return NextResponse.json(
          { error: "Invalid transition" },
          { status: 409 },
        );
      }
      // No PII: never log sender/subject/summary — ids only.
      reportSilentFallback(error, {
        feature: "inbox-emails",
        op: OP_BY_STATUS[status],
        message: "set_email_triage_status RPC failed",
        extra: { userId: user.id, emailId: id },
      });
      return NextResponse.json({ error: "Internal error" }, { status: 500 });
    }

    return NextResponse.json({ ok: true });
  };
}
