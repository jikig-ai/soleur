import { getFreshTenantClient } from "@/lib/supabase/tenant";
import {
  isUntrustedContentClassifyEnabled,
  isUntrustedContentWrapEnabled,
  type Identity,
  type Role,
} from "@/lib/feature-flags/server";
import { mirrorWithDebounce } from "./observability";

export interface UntrustedContentFlags {
  classify: boolean;
  /** Subordinate to classify: wrap is forced false whenever classify is false. */
  wrap: boolean;
}

const OFF: UntrustedContentFlags = { classify: false, wrap: false };

/**
 * Resolve the two #4671 flags against the dispatch user's REAL identity (never
 * ANON_IDENTITY, which always reads the prd default). FAIL-OPEN to OFF: any resolution
 * error disables the hook (the scan is annotate-only and best-effort, so "off" is the
 * safe degraded state) and emits ONE debounced Sentry event (`flag-unresolved`).
 * Takes effect on the next query-options build; a running turn keeps its old state.
 */
export async function resolveUntrustedContentFlags(
  userId: string,
): Promise<UntrustedContentFlags> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { data: roleRow } = await tenant
      .from("users")
      .select("role")
      .eq("id", userId)
      .single<{ role: unknown }>();
    const role: Role = roleRow?.role === "dev" ? "dev" : "prd";
    const identity: Identity = { userId, role, orgId: null, email: null, subscriptionStatus: null };
    const classify = await isUntrustedContentClassifyEnabled(identity);
    if (!classify) return OFF;
    const wrap = await isUntrustedContentWrapEnabled(identity);
    return { classify: true, wrap };
  } catch (err) {
    mirrorWithDebounce(
      err,
      {
        feature: "untrusted-content",
        op: "flag-unresolved",
        message: "untrusted-content flag resolve failed; WebFetch scan disabled for this query",
      },
      userId,
      "untrusted-content-flag-unresolved",
    );
    return OFF;
  }
}
