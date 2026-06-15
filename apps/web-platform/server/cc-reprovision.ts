import { fetchUserWorkspacePath } from "./kb-document-resolver";
import { resolveInstallationId } from "./resolve-installation-id";
import { getCurrentRepoUrl } from "./current-repo-url";
import { resolveEffectiveInstallationId } from "./cc-effective-installation";
import {
  ensureWorkspaceRepoCloned,
  type ReprovisionOutcome,
} from "./ensure-workspace-repo";
import { reportSilentFallback } from "./observability";

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
 */
export async function reprovisionWorkspaceOnDispatch(
  userId: string,
): Promise<ReprovisionOutcome> {
  try {
    const [workspacePath, storedInstallationId, repoUrl] = await Promise.all([
      fetchUserWorkspacePath(userId),
      resolveInstallationId(userId),
      getCurrentRepoUrl(userId),
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
