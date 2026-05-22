import type { SupabaseClient } from "@supabase/supabase-js";
import { ANON_IDENTITY, type Identity, type Role } from "./server";

// Resolve the calling user's flag identity from a server-side Supabase
// client. Returns ANON_IDENTITY for logged-out requests, auth lookup
// failures, or any case where the `users.role` row can't be read — these
// all collapse to "treat as prd", which matches the fallback semantics
// documented in ADR-038 v2 (anonymous = prd, never dark-launch).
export async function resolveIdentity(supabase: SupabaseClient): Promise<Identity> {
  const { data: userData, error: userErr } = await supabase.auth.getUser();
  if (userErr || !userData.user) return ANON_IDENTITY;

  const userId = userData.user.id;
  const { data, error } = await supabase
    .from("users")
    .select("role")
    .eq("id", userId)
    .single();
  if (error || !data) return { userId, role: "prd" };

  return { userId, role: normaliseRole((data as { role: unknown }).role) };
}

function normaliseRole(value: unknown): Role {
  return value === "dev" ? "dev" : "prd";
}
