import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { listInstallationRepos, type Repo } from "@/server/github-app";
import { resolveReachableInstallationIds } from "@/server/reachable-installations";
import { resolveGithubLogin } from "@/server/github-login";
import logger from "@/server/logger";

/**
 * GET /api/repo/repos
 *
 * Lists repositories accessible across ALL of the user's reachable GitHub App
 * installations — their personal (login-matched) install PLUS any install
 * carried by a workspace they are a member of (ADR-044). This surfaces an
 * org-owned repo whose org login != the user's login. Keeps the 400 contract
 * when the reachable set is empty (the frontend branches on !res.ok).
 */
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();
  const { data: userData } = await serviceClient
    .from("users")
    .select("github_username")
    .eq("id", user.id)
    .single();

  const githubLogin = await resolveGithubLogin(
    serviceClient,
    user.id,
    userData?.github_username,
  );

  const reachable = await resolveReachableInstallationIds(
    serviceClient,
    user.id,
    githubLogin,
  );

  if (reachable.length === 0) {
    return NextResponse.json(
      { error: "GitHub App not installed. Please install the app first." },
      { status: 400 },
    );
  }

  // Aggregate repos across all reachable installs, de-duped on fullName.
  // A per-install failure is logged and skipped (do not fail the whole list).
  const seen = new Set<string>();
  const repos: Repo[] = [];
  for (const installationId of reachable) {
    try {
      const installRepos = await listInstallationRepos(installationId);
      for (const r of installRepos) {
        if (!seen.has(r.fullName)) {
          seen.add(r.fullName);
          repos.push(r);
        }
      }
    } catch (err) {
      logger.error(
        { err, userId: user.id, installationId },
        "Failed to list repos for a reachable installation — skipping",
      );
    }
  }

  return NextResponse.json({ repos });
}
