import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { resolveOrgMemberships } from "@/server/org-memberships-resolver";

// Powers the dashboard OrgSwitcher (Phase 5.3). Returns the user's full list
// of organization memberships with role + member count, plus an `isCurrent`
// marker derived from the JWT custom claim (migration 056).
//
// AC-C: solo users (memberships.length <= 1) get [] or a single-entry array;
// the OrgSwitcher client component renders nothing in either case.
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ memberships: [] }, { status: 401 });
  }
  const service = createServiceClient();
  const memberships = await resolveOrgMemberships(supabase, service);
  return NextResponse.json({ memberships });
}
