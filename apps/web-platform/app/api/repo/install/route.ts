import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { verifyInstallationOwnership } from "@/server/github-app";
import logger from "@/server/logger";

/**
 * POST /api/repo/install
 *
 * Stores the GitHub App installation ID on the user record after
 * the user completes the GitHub App installation flow.
 * Verifies the authenticated user owns the installation before storing.
 *
 * Body: { installationId: number }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/install", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (
    !body?.installationId ||
    typeof body.installationId !== "number" ||
    !Number.isInteger(body.installationId) ||
    body.installationId <= 0
  ) {
    return NextResponse.json(
      { error: "Missing or invalid installationId" },
      { status: 400 },
    );
  }

  // SECURITY: Extract GitHub username from provider-controlled identity first.
  // user_metadata is user-mutable via auth.updateUser() — never trust it for
  // security decisions when an immutable source exists.
  const githubLogin =
    user.identities?.find(
      (i: { provider: string; identity_data?: { user_name?: string } }) =>
        i.provider === "github",
    )?.identity_data?.user_name ??
    user.user_metadata?.user_name;

  if (!githubLogin) {
    logger.warn(
      { userId: user.id },
      "User has no GitHub identity — cannot verify installation ownership",
    );
    return NextResponse.json(
      { error: "No GitHub identity found on this account" },
      { status: 403 },
    );
  }

  const verification = await verifyInstallationOwnership(
    body.installationId,
    githubLogin,
  );

  if (!verification.verified) {
    logger.warn(
      { userId: user.id, installationId: body.installationId, error: verification.error },
      "Installation ownership verification failed",
    );
    return NextResponse.json(
      { error: verification.error },
      { status: verification.status ?? 403 },
    );
  }

  const serviceClient = createServiceClient();
  const { error: updateError } = await serviceClient
    .from("users")
    .update({ github_installation_id: body.installationId })
    .eq("id", user.id);

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id },
      "Failed to store installation ID",
    );
    return NextResponse.json(
      { error: "Failed to store installation ID" },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true });
}
