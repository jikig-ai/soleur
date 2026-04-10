import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { provisionWorkspaceWithRepo } from "@/server/workspace";
import { scanProjectHealth } from "@/server/project-scanner";
import logger from "@/server/logger";

/**
 * POST /api/repo/setup
 *
 * Starts cloning a repository into the user's workspace.
 * The clone runs in the background — poll GET /api/repo/status for progress.
 *
 * Body: { repoUrl: string }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/setup", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.repoUrl || typeof body.repoUrl !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid repoUrl" },
      { status: 400 },
    );
  }

  // Validate URL format (must be HTTPS GitHub URL with valid owner/repo)
  const repoUrl = body.repoUrl.trim().replace(/\/+$/, "");
  if (!/^https:\/\/github\.com\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+$/.test(repoUrl)) {
    return NextResponse.json(
      { error: "Invalid GitHub repository URL" },
      { status: 400 },
    );
  }

  const serviceClient = createServiceClient();

  // Get user's installation ID
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select("github_installation_id, email")
    .eq("id", user.id)
    .single();

  if (fetchError || !userData?.github_installation_id) {
    return NextResponse.json(
      { error: "GitHub App not installed. Please install the app first." },
      { status: 400 },
    );
  }

  // Optimistic lock: only transition to "cloning" if not already cloning.
  // Prevents race condition from double-click or concurrent requests.
  const { data: lockResult, error: updateError } = await serviceClient
    .from("users")
    .update({ repo_url: repoUrl, repo_status: "cloning", repo_error: null })
    .eq("id", user.id)
    .neq("repo_status", "cloning")
    .select("id")
    .maybeSingle();

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id },
      "Failed to update repo status to cloning",
    );
    return NextResponse.json(
      { error: "Failed to start setup" },
      { status: 500 },
    );
  }

  if (!lockResult) {
    return NextResponse.json(
      { error: "Setup already in progress" },
      { status: 409 },
    );
  }

  // Kick off clone in the background (don't await)
  const userName = user.user_metadata?.full_name ?? user.email?.split("@")[0] ?? "Soleur User";
  const userEmail = userData.email ?? user.email ?? "";

  provisionWorkspaceWithRepo(
    user.id,
    repoUrl,
    userData.github_installation_id,
    userName,
    userEmail,
  )
    .then(async (workspacePath) => {
      // Fast scan — failure must not block provisioning
      let healthSnapshot = null;
      try {
        healthSnapshot = scanProjectHealth(workspacePath);
      } catch (scanErr) {
        logger.error(
          { err: scanErr, userId: user.id },
          "Project health scan failed — continuing without snapshot",
        );
        Sentry.captureException(scanErr);
      }

      const { error } = await serviceClient
        .from("users")
        .update({
          workspace_path: workspacePath,
          workspace_status: "ready",
          repo_status: "ready",
          repo_last_synced_at: new Date().toISOString(),
          health_snapshot: healthSnapshot,
        })
        .eq("id", user.id);

      if (error) {
        logger.error(
          { err: error, userId: user.id },
          "Failed to update user after successful clone",
        );
        return;
      }

      logger.info(
        { userId: user.id, repoUrl, category: healthSnapshot?.category },
        "Repo setup completed",
      );

      // Auto-trigger headless sync — fire-and-forget with .catch()
      // BYOK check is handled internally by startAgentSession (rejects if no key)
      const conversationId = crypto.randomUUID();
      const { error: convError } = await serviceClient
        .from("conversations")
        .insert({
          id: conversationId,
          user_id: user.id,
          domain_leader: "system",
          status: "active",
          session_id: crypto.randomUUID(),
        });

      if (convError) {
        logger.error(
          { err: convError, userId: user.id },
          "Failed to create sync conversation",
        );
        Sentry.captureException(convError);
        return;
      }

      // Dynamic import: agent-runner.ts pulls in @anthropic-ai/claude-agent-sdk
      // which breaks Next.js build-time route validation when statically imported.
      import("@/server/agent-runner").then(({ startAgentSession }) =>
        startAgentSession(
          user.id,
          conversationId,
          undefined,
          undefined,
          "/soleur:sync --headless",
        ),
      ).catch((syncErr) => {
        logger.error(
          { err: syncErr, userId: user.id },
          "Auto-triggered sync failed",
        );
        Sentry.captureException(syncErr);
      });
    })
    .catch(async (err) => {
      logger.error({ err, userId: user.id, repoUrl }, "Repo clone failed");
      Sentry.captureException(err);

      const rawMessage = err instanceof Error ? err.message : String(err);
      const errorMessage = rawMessage.slice(0, 2000);
      await serviceClient
        .from("users")
        .update({ repo_status: "error", repo_error: errorMessage })
        .eq("id", user.id)
        .then(({ error }) => {
          if (error) {
            logger.error(
              { err: error, userId: user.id },
              "Failed to update repo status to error",
            );
          }
        });
    });

  return NextResponse.json({ status: "cloning" });
}
