import {
  findInstallationForLogin,
  checkRepoAccess,
} from "@/server/github-app";
import { reportSilentFallback } from "@/server/observability";

interface ServiceClientLike {
  from: (table: string) => unknown; // PostgREST chain
}

/**
 * Resolve the SET of GitHub App installation ids the user can legitimately
 * reach, for repo-listing/aggregation and owning-install resolution.
 *
 * Sources (unioned, de-duplicated):
 *   (a) Personal/login-matched install — findInstallationForLogin(githubLogin).
 *       Covers the user's own account install AND org installs where GitHub
 *       reports the user as an org member (existing behavior, kept).
 *   (b) Workspace-membership installs — every github_installation_id carried by
 *       a workspace the user is a workspace_members member of. This is the path
 *       that surfaces an ORG install when the org login != the user's login and
 *       the install lives on the user's WORKSPACE row (ADR-044).
 *
 * SECURITY: the membership read is service-role (trusted server context, same
 * as the existing users read in these routes). It is scoped by an explicit
 * `.eq("user_id", userId)` filter, so it only ever returns installs for
 * workspaces THIS user belongs to — never an arbitrary install. The login
 * source is GitHub-authoritative. The union therefore contains only
 * legitimately-reachable installs.
 *
 * Returns a deduped number[] (may be empty -> caller surfaces "not installed").
 */
export async function resolveReachableInstallationIds(
  service: ServiceClientLike,
  userId: string,
  githubLogin: string | null,
): Promise<number[]> {
  const ids = new Set<number>();

  // (a) login-matched install (personal account or GitHub-reported org member)
  if (githubLogin) {
    try {
      const loginInstall = await findInstallationForLogin(githubLogin);
      if (loginInstall) ids.add(loginInstall);
    } catch (err) {
      reportSilentFallback(err, {
        feature: "reachable-installations",
        op: "login-install",
        extra: { userId },
        message:
          "findInstallationForLogin failed during reachable-install resolution",
      });
    }
  }

  // (b) workspace-membership installs (service-role, user-scoped)
  type MembershipChain = {
    select: (cols: string) => {
      eq: (
        col: string,
        val: string,
      ) => Promise<{ data: unknown[] | null; error: unknown }>;
    };
  };
  try {
    const { data, error } = await (
      service.from("workspace_members") as MembershipChain
    )
      .select("workspaces!inner(github_installation_id)")
      .eq("user_id", userId);
    if (error) {
      reportSilentFallback(error, {
        feature: "reachable-installations",
        op: "membership-installs",
        extra: { userId },
        message: "workspace_members install enumeration failed",
      });
    } else {
      for (const row of data ?? []) {
        // PostgREST embed may be object or array depending on cardinality
        const ws = (row as { workspaces: unknown }).workspaces;
        const list = Array.isArray(ws) ? ws : ws ? [ws] : [];
        for (const w of list) {
          const id = (w as { github_installation_id: number | null })
            .github_installation_id;
          if (typeof id === "number" && id > 0) ids.add(id);
        }
      }
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "reachable-installations",
      op: "membership-installs",
      extra: { userId },
    });
  }

  return [...ids];
}

/**
 * Outcome of an owning-install probe sweep. `installId` is the first reachable
 * install whose `GET /repos/{owner}/{repo}` returned "ok", else null.
 *
 * `allDegraded` distinguishes the two ways `installId` can be null:
 *   - `false` — the sweep saw at least one CONCLUSIVE non-owning answer
 *     (404 not_found / 403/401 access_revoked). The owner genuinely cannot
 *     reach this repo via any reachable install → "needs re-auth".
 *   - `true`  — reachableIds was non-empty AND every probe returned "degraded"
 *     (5xx / network / token-gen). The sweep was INCONCLUSIVE (transient) →
 *     caller should no-op and retry, not surface a re-auth signal.
 * (An empty `reachableIds` returns `{ installId: null, allDegraded: false }`;
 * the caller handles "no reachable install" before probing.)
 */
export interface OwningInstallationResult {
  installId: number | null;
  allDegraded: boolean;
}

/**
 * From the user's reachable install set, resolve the install that owns
 * `owner/repo`, returning the discriminated {@link OwningInstallationResult} so
 * a transient all-degraded sweep is distinguishable from a conclusive absence.
 * Probes sequentially and short-circuits on the first "ok".
 */
export async function resolveOwningInstallationForRepoDetailed(
  reachableIds: number[],
  owner: string,
  repo: string,
): Promise<OwningInstallationResult> {
  let sawConclusive = false;
  for (const id of reachableIds) {
    const status = await checkRepoAccess(id, owner, repo);
    if (status === "ok") return { installId: id, allDegraded: false };
    // "degraded" (5xx/network/token-gen) is inconclusive — keep probing other
    // installs; only "ok" is an affirmative owning-install signal. A
    // not_found / access_revoked is a conclusive "this install can't own it".
    if (status !== "degraded") sawConclusive = true;
  }
  return {
    installId: null,
    allDegraded: reachableIds.length > 0 && !sawConclusive,
  };
}

/**
 * Back-compat thin wrapper: returns just the owning install id (or null),
 * collapsing the transient/conclusive distinction. Existing callers
 * (`repo/setup`) only need the id; the cron uses the *Detailed variant.
 * Returns null when no reachable install can see the repo — the caller then
 * surfaces "not installed" / "no access" WITHOUT falling back to an arbitrary
 * install.
 */
export async function resolveOwningInstallationForRepo(
  reachableIds: number[],
  owner: string,
  repo: string,
): Promise<number | null> {
  const { installId } = await resolveOwningInstallationForRepoDetailed(
    reachableIds,
    owner,
    repo,
  );
  return installId;
}
