import { existsSync } from "node:fs";
import { join } from "node:path";
import { fetchUserWorkspacePath } from "./kb-document-resolver";
import { resolveInstallationId } from "./resolve-installation-id";
import { getCurrentRepoUrl } from "./current-repo-url";
import { resolveEffectiveInstallationId } from "./cc-effective-installation";
import {
  ensureWorkspaceRepoCloned,
  type ReprovisionOutcome,
} from "./ensure-workspace-repo";
import { reportSilentFallback } from "./observability";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { resolveActiveWorkspace } from "./workspace-resolver";
import { reportRepoResolverDivergence } from "./repo-resolver-divergence";

/**
 * Per-dispatch workspace re-provision for the Concierge (cc-soleur-go) path
 * (#5340 / #5240 design item #2).
 *
 * WHY per-dispatch and not just the factory-internal self-heal: the
 * `ensureWorkspaceRepoCloned` call in `cc-dispatcher.ts realSdkQueryFactory`
 * runs ONLY on a COLD conversation — warm-query reconnect (the epic's headline
 * scenario) does NOT re-invoke the factory, so the cold-path self-heal never
 * fires on a warm resume. This runs every dispatch (mirroring the fire-and-
 * forget `resolveBashAutonomous` warm-query resolve in `dispatchSoleurGo`) and
 * publishes the `ReprovisionOutcome` the post-recovery-failure honest message
 * branch reads on BOTH cold and warm turns.
 *
 * Idempotent + safe to race the cold-path factory call: `ensureWorkspaceRepoCloned`
 * is `.git`-absent-gated and the graft re-checks the `.git` sentinel before its
 * move, so a double-invocation no-ops on the second.
 *
 * Fail-soft: a transient resolver failure (workspace path / installation / repo
 * URL) is NOT a clone failure — it returns `"ok"` (the generic-message route)
 * and mirrors to Sentry, so it never surfaces a FALSE "workspace reclaimed"
 * honest message. A genuine clone failure returns `"failed"` (the honest-message
 * signal). Inputs are server-resolved + membership-scoped (ADR-044), never
 * request input.
 *
 * ADR-044 PR-3 (member-stranding closure): the active workspace is resolved ONCE
 * via the membership-verified `resolveActiveWorkspace` and the single id is
 * threaded into all three consumers — mirroring the cold factory's
 * resolve-once-and-thread (`cc-dispatcher.ts realSdkQueryFactory:1536`). Before
 * this, the path consumer (membership-verified) diverged from install/repo
 * (raw-claim), so a non-member/stale-claim member grafted the TEAM repo into the
 * SOLO `/workspaces/<userId>` (no `.git`) and the routine-authoring agent
 * stranded on a missing work tree. The ONE deliberate divergence from the
 * factory: on a transient membership-probe `db-error` this fire-and-forget
 * recovery SKIPS (returns `"ok"`) rather than throwing `WorkspaceNotReadyError`
 * (the factory is the dispatch readiness boundary; this is not).
 */
export async function reprovisionWorkspaceOnDispatch(
  userId: string,
): Promise<ReprovisionOutcome> {
  try {
    // Resolve the active workspace ONCE (membership-verified). One tenant client,
    // one resolve, before the otherwise-parallel consumer block.
    const tenant = await getFreshTenantClient(userId);
    const resolved = await resolveActiveWorkspace(userId, tenant);
    // Fail-closed on a transient membership-probe db-error: SKIP the reprovision
    // (never clone into an unverified location, never throw). The db-error is
    // already mirrored inside `resolveActiveWorkspace`; returning `"ok"` preserves
    // the existing fail-soft contract (no false reclaim message).
    if (!resolved.ok) return "ok";
    const activeWorkspaceId = resolved.workspaceId;
    // Divergence breadcrumb on the non-member/stale-claim reset (formerly
    // zero-Sentry on the reprovision path). Deduped by (op, userId, claim) so a
    // removed member does not storm Sentry on every dispatch.
    if (resolved.resetFromClaim) {
      reportRepoResolverDivergence({
        userId,
        op: "reprovision-non-member-claim-reset",
        activeClaimWorkspaceId: resolved.resetFromClaim,
        resolvedWorkspaceId: activeWorkspaceId,
      });
    }
    // #5715 — resolve the workspace path FIRST (membership-verified id), then
    // stat `.git` on EXACTLY that path before the heavier install/repo resolves
    // + the 120s clone. ONE resolve feeds both the stat and the clone target
    // (LEADER precedent `agent-runner.ts:1148`) — no second divergent resolve,
    // so the warm-dispatch gate can AWAIT this on every warm turn and a
    // `.git`-present turn short-circuits the slow path (instead of the old
    // fire-and-forget that let the agent run before the clone finished).
    const workspacePath = await fetchUserWorkspacePath(userId, activeWorkspaceId);
    // Forced-slow-path observability (AC11): a resolver outage that yields no
    // path cannot stat `.git`, so we fail soft to the generic route — but make
    // it queryable in Sentry rather than a silent slow-path forcing.
    if (!workspacePath) {
      reportSilentFallback(new Error("workspace_path_unresolved"), {
        feature: "cc-dispatcher",
        op: "reprovision-on-dispatch-await",
        extra: {
          userId,
          activeWorkspaceId,
          reason: "workspace-path-unresolved",
        },
      });
      return "ok";
    }
    // `.git` PRESENT → the safe symptom (missing repo) is absent: skip the
    // install/repo resolution AND the clone. Safety invariant: a present `.git`
    // is NEVER re-cloned/overwritten (never destroy Start-Fresh work / un-pushed
    // commits — learning 2026-06-03-self-heal-on-brand-path-only-acts-on-safe-
    // symptom.md). The path the stat used is exactly the path
    // `ensureWorkspaceRepoCloned` would clone into — probe == clone by construction.
    if (existsSync(join(workspacePath, ".git"))) {
      return "ok";
    }
    const [storedInstallationId, repoUrl] = await Promise.all([
      resolveInstallationId(userId, activeWorkspaceId),
      getCurrentRepoUrl(userId, activeWorkspaceId),
    ]);
    // Promote to the entitled repo-owner install (same selection the cold
    // factory makes) so a cross-account org repo re-clones with the right
    // credential instead of 403-ing and surfacing a false "couldn't restore".
    const installationId = await resolveEffectiveInstallationId({
      userId,
      installationId: storedInstallationId,
      repoUrl,
    });
    return await ensureWorkspaceRepoCloned({
      userId,
      workspacePath,
      installationId,
      repoUrl,
    });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cc-dispatcher",
      op: "reprovision-on-dispatch",
      extra: { userId },
      message:
        "per-dispatch workspace re-provision resolve failed; falling back to the generic worktree-enter message (no false reclaim message)",
    });
    return "ok";
  }
}
