import { createClient } from "@/lib/supabase/server";
import { verifiedUserId } from "@/server/request-auth";
import { NextResponse } from "next/server";
import {
  userHasEffectiveByokKey,
  userHasPendingByokDelegation,
} from "@/server/byok-resolver";
import { userIsSharedWorkspaceMember } from "@/server/workspace-resolver";

// feat-skip-api-key-onboarding (#4642). Self-fetch target for the dashboard
// NoApiKeyBanner. The layout is a client component and cannot run the
// service-role effective-key resolution, so the banner gates on this endpoint.
//
// userId is derived STRICTLY from the verified identity — the middleware-
// minted `x-soleur-auth-user-id` header (with getUser() fallback) — so any
// client userId/workspace query/body param is ignored (IDOR guard).
// hasEffectiveKey is computed fail-CLOSED so a transient
// resolver error shows the banner rather than hiding it and lying to a keyless
// user. The helpers return bare booleans and never leak a ByokDelegationError.
//
// isSharedWorkspaceMember (#4715) lets the banner distinguish a keyless invited
// member (joiner copy: "ask your owner or add your own") from a keyless solo
// user (the original "buy a paid account" copy). It is session-derived from the
// same authenticated userId, so the IDOR guard is preserved.
export async function GET(request: Request) {
  // Middleware-verified identity (x-soleur-auth-user-id) replaces the
  // getUser() RTT; absent header falls back to getUser() — fail-closed. The
  // IDOR guard is preserved: userId is still derived STRICTLY from the
  // verified session/header, never from a client param.
  const userId = await verifiedUserId(request);

  if (!userId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const supabase = await createClient();

  const hasEffectiveKey = await userHasEffectiveByokKey(userId, {
    onErrorReturn: false,
  });
  const pendingDelegation = await userHasPendingByokDelegation(userId);
  const isSharedWorkspaceMember = await userIsSharedWorkspaceMember(
    userId,
    supabase,
  );

  return NextResponse.json({
    hasEffectiveKey,
    pendingDelegation,
    isSharedWorkspaceMember,
  });
}
