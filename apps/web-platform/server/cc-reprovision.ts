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
import {
  isReadyGitWorkTree,
  evaluateAgentReadiness,
} from "./git-worktree-validity";

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
        op: "reprovision-on-dispatch-path-unresolved",
        extra: {
          userId,
          activeWorkspaceId,
          reason: "workspace-path-unresolved",
        },
      });
      return "ok";
    }
    // `.git` READY work tree → the safe symptom (missing/corrupt repo) is absent:
    // skip the install/repo resolution AND the clone. Safety invariant: a READY
    // `.git` is NEVER re-cloned/overwritten (never destroy Start-Fresh work /
    // un-pushed commits — learning 2026-06-03-self-heal-on-brand-path-only-acts-
    // on-safe-symptom.md). READINESS-not-presence (ADR-044 2026-06-19 +
    // 2026-06-30 amendments): a CORRUPT `.git` (partial clone / bare `mkdir .git`)
    // OR a STRANDING gitdir-pointer FILE (#5733 — passes lstat-validity but its
    // gitdir target escapes the sandbox, so the agent's in-bwrap `git rev-parse`
    // fails) is NOT a usable work tree, so it must NOT short-circuit "ok" — it
    // falls through to `ensureWorkspaceRepoCloned`, which does the validity check
    // + empty-corrupt removal / stale-pointer unlink + re-clone. This is the WARM
    // turn's only heal gate (the cold `realSdkQueryFactory` does not run on a warm
    // turn), so it MUST use the same `isReadyGitWorkTree` predicate as the cold
    // dispatch + reconcile gates or a mid-session pointer strands unhealed. The
    // path the probe used is exactly the path `ensureWorkspaceRepoCloned` clones
    // into — probe == clone by construction.
    //
    // Observability: a present-but-INVALID `.git` (corrupt / partial clone) falls
    // through to `ensureWorkspaceRepoCloned`, whose corrupt-recovery surfaces in
    // Sentry under `feature=ensure-workspace-repo op=corrupt-worktree-block`
    // (populated-but-broken `.git` honest-blocked, never rm'd) or `op=clone` (a
    // genuine re-clone failure). These are DISTINCT from the cold dispatch path's
    // `feature=repo-resolver-divergence op=corrupt-worktree-at-dispatch` breadcrumb
    // — a warm-path corruption is NOT visible under the cold divergence op.
    // #5733 (review P3) — resolve the connected repoUrl ONCE (tenant mint + SELECT)
    // and reuse it in BOTH branches below: the lstat-ready `dir-valid` host-confirm
    // scoping AND the not-ready re-clone. The previous code resolved it once per
    // branch — a divergent second read the cold gate already avoids.
    const repoUrl = await getCurrentRepoUrl(userId, activeWorkspaceId);
    if (isReadyGitWorkTree(workspacePath)) {
      // #5733 deliverable A — a lstat-READY `dir-valid` `.git` can STILL fail the
      // agent's in-bwrap `git rev-parse` (broken config/refs/gitdir indirection),
      // and the WARM path is the only heal gate on a warm turn. Before short-
      // circuiting "ok" (→ caller spawns), run the SAME shared `evaluateAgent-
      // Readiness` host confirm the cold + reconcile gates use (structural cross-
      // gate consistency, NOT per-gate re-spec — the cold-only-emit drift was the
      // 26×-dark incident). A confirmed `"not-a-worktree"` emits the self-stop
      // (inside the helper) and returns "failed" so the caller surfaces the honest
      // reclaim message instead of spawning into a strand; an inconclusive probe
      // FAILS-OPEN to "ok". NO memoization (a stale positive masks sub-lstat
      // corruption from a concurrent reconcile/pull, re-darkening this path). The
      // `repoUrl` read scopes the confirm to connected workspaces (a repo-less
      // Start-Fresh `git init` tree is a real work tree → "worktree" → "ok").
      const verdict = await evaluateAgentReadiness(workspacePath, {
        userId,
        activeWorkspaceId,
        connected: Boolean(repoUrl),
        dbReady: true, // a lstat-ready warm tree is not mid-clone
      });
      return verdict === "block" ? "failed" : "ok";
    }
    const storedInstallationId = await resolveInstallationId(
      userId,
      activeWorkspaceId,
    );
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
