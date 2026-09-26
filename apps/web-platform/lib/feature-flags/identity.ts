import { cache } from "react";
import { headers } from "next/headers";
import type { SupabaseClient } from "@supabase/supabase-js";
import { decodeJwtPayloadUnsafe } from "@/lib/supabase/tenant";
import { ANON_IDENTITY, type Identity, type Role } from "./server";

export const resolveIdentity = cache(async (
  supabase: SupabaseClient,
): Promise<Identity> => {
  // Fast path (#8978 Phase 1.2): a middleware-minted `x-soleur-auth-user-id`
  // plus a LOCAL session-JWT decode supply id + email without the remote
  // getUser() RTT. The header is minted only after `getUser()` succeeds in
  // middleware (and is deleted inbound before any exit can forward a forged
  // value), so its presence means this request already authenticated — the
  // JWT decode just re-reads the claims the session cookie carries. Absent
  // header / mismatched sub / missing email claim / malformed token ⇒ remote
  // re-verify, never trust (ADR-253 contract unchanged).
  let userId: string | null = null;
  let email: string | null = null;

  // `headers()` throws outside a request scope (direct invocation in tests,
  // scripts, non-RSC callers) — the absent arm is the re-verify path.
  let mintedUserId: string | null = null;
  try {
    mintedUserId = (await headers()).get("x-soleur-auth-user-id");
  } catch {
    mintedUserId = null;
  }

  if (mintedUserId) {
    const { data: sessionData } = await supabase.auth.getSession();
    const accessToken = sessionData?.session?.access_token;
    if (accessToken) {
      try {
        const payload = decodeJwtPayloadUnsafe(accessToken);
        // Accept only when the token's own subject AGREES with the minted id
        // and carries the email claim the Identity needs — any gap re-verifies.
        if (
          payload.sub === mintedUserId &&
          typeof payload.email === "string"
        ) {
          userId = mintedUserId;
          email = payload.email;
        }
      } catch {
        // Malformed JWT — fall through to remote verification.
      }
    }
  }

  if (userId === null) {
    const { data: userData, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userData.user) return ANON_IDENTITY;
    userId = userData.user.id;
    email = userData.user.email ?? null;
  }
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
    email,
    subscriptionStatus,
  };
});

function normaliseRole(value: unknown): Role {
  return value === "dev" ? "dev" : "prd";
}
