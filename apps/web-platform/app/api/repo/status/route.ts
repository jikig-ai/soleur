import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { existsSync } from "fs";
import { join } from "path";
import { parseErrorPayload } from "@/server/git-auth";
import {
  resolveActiveWorkspacePath,
  resolveCurrentWorkspaceId,
} from "@/server/workspace-resolver";

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

  // ADR-044 PR-2 (#5462): the repo-connection columns are AUTHORITATIVE on the
  // ACTIVE `workspaces` row (not the caller's own `users` row, which goes
  // stale for newly-connected users once the write relocated, and is wrong for a
  // member viewing a shared/team workspace). Resolve the active workspace
  // (claim → solo fallback, never a sibling) and read the repo cols there.
  // `health_snapshot` is NOT relocated by ADR-044 — it stays on `users`.
  const activeWorkspaceId = await resolveCurrentWorkspaceId(user.id, serviceClient);
  const [wsRes, userRes] = await Promise.all([
    serviceClient
      .from("workspaces")
      .select("repo_url, repo_status, repo_last_synced_at, repo_error")
      .eq("id", activeWorkspaceId)
      .maybeSingle(),
    serviceClient
      .from("users")
      .select("health_snapshot")
      .eq("id", user.id)
      .maybeSingle(),
  ]);

  if (wsRes.error) {
    return NextResponse.json(
      { error: "Failed to read repository status" },
      { status: 500 },
    );
  }

  const workspaceData = wsRes.data;
  const status = workspaceData?.repo_status ?? "not_connected";
  const repoUrl = workspaceData?.repo_url ?? null;

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
    status === "error" ? (workspaceData?.repo_error ?? null) : null,
  );

  return NextResponse.json({
    status,
    repoUrl,
    repoName,
    lastSyncedAt: workspaceData?.repo_last_synced_at ?? null,
    hasKnowledgeBase,
    healthSnapshot: userRes.data?.health_snapshot ?? null,
    syncConversationId,
    errorMessage,
    errorCode,
  });
}
