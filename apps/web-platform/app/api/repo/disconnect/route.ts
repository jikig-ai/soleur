import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { SlidingWindowCounter } from "@/server/rate-limiter";
import { deleteWorkspace } from "@/server/workspace";
import { resolveActiveWorkspace } from "@/server/workspace-resolver";
import { abortAllSessionsForWorkspace } from "@/server/agent-session-registry";
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

  // ADR-044 PR-2 team write-cutover (#5462): resolve the target workspace id
  // server-side via the MEMBERSHIP-VERIFIED resolver (IDOR-safe — session claim,
  // never request input). At this destructive boundary a db-error must FAIL-CLOSED
  // (503), never silently disconnect the caller's solo workspace under a team
  // claim. A removed/non-member of a stale team claim is reset to their OWN solo
  // id (`resetFromClaim`) — so a removed member disconnecting tears down their OWN
  // repo, never the team's.
  const activeResolution = await resolveActiveWorkspace(user.id, supabase);
  if (!activeResolution.ok) {
    return NextResponse.json(
      { error: "Could not resolve your active workspace. Please retry." },
      { status: 503 },
    );
  }
  const activeWorkspaceId = activeResolution.workspaceId;
  if (activeResolution.resetFromClaim) {
    logger.info(
      { userId: user.id, staleClaim: activeResolution.resetFromClaim },
      "repo disconnect: stale team claim reset to caller's solo workspace",
    );
  }

  // ADR-044 owner-gate (confused-deputy): only the OWNER of the workspace this
  // handler mutates may disconnect it. `p_workspace_id` MUST equal the id the
  // handler actually mutates — now the RESOLVED active id (team or solo). A
  // non-owner member disconnecting a team workspace gets 403; a solo user owns
  // workspace_id=user.id so it stays a no-op for solo. `is_workspace_owner` is
  // SECURITY DEFINER (mig 098), GRANT authenticated.
  const ownerRes = await supabase.rpc("is_workspace_owner", {
    p_workspace_id: activeWorkspaceId,
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
  // ADR-044 PR-2: read `repo_status` from the ACTIVE WORKSPACE (was the caller's
  // `users` row). For a team disconnect, the disconnecter's personal row is not
  // cloning even when the SHARED team clone is in flight — reading `users` would
  // let the teardown delete a workspace whose clone is mid-write.
  const { data: currentWorkspace, error: fetchError } = await serviceClient
    .from("workspaces")
    .select("repo_status")
    .eq("id", activeWorkspaceId)
    .single();

  if (fetchError) {
    logger.error(
      { err: fetchError, userId: user.id, workspaceId: activeWorkspaceId },
      "Failed to fetch workspace record for disconnect",
    );
    return NextResponse.json(
      { error: "Failed to disconnect repository" },
      { status: 500 },
    );
  }

  if (currentWorkspace?.repo_status === "cloning") {
    return NextResponse.json(
      { error: "Cannot disconnect while repository setup is in progress. Please wait for cloning to complete." },
      { status: 409 },
    );
  }

  // ADR-044 PR-2: clear the repo-connection columns AUTHORITATIVELY on the active
  // `workspaces` row (was the `users` row). Fail CLOSED: the read path is
  // workspaces-only, so a silently-failed clear (db error OR 0-row no-op) would
  // leave the credential (github_installation_id) + repo_url live — the user
  // appears connected and the agent could still act under the revoked GitHub
  // grant. The helper throws on either failure so we surface a 500 and the
  // (idempotent) disconnect is retried.
  const { writeRepoColsToWorkspace } = await import(
    "@/server/workspace-repo-mirror"
  );
  try {
    await writeRepoColsToWorkspace(
      serviceClient,
      activeWorkspaceId,
      {
        github_installation_id: null,
        repo_url: null,
        repo_status: "not_connected",
        repo_last_synced_at: null,
        repo_error: null,
      },
      { throwOnError: true },
    );
  } catch (clearErr) {
    logger.error(
      { err: clearErr, userId: user.id, workspaceId: activeWorkspaceId },
      "Failed to clear repo fields on the active workspace (credential may persist on the read path)",
    );
    return NextResponse.json(
      { error: "Failed to disconnect repository" },
      { status: 500 },
    );
  }

  // The provisioning/readiness columns (`workspace_status`, `health_snapshot`)
  // are NOT relocated by ADR-044 — reset them on the caller's `users` row only for
  // a SOLO disconnect. For a team disconnect, resetting the (owner) caller's
  // `users.workspace_status` would corrupt their PERSONAL solo readiness AND any
  // other team they own (the readiness gate reads the org owner's row).
  // `workspace_path` is intentionally NOT cleared — access is gated by
  // `workspace_status`, not an empty path, and writing it trips the
  // zero-`users.*`-write exit criterion.
  if (activeWorkspaceId === user.id) {
    const { error: readinessError } = await serviceClient
      .from("users")
      .update({ health_snapshot: null, workspace_status: "provisioning" })
      .eq("id", user.id);
    if (readinessError) {
      logger.error(
        { err: readinessError, userId: user.id },
        "Failed to reset solo readiness during disconnect (non-fatal — repo already cleared)",
      );
    }
  }

  // P0-6: a team workspace dir is SHARED across members. Abort EVERY live session
  // bound to this workspace (all members, not just the disconnecter) BEFORE the
  // `rm` so no agent is mid-write when the shared clone disappears (otherwise it
  // gets ENOENT mid-operation). Owner-only disconnect, so tearing down the shared
  // clone for everyone is intended. No-op when no session is bound (e.g. solo).
  try {
    abortAllSessionsForWorkspace(activeWorkspaceId);
  } catch (abortErr) {
    logger.warn(
      { err: abortErr, userId: user.id, workspaceId: activeWorkspaceId },
      "Failed to abort live member sessions before workspace teardown (best-effort)",
    );
  }

  // Best-effort workspace cleanup — deleteWorkspace derives the path from
  // getWorkspacesRoot() + the workspace identifier and handles non-existent
  // directories. Tears down `/workspaces/<activeWorkspaceId>` (team or solo).
  try {
    await deleteWorkspace(activeWorkspaceId);
  } catch (err) {
    logger.warn(
      { err, userId: user.id, workspaceId: activeWorkspaceId },
      "Workspace cleanup failed during disconnect (best-effort)",
    );
    Sentry.captureException(err);
  }

  return NextResponse.json({ ok: true });
}
