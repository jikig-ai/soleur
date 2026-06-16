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

  // ADR-044 PR-1 owner-gate (confused-deputy): only the OWNER of the workspace
  // this handler mutates may disconnect it. `p_workspace_id` MUST equal the id
  // the handler actually mutates — in PR-1 the disconnect clears the solo
  // `users` row + the solo workspace mirror keyed on `user.id`, so
  // `p_workspace_id = user.id` and the gate is a NO-OP for solo users by
  // construction (a solo user always owns workspace_id=user.id). It becomes
  // load-bearing in PR-2 when connect-writes relocate to `workspaces.*` keyed on
  // the active (possibly team) id. `is_workspace_owner` is SECURITY DEFINER
  // (mig 098), GRANT authenticated — reuse the workspace/logo/route.ts shape.
  const ownerRes = await supabase.rpc("is_workspace_owner", {
    p_workspace_id: user.id,
    p_user_id: user.id,
  });
  if (ownerRes.error) {
    logger.error(
      { err: ownerRes.error, userId: user.id },
      "is_workspace_owner check failed during disconnect",
    );
    return NextResponse.json(
      { error: "Failed to disconnect repository" },
      { status: 500 },
    );
  }
  if (ownerRes.data !== true) {
    return NextResponse.json(
      { error: "Only the workspace owner can disconnect the repository." },
      { status: 403 },
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

  // ADR-044: mirror the moved repo cols to the solo workspace so the
  // workspaces-only read path reflects the disconnect. Fail CLOSED here
  // (unlike connect): the read path is workspaces-only, so a silently-failed
  // mirror would leave the credential (github_installation_id) + repo_url
  // live — the user appears connected and the agent could still act under the
  // revoked GitHub grant. Surface a 500 so the (idempotent) disconnect retries.
  const { mirrorRepoColsToSoloWorkspace } = await import(
    "@/server/workspace-repo-mirror"
  );
  try {
    await mirrorRepoColsToSoloWorkspace(
      serviceClient,
      user.id,
      {
        github_installation_id: null,
        repo_url: null,
        repo_status: "not_connected",
        repo_last_synced_at: null,
      },
      { throwOnError: true },
    );
  } catch (mirrorErr) {
    logger.error(
      { err: mirrorErr, userId: user.id },
      "Failed to mirror repo disconnect to workspaces (credential may persist on the read path)",
    );
    return NextResponse.json(
      { error: "Failed to disconnect repository" },
      { status: 500 },
    );
  }

  // Best-effort workspace cleanup — deleteWorkspace derives path from
  // getWorkspacesRoot() + the workspace identifier, handles non-existent
  // directories. For a solo user, `user.id` is the workspace_id (N2
  // invariant — migration 053 §1.1.7).
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
