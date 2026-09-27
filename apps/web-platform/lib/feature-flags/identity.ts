import { cache } from "react";
import { headers } from "next/headers";
import type { SupabaseClient } from "@supabase/supabase-js";
import { sessionJwtEmailForVerifiedUser } from "@/server/request-auth";
import { ANON_IDENTITY, type Identity, type Role } from "./server";

// Bounded wait on the remote selects below (#8978): cold-upstream stalls of
// 20–37 s were measured on this pair; the bound reclassifies a stall into the
// pre-existing `error || !data` degrade arm (prd role, null fields) rather
// than hanging the document. Generous vs the ~100–300 ms warm-path reads.
// Read lazily so a test can pin a short bound via env stub.
const identitySelectTimeoutMs = () =>
  Number(process.env.SOLEUR_IDENTITY_SELECT_TIMEOUT_MS) || 8_000;

export const resolveIdentity = cache(async (
  supabase: SupabaseClient,
): Promise<Identity> => {
  // Fast path (#8978 Phase 1.2): a middleware-minted `x-soleur-auth-user-id`
  // plus a LOCAL session-JWT decode supply id + email without the remote
  // getUser() RTT. The header is minted only after `getUser()` succeeds in
  // middleware (and is deleted inbound before any exit can forward a forged
  // value), so its presence means this request already authenticated — the
  // helper re-reads the claims the session cookie carries, accepting them
  // only when the token's own `sub` agrees with the minted id. Absent header
  // / mismatched sub / missing email claim / malformed token ⇒ remote
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
    email = await sessionJwtEmailForVerifiedUser(supabase, mintedUserId);
    if (email !== null) {
      userId = mintedUserId;
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
  // payment banners without a post-hydration mount effect. Both carry a
  // bounded wait (#8978): post-merge Sentry spans measured these two
  // selects stalling 20–37 s on a cold upstream — an abort resolves as a
  // PostgREST error object, landing on the EXISTING degrade arm below
  // (role:"prd", orgId/subscriptionStatus null) instead of hanging the
  // document render. userId/email are unaffected — both come from the
  // minted-header fast path or the remote getUser() above.
  const [{ data, error }, { data: memberData }] = await Promise.all([
    supabase
      .from("users")
      .select("role, subscription_status")
      .eq("id", userId)
      .abortSignal(AbortSignal.timeout(identitySelectTimeoutMs()))
      .single<{ role: unknown; subscription_status: string | null }>(),
    supabase
      .from("workspace_members")
      .select("workspace_id, workspaces!inner(organization_id)")
      .eq("user_id", userId)
      .order("created_at", { ascending: true })
      .limit(1)
      .abortSignal(AbortSignal.timeout(identitySelectTimeoutMs()))
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
