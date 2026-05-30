import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import {
  userHasEffectiveByokKey,
  userHasPendingByokDelegation,
} from "@/server/byok-resolver";

// feat-skip-api-key-onboarding (#4642). Self-fetch target for the dashboard
// NoApiKeyBanner. The layout is a client component and cannot run the
// service-role effective-key resolution, so the banner gates on this endpoint.
//
// userId is derived STRICTLY from the authenticated session — `_request` is
// intentionally unread so any client userId/workspace query/body param is
// ignored (IDOR guard). hasEffectiveKey is computed fail-CLOSED so a transient
// resolver error shows the banner rather than hiding it and lying to a keyless
// user. The helpers return bare booleans and never leak a ByokDelegationError.
export async function GET(_request: Request) {
  void _request;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const hasEffectiveKey = await userHasEffectiveByokKey(user.id, {
    onErrorReturn: false,
  });
  const pendingDelegation = await userHasPendingByokDelegation(user.id);

  return NextResponse.json({ hasEffectiveKey, pendingDelegation });
}
