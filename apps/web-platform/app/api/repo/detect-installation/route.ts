import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import {
  findInstallationForLogin,
  listInstallationRepos,
  verifyInstallationOwnership,
} from "@/server/github-app";
import logger from "@/server/logger";

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

  // If installation is already stored, just return repos
  const { data: userData } = await serviceClient
    .from("users")
    .select("github_installation_id")
    .eq("id", user.id)
    .single();

  if (userData?.github_installation_id) {
    try {
      const repos = await listInstallationRepos(
        userData.github_installation_id,
      );
      return NextResponse.json({ installed: true, repos });
    } catch (err) {
      logger.error(
        { err, userId: user.id },
        "Failed to list repos for stored installation",
      );
      return NextResponse.json({ installed: true, repos: [] });
    }
  }

  // Resolve GitHub login from identity
  let githubLogin: string | undefined;
  try {
    const { data: adminUser, error: adminError } =
      await serviceClient.auth.admin.getUserById(user.id);
    if (adminError) {
      logger.error(
        { err: adminError, userId: user.id },
        "auth.admin.getUserById failed during detection",
      );
    }
    const githubIdentity = adminUser?.user?.identities?.find(
      (i) => i.provider === "github",
    );
    githubLogin = githubIdentity?.identity_data?.user_name as
      | string
      | undefined;
  } catch (err) {
    logger.error(
      { err, userId: user.id },
      "Failed to resolve GitHub identity for detection",
    );
  }

  // Fallback: use stored github_username for email-only users
  if (!githubLogin) {
    const { data: usernameRow } = await serviceClient
      .from("users")
      .select("github_username")
      .eq("id", user.id)
      .single();
    githubLogin = usernameRow?.github_username ?? undefined;
  }

  if (!githubLogin) {
    return NextResponse.json({
      installed: false,
      reason: "no_github_identity",
    });
  }

  // Check if the app is installed on the user's GitHub account
  const installationId = await findInstallationForLogin(githubLogin);
  if (!installationId) {
    return NextResponse.json({
      installed: false,
      reason: "not_installed",
    });
  }

  // Verify ownership before storing
  const verification = await verifyInstallationOwnership(
    installationId,
    githubLogin,
  );
  if (!verification.verified) {
    logger.warn(
      { userId: user.id, installationId, error: verification.error },
      "Detected installation failed ownership verification",
    );
    return NextResponse.json({
      installed: false,
      reason: "ownership_verification_failed",
    });
  }

  // Store the installation ID
  const { error: updateError } = await serviceClient
    .from("users")
    .update({ github_installation_id: installationId })
    .eq("id", user.id);

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id },
      "Failed to store detected installation ID",
    );
    return NextResponse.json(
      { error: "Failed to store installation" },
      { status: 500 },
    );
  }

  logger.info(
    { userId: user.id, installationId, githubLogin },
    "Auto-detected and registered GitHub App installation",
  );

  // Fetch and return repos
  try {
    const repos = await listInstallationRepos(installationId);
    return NextResponse.json({ installed: true, repos });
  } catch (err) {
    logger.error(
      { err, userId: user.id },
      "Failed to list repos after auto-detection",
    );
    return NextResponse.json({ installed: true, repos: [] });
  }
}
