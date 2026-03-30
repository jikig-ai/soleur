import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { listInstallationRepos } from "@/server/github-app";
import logger from "@/server/logger";

/**
 * GET /api/repo/repos
 *
 * Lists repositories accessible to the user's GitHub App installation.
 * Requires the user to have a stored github_installation_id.
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
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select("github_installation_id")
    .eq("id", user.id)
    .single();

  if (fetchError || !userData?.github_installation_id) {
    return NextResponse.json(
      { error: "GitHub App not installed. Please install the app first." },
      { status: 400 },
    );
  }

  try {
    const repos = await listInstallationRepos(userData.github_installation_id);
    return NextResponse.json({ repos });
  } catch (err) {
    logger.error(
      { err, userId: user.id },
      "Failed to list installation repos",
    );
    return NextResponse.json(
      { error: "Failed to list repositories" },
      { status: 500 },
    );
  }
}
