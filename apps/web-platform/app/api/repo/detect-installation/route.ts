import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import {
  findInstallationForLogin,
  listInstallationRepos,
  verifyInstallationOwnership,
  type Repo,
} from "@/server/github-app";
import { resolveReachableInstallationIds } from "@/server/reachable-installations";
import { resolveGithubLogin } from "@/server/github-login";
import { resolveInstallationIdForWorkspace } from "@/server/resolve-installation-id-for-workspace";
import logger from "@/server/logger";

/**
 * Aggregate repos across a set of installs, de-duped on fullName. A per-install
 * failure is logged and skipped (a stale/revoked sibling install must not fail
 * the whole list).
 */
async function aggregateReposForInstalls(
  installationIds: number[],
  userId: string,
): Promise<Repo[]> {
  const seen = new Set<string>();
  const repos: Repo[] = [];
  for (const id of installationIds) {
    try {
      const installRepos = await listInstallationRepos(id);
      for (const r of installRepos) {
        if (!seen.has(r.fullName)) {
          seen.add(r.fullName);
          repos.push(r);
        }
      }
    } catch (err) {
      logger.error(
        { err, userId, installationId: id },
        "Failed to list repos for a reachable installation — skipping",
      );
    }
  }
  return repos;
}

/**
 * POST /api/repo/detect-installation
 *
 * Auto-detects whether the Soleur GitHub App is already installed for the
 * authenticated user's GitHub account, even when `github_installation_id`
 * is not stored in our database.
 *
 * This breaks the redirect loop where:
 * 1. User has the app installed on GitHub
 * 2. But `github_installation_id` is NULL (callback never fired)
 * 3. /api/repo/repos returns 400 → user gets sent to GitHub → app already
 *    installed → GitHub may not redirect back → loop
 *
 * If an installation is found, it is verified, stored, and repos are returned.
 *
 * Returns:
 * - { installed: true, repos: [...] } — installation found and registered
 * - { installed: false, reason: string } — no installation detected
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/detect-installation", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();

  // ADR-044 Amendment 2026-06-17b: the install is read from the caller's solo
  // `workspaces` row (NOT `users.github_installation_id`, ahead of PR-2b's
  // column drop) via the service-role-safe resolver — the solo workspace
  // carries the install (workspaces.id == users.id, ADR-038 N2), same value.
  // `github_username` is NOT relocated by ADR-044, so it stays a `users` read.
  const storedInstallationId = await resolveInstallationIdForWorkspace(
    user.id,
    serviceClient,
  );

  const { data: userData } = await serviceClient
    .from("users")
    .select("github_username")
    .eq("id", user.id)
    .single();

  // Resolve GitHub login from identity (shared helper, github_username fallback)
  const githubLogin = await resolveGithubLogin(
    serviceClient,
    user.id,
    userData?.github_username,
  );

  if (storedInstallationId) {
    // A stored personal install does not preclude a separate workspace org
    // install — aggregate repos across the full reachable set so org-owned
    // repos appear here too.
    const reachable = await resolveReachableInstallationIds(
      serviceClient,
      user.id,
      githubLogin,
    );
    const repos = await aggregateReposForInstalls(reachable, user.id);
    return NextResponse.json({ installed: true, repos });
  }

  if (!githubLogin) {
    return NextResponse.json({
      installed: false,
      reason: "no_github_identity",
    });
  }

  // Check for a login-matched PERSONAL install (own account or GitHub-reported
  // org member). This is the only install we persist on `users` (the unique
  // constraint forbids storing a membership-only install — ADR-044).
  const personalInstallationId = await findInstallationForLogin(githubLogin);

  if (personalInstallationId) {
    // Verify ownership before storing.
    const verification = await verifyInstallationOwnership(
      personalInstallationId,
      githubLogin,
    );
    if (!verification.verified) {
      logger.warn(
        {
          userId: user.id,
          installationId: personalInstallationId,
          error: verification.error,
        },
        "Detected installation failed ownership verification",
      );
      return NextResponse.json({
        installed: false,
        reason: "ownership_verification_failed",
      });
    }

    // ADR-044 PR-2: this auto-detect persists the caller's OWN login-matched
    // personal install to their OWN SOLO workspace (`workspaces.id = user.id`) —
    // the authoritative target (was `users.github_installation_id` + a solo
    // mirror). A team workspace's install is bound separately via the owner-gated
    // install/setup routes, never auto-detected, so this stays solo-keyed and
    // needs no membership resolution.
    //
    // The former 23505 unique-violation tolerance branch is DELETED: it guarded
    // the partial-UNIQUE on `users.github_installation_id` (mig 052). `workspaces`
    // is intentionally NON-unique (ADR-044 fan-out, mig 079), so the violation can
    // never fire on a `workspaces` write — the cross-tenant attribution invariant
    // it served is now enforced by the webhook push-reconcile fan-out over
    // (installation_id, normalizeRepoUrl(repo_url)). Best-effort: a failed write is
    // Sentry-mirrored by the helper; the route still returns the repo list.
    const { writeRepoColsToWorkspace } = await import(
      "@/server/workspace-repo-mirror"
    );
    await writeRepoColsToWorkspace(serviceClient, user.id, {
      github_installation_id: personalInstallationId,
    });

    logger.info(
      { userId: user.id, installationId: personalInstallationId, githubLogin },
      "Auto-detected and registered GitHub App installation",
    );
  }

  // Aggregate repos across the full reachable set (personal + org-membership
  // installs), so an org-owned repo (org login != user login) appears on the
  // first call — no double-connect.
  const reachable = await resolveReachableInstallationIds(
    serviceClient,
    user.id,
    githubLogin,
  );

  // No personal install matched AND no membership-reachable install exists →
  // the app is not installed for this user (preserve the contract).
  if (reachable.length === 0) {
    return NextResponse.json({ installed: false, reason: "not_installed" });
  }

  const repos = await aggregateReposForInstalls(reachable, user.id);
  return NextResponse.json({ installed: true, repos });
}
