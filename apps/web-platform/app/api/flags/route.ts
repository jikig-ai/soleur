import { getFeatureFlags } from "@/lib/feature-flags/server";
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { createClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

// Identity-scoped flag snapshot. One Supabase auth lookup + one users.role
// select per request; runtime flag values are cached server-side per role
// (30s TTL) so the Flagsmith RTT is amortised within a role bucket.
// No rate limit today — payload is small and the role cache bounds Flagsmith
// cost. Re-audit if this endpoint ever becomes a DoS surface or the response
// starts leaking sensitive role-distinguishing values.
export async function GET() {
  const supabase = await createClient();
  const identity = await resolveIdentity(supabase);
  return NextResponse.json(await getFeatureFlags(identity));
}
