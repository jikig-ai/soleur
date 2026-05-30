import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import * as Sentry from "@sentry/nextjs";
import { reportSilentFallback } from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";

// feat-skip-api-key-onboarding (#4642). Persists the user's "Set up later"
// choice on /setup-key so the effective-key-aware redirect gates stop
// force-routing them back. Service-role write (a client-side updateUserField
// would silently no-op — mig 006 REVOKEd UPDATE on public.users). The
// affected-row-count assertion fails LOUD: a 0-row update (grant/RLS drift)
// would otherwise re-trap the user on next login with no signal.
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/setup-key/skip", origin);

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
    .update({ setup_key_skipped_at: new Date().toISOString() })
    .eq("id", user.id)
    .select("id");

  if (error || !data || data.length !== 1) {
    Sentry.withIsolationScope(() => {
      Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });
      reportSilentFallback(error, {
        feature: "setup-key-skip",
        op: "persist-skip",
        message: "setup_key_skipped_at update did not affect exactly one row",
        extra: { userId: user.id, affectedRows: data?.length ?? 0 },
      });
    });
    return NextResponse.json(
      { error: "Failed to record skip" },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true });
}
