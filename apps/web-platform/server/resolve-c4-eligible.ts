import { getFreshTenantClient } from "@/lib/supabase/tenant";
import {
  getRuntimeFlag,
  type Role,
} from "@/lib/feature-flags/server";
import { C4_VISUALIZER_FLAG } from "@/lib/c4-constants";
import { getCurrentRepoUrl } from "./current-repo-url";
import { resolveInstallationId } from "./resolve-installation-id";
import { resolveEffectiveInstallationId } from "./cc-effective-installation";
import { parseConnectedRepo } from "./github-repo-parse";

/**
 * Resolve the `c4-visualizer` Flagsmith flag for the dispatch user's real role
 * (the dev-cohort segment). The SINGLE source of truth for the c4 flag decision,
 * shared by:
 *   - `realSdkQueryFactory` (cc-dispatcher) — gates whether the edit_c4_diagram
 *     tool is BUILT into the soleur_platform MCP server this (cold) dispatch.
 *   - `resolveC4Eligible` below — gates whether the dispatcher ADVERTISES the c4
 *     FQN to the unregistered-tool mirror predicate this dispatch (cold + warm).
 *
 * Sharing this helper is load-bearing: if the two call sites resolved the flag
 * independently they could drift, and an over-permissive advertise would suppress
 * a GENUINE unregistered-tool mirror (the #5388 / #2909 FR2 silent-failure
 * surface). Role is read from the SAME `users.role` shape as the debug-mode and
 * (pre-extraction) inline c4 gates.
 *
 * Throws on a tenant/role-read error — callers fail closed (treat as NOT eligible
 * and mirror the failure). The Flagsmith dimension does NOT throw: `getRuntimeFlag`
 * catches an upstream outage internally and degrades to the `RUNTIME_FLAGS`
 * env-fallback — the SAME value both call sites get, so parity is preserved even
 * on a Flagsmith outage.
 */
export async function resolveC4FlagEnabled(userId: string): Promise<boolean> {
  const tenant = await getFreshTenantClient(userId);
  const { data: roleRow } = await tenant
    .from("users")
    .select("role")
    .eq("id", userId)
    .single<{ role: unknown }>();
  const role: Role = roleRow?.role === "dev" ? "dev" : "prd";
  return getRuntimeFlag(C4_VISUALIZER_FLAG, { userId, role, orgId: null });
}

/**
 * Resolve the FULL edit_c4_diagram eligibility for a user from `userId` alone —
 * the same precondition set `realSdkQueryFactory`'s c4 gate requires
 * (`effectiveInstallationId !== null && owner && repo && c4Enabled`), but
 * reachable WITHOUT factory-scoped state.
 *
 * Why userId-only matters: the factory runs ONLY on a COLD conversation
 * (`soleur-go-runner.ts` `if (!state)`); on warm-query reuse it is not
 * re-invoked. The dispatcher's per-dispatch registered-tool resolve must work on
 * BOTH cold and warm turns, so it cannot read the factory's `c4ToolName` — it
 * re-resolves here using the SAME userId-keyed primitives the factory uses
 * (`getCurrentRepoUrl`, `resolveInstallationId`, `resolveEffectiveInstallationId`,
 * the shared `parseConnectedRepo`, and the shared `resolveC4FlagEnabled`).
 *
 * Precondition parity is load-bearing (the #5388 AC2 guard): this MUST NOT report
 * eligible more permissively than the factory registers the tool, or the
 * dispatcher would advertise the c4 FQN for a dispatch where the tool was never
 * built — re-introducing the false-suppression bug. The flag is checked LAST,
 * after the installation + owner/repo preconditions, mirroring the factory order.
 *
 * Throws on a resolution error — callers fail closed (c4 FQN excluded + mirror).
 */
export async function resolveC4Eligible(userId: string): Promise<boolean> {
  const [repoUrl, installationId] = await Promise.all([
    getCurrentRepoUrl(userId),
    resolveInstallationId(userId),
  ]);

  const parsed = parseConnectedRepo(repoUrl);
  if (!parsed) return false;

  const effectiveInstallationId = await resolveEffectiveInstallationId({
    userId,
    installationId,
    repoUrl,
  });
  if (effectiveInstallationId === null) return false;

  return resolveC4FlagEnabled(userId);
}
