import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { SlidingWindowCounter } from "@/server/rate-limiter";
import { deleteWorkspace } from "@/server/workspace";
import logger from "@/server/logger";

const disconnectLimiter = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: 1,
});

/**
 * DELETE /api/repo/disconnect
 *
 * Clears all repo-related fields on the user record and deletes the
 * workspace directory on disk. Workspace cleanup is best-effort —
 * the user is disconnected even if disk cleanup fails.
 */
export async function DELETE(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/disconnect", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  if (!disconnectLimiter.isAllowed(user.id)) {
    return NextResponse.json(
      { error: "Too many requests. Please wait before trying again." },
      { status: 429 },
    );
  }

  const serviceClient = createServiceClient();

  // Reject disconnect while clone is in progress — the background
  // provisionWorkspaceWithRepo would overwrite cleared fields on completion.
  const { data: currentUser, error: fetchError } = await serviceClient
    .from("users")
    .select("repo_status")
    .eq("id", user.id)
    .single();

  if (fetchError) {
    logger.error(
      { err: fetchError, userId: user.id },
      "Failed to fetch user record for disconnect",
    );
    return NextResponse.json(
      { error: "Failed to disconnect repository" },
      { status: 500 },
    );
  }

  if (currentUser?.repo_status === "cloning") {
    return NextResponse.json(
      { error: "Cannot disconnect while repository setup is in progress. Please wait for cloning to complete." },
      { status: 409 },
    );
  }

  // Clear all repo-related fields (DB update before disk cleanup)
  const { error: updateError } = await serviceClient
    .from("users")
    .update({
      github_installation_id: null,
      repo_url: null,
      repo_status: "not_connected",
      repo_last_synced_at: null,
      repo_error: null,
      health_snapshot: null,
      workspace_path: "",
      workspace_status: "provisioning",
    })
    .eq("id", user.id);

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id },
      "Failed to clear repo fields during disconnect",
    );
    return NextResponse.json(
      { error: "Failed to disconnect repository" },
      { status: 500 },
    );
  }

  // Best-effort workspace cleanup — deleteWorkspace derives path from
  // getWorkspacesRoot() + userId, handles non-existent directories.
  try {
    await deleteWorkspace(user.id);
  } catch (err) {
    logger.warn(
      { err, userId: user.id },
      "Workspace cleanup failed during disconnect (best-effort)",
    );
    Sentry.captureException(err);
  }

  return NextResponse.json({ ok: true });
}
