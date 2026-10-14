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

/** Upper bound on the whole resolution: a hung DB/Flagsmith read must not delay a turn start. */
export const RESOLVE_TIMEOUT_MS = 2000;

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  let t: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    t = setTimeout(() => reject(new Error("untrusted-content flag resolve timed out")), ms);
  });
  return Promise.race([p, timeout]).finally(() => {
    if (t !== undefined) clearTimeout(t);
  });
}

async function resolve(userId: string): Promise<UntrustedContentFlags> {
  const tenant = await getFreshTenantClient(userId);
  const { data: roleRow, error } = await tenant
    .from("users")
    .select("role")
    .eq("id", userId)
    .single<{ role: unknown }>();
  if (error) {
    // The role only picks the dev/prd Flagsmith segment. Degrade to prd (the default
    // segment) rather than disabling the control, but leave one debounced signal.
    mirrorWithDebounce(
      error,
      { feature: "untrusted-content", op: "role-read", message: "users.role read failed; resolving flags as prd" },
      userId,
      "untrusted-content-role-read",
    );
  }
  const role: Role = roleRow?.role === "dev" ? "dev" : "prd";
  const identity: Identity = { userId, role, orgId: null, email: null, subscriptionStatus: null };
  const classify = await isUntrustedContentClassifyEnabled(identity);
  if (!classify) return OFF;
  const wrap = await isUntrustedContentWrapEnabled(identity);
  return { classify: true, wrap };
}

/**
 * Resolve the two #4671 flags against the dispatch user's identity (role segment only: the
 * Flagsmith identifier is `role:<role>` and orgId is null, so this selects dev vs prd, not a
 * per-user canary). FAIL-OPEN to OFF: any resolution error or a 2 s timeout disables the hook
 * (the scan is annotate-only and best-effort, so "off" is the safe degraded state) and emits
 * ONE debounced Sentry event (`flag-unresolved`).
 *
 * Runs once per COLD conversation (the query factory is skipped on warm reuse), so a flag flip
 * reaches the next conversation start; a live conversation keeps its hooks until it is reaped
 * (~10 min idle, ADR-287).
 */
export async function resolveUntrustedContentFlags(
  userId: string,
): Promise<UntrustedContentFlags> {
  try {
    return await withTimeout(resolve(userId), RESOLVE_TIMEOUT_MS);
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
