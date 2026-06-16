import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { existsSync } from "fs";
import { join } from "path";
import { parseErrorPayload } from "@/server/git-auth";
import { resolveActiveWorkspacePath } from "@/server/workspace-resolver";

/**
 * GET /api/repo/status
 *
 * Returns the user's repository connection status.
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
  // #5005 — `workspace_path` is no longer read here; the `hasKnowledgeBase`
  // existence check below resolves the ACTIVE workspace path via the
  // membership-scoped resolver (the own-row column is stale/empty post-ADR-044).
  // The `repo_url`/`repo_status`/`repo_last_synced_at` reads are the ADR-044
  // relocated REPO columns — out of scope for #5005 (covered by ADR-044's own
  // pre-decommission drift gate); left untouched here.
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select("repo_url, repo_status, repo_last_synced_at, repo_error, health_snapshot")
    .eq("id", user.id)
    .single();

  if (fetchError || !userData) {
    return NextResponse.json(
      { error: "User not found" },
      { status: 404 },
    );
  }

  const status = userData.repo_status ?? "not_connected";
  const repoUrl = userData.repo_url ?? null;

  // Extract repo name from URL (e.g., "owner/repo" from "https://github.com/owner/repo")
  let repoName: string | null = null;
  if (repoUrl) {
    const match = repoUrl.match(/github\.com\/([^/]+\/[^/]+?)\/?$/);
    repoName = match?.[1] ?? null;
  }

  // Additional details only available when workspace is ready. Resolve the
  // active workspace path (#5005) rather than the stale own-row column.
  let hasKnowledgeBase = false;
  if (status === "ready") {
    const workspacePath = await resolveActiveWorkspacePath(
      user.id,
      serviceClient,
    );
    hasKnowledgeBase = existsSync(join(workspacePath, "knowledge-base"));
  }

  // Check for an active system sync conversation (#1816)
  let syncConversationId: string | null = null;
  if (status === "ready") {
    const { data: syncConv } = await serviceClient
      .from("conversations")
      .select("id")
      .eq("user_id", user.id)
      .eq("domain_leader", "system")
      .eq("status", "active")
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    syncConversationId = syncConv?.id ?? null;
  }

  // `repo_error` is TEXT. New writes are a JSON string of
  // `{ code, message, timestamp }` (see /api/repo/setup). Legacy rows
  // (pre-errorCode migration) contain plain stderr — parseErrorPayload
  // returns a `{errorMessage, errorCode: undefined}` shape so the UI
  // falls back to its legacy generic copy for those rows.
  const { errorMessage, errorCode } = parseErrorPayload(
    status === "error" ? userData.repo_error : null,
  );

  return NextResponse.json({
    status,
    repoUrl,
    repoName,
    lastSyncedAt: userData.repo_last_synced_at ?? null,
    hasKnowledgeBase,
    healthSnapshot: userData.health_snapshot ?? null,
    syncConversationId,
    errorMessage,
    errorCode,
  });
}
