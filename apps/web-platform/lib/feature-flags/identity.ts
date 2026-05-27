import { cache } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ANON_IDENTITY, type Identity, type Role } from "./server";

export const resolveIdentity = cache(async (
  supabase: SupabaseClient,
): Promise<Identity> => {
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) return ANON_IDENTITY;

  const userId = userData.user.id;
  const { data, error } = await supabase
    .from("users")
    .select("role")
    .eq("id", userId)
    .single<{ role: unknown }>();

  const role = error || !data ? "prd" as Role : normaliseRole(data.role);

  const { data: memberData } = await supabase
    .from("workspace_members")
    .select("workspace_id, workspaces!inner(organization_id)")
    .eq("user_id", userId)
    .order("created_at", { ascending: true })
    .limit(1)
    .single<{ workspace_id: string; workspaces: { organization_id: string } }>();

  const orgId = memberData?.workspaces?.organization_id ?? null;

  return { userId, role, orgId };
});

function normaliseRole(value: unknown): Role {
  return value === "dev" ? "dev" : "prd";
}
