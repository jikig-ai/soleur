import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { existsSync } from "fs";
import { join } from "path";

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
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select("repo_url, repo_status, repo_last_synced_at, workspace_path, repo_error, health_snapshot")
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

  // Additional details only available when workspace is ready
  let hasKnowledgeBase = false;
  if (status === "ready" && userData.workspace_path) {
    hasKnowledgeBase = existsSync(
      join(userData.workspace_path, "knowledge-base"),
    );
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

  return NextResponse.json({
    status,
    repoUrl,
    repoName,
    lastSyncedAt: userData.repo_last_synced_at ?? null,
    hasKnowledgeBase,
    healthSnapshot: userData.health_snapshot ?? null,
    syncConversationId,
    errorMessage: status === "error" ? (userData.repo_error ?? null) : null,
  });
}
