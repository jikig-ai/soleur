import { cache } from "react";
import type { SupabaseClient } from "@supabase/supabase-js";
import { ANON_IDENTITY, type Identity, type Role } from "./server";

// Resolve the calling user's flag identity from a server-side Supabase
// client. Wrapped in React.cache so the underlying auth.getUser() + users.role
// select is amortised across all server components in the same request tree.
//
// Fail-safe direction: anonymous + auth failure → ANON_IDENTITY (anon prd).
// Authenticated-with-missing-row or unrecognised role value → preserves userId
// but defaults role to "prd". Either way the role can never escalate to "dev"
// on error (never dark-launch).
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
  if (error || !data) return { userId, role: "prd" };

  return { userId, role: normaliseRole(data.role) };
});

function normaliseRole(value: unknown): Role {
  return value === "dev" ? "dev" : "prd";
}
