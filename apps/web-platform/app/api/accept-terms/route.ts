import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import { TC_VERSION, TC_DOCUMENT_SHA } from "@/lib/legal/tc-version";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { safeReturnTo } from "@/lib/safe-return-to";
import * as Sentry from "@sentry/nextjs";
import { reportSilentFallback } from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";

async function getRedirectDestination(
  supabase: SupabaseClient,
  userId: string,
  nextHop: string | null,
): Promise<string> {
  const { data: keys } = await supabase
    .from("api_keys")
    .select("id")
    .eq("user_id", userId)
    .eq("provider", "anthropic")
    .eq("is_valid", true)
    .limit(1);

  // No key yet → onboarding takes precedence, BUT thread the validated next hop
  // through it so a brand-new invitee auto-returns to /invite/<token> AFTER
  // onboarding (T&C recorded first, then key → repo → invite). setup-key carries
  // it to connect-repo, which lands on it. Keyed → honor the next hop directly.
  if (!keys || keys.length === 0) {
    return nextHop
      ? `/setup-key?redirectTo=${encodeURIComponent(nextHop)}`
      : "/setup-key";
  }
  return nextHop ?? "/dashboard";
}

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/accept-terms", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Optional post-acceptance destination, re-validated server-side against the
  // open-redirect allowlist (never trust the client-supplied value).
  let nextHop: string | null = null;
  try {
    const body = (await request.json()) as { redirectTo?: unknown };
    if (typeof body?.redirectTo === "string") {
      nextHop = safeReturnTo(body.redirectTo);
    }
  } catch {
    // No/invalid JSON body — proceed with the default destination.
  }

  // Always delegate to the public.accept_terms RPC. Idempotency lives in
  // SQL: the UPDATE on public.users is a no-op when tc_accepted_version
  // already matches, and the INSERT into public.tc_acceptances uses
  // ON CONFLICT (user_id, version) DO NOTHING. No client-side
  // early-return — re-acceptance of the same version is still a meaningful
  // heartbeat for tc_accepted_at.
  const serviceClient = createServiceClient();
  const { error } = await serviceClient.rpc("accept_terms", {
    p_user_id: user.id,
    p_version: TC_VERSION,
    p_doc_sha: TC_DOCUMENT_SHA,
  });

  if (error) {
    Sentry.withIsolationScope(() => {
      Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });
      reportSilentFallback(error, {
        feature: "accept-terms",
        op: "record",
        message: "Failed to record acceptance",
        extra: { userId: user.id },
      });
    });
    return NextResponse.json(
      { error: "Failed to record acceptance" },
      { status: 500 },
    );
  }

  const redirect = await getRedirectDestination(supabase, user.id, nextHop);
  return NextResponse.json({ ok: true, redirect });
}
