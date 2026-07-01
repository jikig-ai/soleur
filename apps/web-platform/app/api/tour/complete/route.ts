// feat-guided-tour (#5743): persist guided-tour completion.
//
// Service-role write — a client-side users UPDATE would silently no-op (mig 006
// REVOKEd UPDATE on public.users except the `email` column). Cookie-authed: the
// route resolves the session user itself, so it is NOT in PUBLIC_PATHS.
// Idempotent: called on both Finish and Skip; stamps tour_completed_at = now().

import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import * as Sentry from "@sentry/nextjs";
import { reportSilentFallback } from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/tour/complete", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();
  const { data, error } = await serviceClient
    .from("users")
    .update({ tour_completed_at: new Date().toISOString() })
    .eq("id", user.id)
    .select("id");

  if (error || !data || data.length !== 1) {
    Sentry.withIsolationScope(() => {
      Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });
      reportSilentFallback(error, {
        feature: "tour-complete",
        op: "persist",
        message: "tour_completed_at update did not affect exactly one row",
        extra: { affectedRows: data?.length ?? 0 },
      });
    });
    return NextResponse.json({ error: "Failed to record tour" }, { status: 500 });
  }

  return NextResponse.json({ ok: true });
}
