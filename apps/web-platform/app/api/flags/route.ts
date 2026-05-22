import { getFeatureFlags } from "@/lib/feature-flags/server";
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { createClient as createSupabaseServerClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

// Returns the caller's identity-scoped feature-flag snapshot (per role,
// see ADR-038 v2). One Supabase auth lookup + one users.role select per
// request; runtime flag values are cached server-side per role (30s TTL),
// so the Flagsmith round-trip is amortised across requests in the same
// role bucket. Still no per-IP rate limit — payload is small and cost is
// bounded by the role-keyed cache. Re-audit if we ever expose a list-all
// flags endpoint that takes parameters.
export async function GET() {
  const supabase = await createSupabaseServerClient();
  const identity = await resolveIdentity(supabase);
  return NextResponse.json(await getFeatureFlags(identity));
}
