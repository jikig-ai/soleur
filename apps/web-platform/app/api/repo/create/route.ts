import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { createRepo, GitHubApiError } from "@/server/github-app";
import { resolveInstallationId } from "@/server/resolve-installation-id";
import { reportSilentFallback } from "@/server/observability";
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

  // ADR-044 PR-2: resolve the install for the caller's ACTIVE workspace via the
  // membership-checked RPC (was a direct `users.github_installation_id` read,
  // which goes NULL for a newly-connected user once the write relocated to
  // `workspaces`). Returns null for "no install" OR a transient read error
  // (Sentry-mirrored inside the resolver) — both map to the existing 400.
  const installationId = await resolveInstallationId(user.id);

  if (!installationId) {
    return NextResponse.json(
      { error: "GitHub App not installed. Please install the app first." },
      { status: 400 },
    );
  }

  try {
    const result = await createRepo(
      installationId,
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
      // 403 here is unexpected post-fix (the original /user/repos 403 is gone);
      // it now means an installation lost administration:write or the App was
      // partially uninstalled. Mirror to Sentry so ops triages — pino warn goes
      // to stdout only. 422 stays warn-only (legitimate user-side name conflict).
      if (err.statusCode === 403) {
        reportSilentFallback(err, {
          feature: "repo-create",
          op: "createRepo",
          extra: { statusCode: 403, userId: user.id, repoName: name },
        });
      }
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
