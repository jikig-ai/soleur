// feat-l5-runaway-guard PR-A — POST /api/dashboard/runtime/resume
//
// The operator-resume clearer. This is the ONLY code path in the codebase
// that sets users.runtime_paused_at = NULL (AC2, set-never-clear contract):
// the cap RPC and the spawn-entry gate only READ or SET the pause, never
// clear it. Reachable from the halt banner / email CTA ("Clear pause &
// resume"). Terminal-halt model (no checkpoint resume): clearing the pause
// lets the founder start a FRESH run.
//
// Auth model (mirrors the /cancel route):
//   1. Origin / CSRF gate at the route boundary.
//   2. Supabase tenant client auth.getUser() — cookie-scoped.
//   3. Service-role UPDATE scoped to the caller's OWN server-derived id.
//      `users` has no permissive UPDATE RLS for tenants, so the service-role
//      bypass is bounded by the `id = user.id` predicate — no cross-tenant
//      surface (the id is server-derived from the session, never client-
//      supplied).
//
// Idempotency: clearing an already-clear pause is a harmless no-op (the
// UPDATE writes NULL over NULL). `.select("id")` reads the row back so a
// 0-row match (a missing user row) fails LOUD instead of a false 200
// (supabase .update().eq() returns no error on 0 matched rows).
//
// Per cq-nextjs-route-files-http-only-exports: only HTTP exports + dynamic.

import { NextResponse } from "next/server";

import { createClient } from "@/lib/supabase/server";
import { getServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";

export const dynamic = "force-dynamic";

export async function POST(req: Request) {
  const { valid, origin } = validateOrigin(req);
  if (!valid) return rejectCsrf("api/dashboard/runtime/resume", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const service = getServiceClient();
  const { data, error } = await service
    .from("users")
    .update({ runtime_paused_at: null })
    .eq("id", user.id)
    .select("id");
  if (error) {
    reportSilentFallback(error, {
      feature: "runtime-resume",
      op: "clear-pause",
      message: "users runtime_paused_at clear failed",
      extra: { userId: user.id },
    });
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }
  if (!data || data.length !== 1) {
    reportSilentFallback(
      new Error(`runtime-resume clear matched ${data?.length ?? 0} rows for own id`),
      {
        feature: "runtime-resume",
        op: "clear-pause-rowcount",
        message: "resume clear matched != 1 row",
        extra: { userId: user.id },
      },
    );
    return NextResponse.json({ error: "internal_error" }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
