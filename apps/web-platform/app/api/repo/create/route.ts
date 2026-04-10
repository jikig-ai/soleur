import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { createRepo, GitHubApiError } from "@/server/github-app";
import logger from "@/server/logger";

/**
 * POST /api/repo/create
 *
 * Creates a new GitHub repository using the user's GitHub App installation.
 *
 * Body: { name: string, private: boolean }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/create", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.name || typeof body.name !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid name" },
      { status: 400 },
    );
  }

  // Server-side name validation (GitHub repo name rules)
  const name = body.name.trim();
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(name) || name.length > 100) {
    return NextResponse.json(
      { error: "Invalid repository name" },
      { status: 400 },
    );
  }

  const isPrivate = body.private !== false; // Default to private

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
    const result = await createRepo(
      userData.github_installation_id,
      name,
      isPrivate,
    );
    return NextResponse.json(result);
  } catch (err) {
    if (err instanceof GitHubApiError && (err.statusCode === 422 || err.statusCode === 403)) {
      const status = err.statusCode === 422 ? 409 : 403;
      logger.warn(
        { statusCode: err.statusCode, userId: user.id, repoName: name },
        "GitHub API rejected repo creation (user-correctable)",
      );
      return NextResponse.json({ error: err.message }, { status });
    }

    logger.error(
      { err, userId: user.id, repoName: name },
      "Failed to create repository",
    );
    Sentry.captureException(err);

    return NextResponse.json(
      { error: "Failed to create repository" },
      { status: 500 },
    );
  }
}
