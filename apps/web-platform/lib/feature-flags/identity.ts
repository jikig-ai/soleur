import { cache } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ANON_IDENTITY, type Identity, type Role } from "./server";

export const resolveIdentity = cache(async (
  supabase: SupabaseClient,
): Promise<Identity> => {
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) return ANON_IDENTITY;

  const userId = userData.user.id;
  // The two selects are independent — run them concurrently (Phase 3,
  // perf-dashboard-section-load-latency). The users select is extended to
  // `subscription_status` so the dashboard layout can server-render the
  // payment banners without a post-hydration mount effect.
  const [{ data, error }, { data: memberData }] = await Promise.all([
    supabase
      .from("users")
      .select("role, subscription_status")
      .eq("id", userId)
      .single<{ role: unknown; subscription_status: string | null }>(),
    supabase
      .from("workspace_members")
      .select("workspace_id, workspaces!inner(organization_id)")
      .eq("user_id", userId)
      .order("created_at", { ascending: true })
      .limit(1)
      .single<{ workspace_id: string; workspaces: { organization_id: string } }>(),
  ]);

  const role = error || !data ? "prd" as Role : normaliseRole(data.role);
  const subscriptionStatus = error || !data ? null : (data.subscription_status ?? null);

  const orgId = memberData?.workspaces?.organization_id ?? null;

  return {
    userId,
    role,
    orgId,
    email: userData.user.email ?? null,
    subscriptionStatus,
  };
});

function normaliseRole(value: unknown): Role {
  return value === "dev" ? "dev" : "prd";
}
