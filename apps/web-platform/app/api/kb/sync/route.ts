// #4224 — manual workspace reconcile endpoint.
//
// Operator-initiated `POST /api/kb/sync` triggered by the "Sync now"
// affordance in `KbSyncStatus`. Webhook-INDEPENDENT — calls `syncWorkspace`
// directly, never re-emits a webhook event (per spec-flow EC2.10).
//
// Sharp Edge (plan §Sharp Edges): the workspace_path is RESOLVED
// SERVER-SIDE from `session.user_id` and NEVER read from the request body.
// Even if the request body carries a `workspace_path` field, it's ignored.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getFreshTenantClient, RuntimeAuthError } from "@/lib/supabase/tenant";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { syncWorkspace } from "@/server/kb-route-helpers";
import { appendKbSyncRow } from "@/server/session-sync";
import { reportSilentFallback } from "@/server/observability";
import logger from "@/server/logger";

export async function POST(request: Request): Promise<Response> {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/kb/sync", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  try {
    return await handleSync(user.id);
  } catch (err) {
    logger.error(
      { err, userId: user.id },
      "kb/sync: unexpected error",
    );
    reportSilentFallback(err, {
      feature: "kb-route-helpers",
      op: "kb-sync.unexpected",
      extra: { userId: user.id },
      message: "kb/sync: unexpected error",
    });
    return NextResponse.json(
      { error: "Internal server error" },
      { status: 500 },
    );
  }
}

async function handleSync(userId: string): Promise<Response> {
  // Server-side workspace resolution. The request body is intentionally
  // NOT parsed — operator-controlled fields cannot reach the FS write path.
  let tenant;
  try {
    tenant = await getFreshTenantClient(userId);
  } catch (mintErr) {
    if (mintErr instanceof RuntimeAuthError) {
      reportSilentFallback(mintErr, {
        feature: "kb-route-helpers",
        op: "kb-sync.tenant-mint",
        extra: { userId },
        message: "kb/sync: tenant mint failed",
      });
      return NextResponse.json(
        { error: "Workspace not ready" },
        { status: 503 },
      );
    }
    throw mintErr;
  }

  const { data: userData, error: userErr } = await tenant
    .from("users")
    .select("workspace_path, workspace_status, github_installation_id")
    .eq("id", userId)
    .single();

  if (userErr || !userData) {
    return NextResponse.json(
      { error: "Workspace not found" },
      { status: 404 },
    );
  }

  if (userData.workspace_status !== "ready") {
    return NextResponse.json(
      {
        error: "Workspace not ready",
        code: "WORKSPACE_NOT_READY",
        workspace_status: userData.workspace_status,
      },
      { status: 409 },
    );
  }

  let installationId = userData.github_installation_id;
  if (!installationId) {
    const { resolveInstallationId } = await import(
      "@/server/resolve-installation-id"
    );
    installationId = await resolveInstallationId(userId);
  }

  if (!userData.workspace_path || !installationId) {
    return NextResponse.json(
      { error: "Workspace not connected" },
      { status: 409 },
    );
  }

  const syncResult = await syncWorkspace(
    installationId,
    userData.workspace_path,
    logger,
    { userId, op: "manual" },
  );

  // Anchor `at` to sync-completion (not sync-start) so manual and
  // webhook-push rows share consistent semantics. Otherwise `relativeLabel`
  // in `KbSyncStatus` shows "Synced just now" the instant the sync starts,
  // even if the sync takes 25s.
  const sync_completed_at = Date.now();
  const at = new Date(sync_completed_at).toISOString();
  if (!syncResult.ok) {
    // Real class from the git stderr/exit signature (`syncWorkspace` now
    // classifies non_fast_forward vs sync_failed and attempts a gated
    // self-heal first). No longer hard-coded — a diverged clone routes the
    // operator to the right desync state instead of a generic failure.
    await appendKbSyncRow(userId, {
      at,
      trigger: "manual",
      ok: false,
      error_class: syncResult.errorClass,
      sync_completed_at,
    });
    return NextResponse.json({
      ok: false,
      at,
      error_class: syncResult.errorClass,
    });
  }

  await appendKbSyncRow(userId, {
    at,
    trigger: "manual",
    ok: true,
    recovered: syncResult.recovered,
    sync_completed_at,
  });
  return NextResponse.json({
    ok: true,
    at,
    ...(syncResult.recovered ? { recovered: true } : {}),
  });
}
