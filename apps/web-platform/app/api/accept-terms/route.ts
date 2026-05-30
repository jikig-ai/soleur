import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import { TC_VERSION, TC_DOCUMENT_SHA } from "@/lib/legal/tc-version";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { safeReturnTo } from "@/lib/safe-return-to";
import * as Sentry from "@sentry/nextjs";
import { reportSilentFallback } from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";
import { userHasEffectiveByokKey } from "@/server/byok-resolver";
import { shouldRouteToSetupKey } from "@/lib/onboarding/setup-key-gate";

// Delegation+skip-aware (#4642). Effective-key = own valid key OR accepted
// delegation; `onErrorReturn: true` fails OPEN so a transient resolver error
// never traps a possibly-delegated user at /setup-key (chat-time enforcement
// is authoritative). The skip flag honors an explicit "Set up later" — read
// via the session client (RLS owner-SELECT) so the service client stays
// confined to the RPC consent write.
async function getRedirectDestination(
  supabase: SupabaseClient,
  userId: string,
  nextHop: string | null,
): Promise<string> {
  const hasEffectiveKey = await userHasEffectiveByokKey(userId, {
    onErrorReturn: true,
  });
  const { data: row } = await supabase
    .from("users")
    .select("setup_key_skipped_at")
    .eq("id", userId)
    .maybeSingle();
  const setupKeySkippedAt =
    (row?.setup_key_skipped_at as string | null | undefined) ?? null;

  // Onboarding gate (#4642): show /setup-key only when the user has no
  // effective key (own valid key OR accepted delegation) AND has not chosen
  // "Set up later". Thread the validated invite next-hop through it (#4641) so
  // a brand-new invitee auto-returns to /invite/<token> AFTER onboarding
  // (T&C recorded first, then key → repo → invite). A keyed OR skipped user
  // honors the next hop directly, else lands on the dashboard.
  if (shouldRouteToSetupKey({ hasEffectiveKey, setupKeySkippedAt })) {
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
