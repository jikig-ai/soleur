import { NextResponse } from "next/server";
import path from "path";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { buildTree } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { resolveNeedsReconnect } from "@/lib/repo-status";

async function getHandler(_req: Request, user: User) {
  const serviceClient = createServiceClient();
  const { data: userData, error: fetchError } = await serviceClient
    .from("users")
    .select(
      "workspace_path, workspace_status, repo_status, kb_sync_history, github_installation_id",
    )
    .eq("id", user.id)
    .single();

  if (fetchError || !userData?.workspace_path || userData.repo_status === "not_connected") {
    return NextResponse.json({ error: "Workspace not found" }, { status: 404 });
  }

  if (userData.workspace_status !== "ready") {
    return NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  // #4224 — surface the latest kb_sync_history row alongside the tree so
  // KbSyncStatus can render the staleness signal on layout mount without a
  // second round-trip. Heterogeneous JSONB: legacy `{date,count}` rows from
  // `recordKbSyncHistory` flow through unchanged; `KbSyncStatus` discriminates.
  const historyArr = Array.isArray(userData.kb_sync_history)
    ? (userData.kb_sync_history as unknown[])
    : [];
  const lastSync = historyArr.length > 0 ? historyArr[historyArr.length - 1] : null;

  // #4712 — capability-aware reconnect signal. `ready` + NULL user install id
  // is EITHER the #4706 silent-freeze class OR a workspace-shared install whose
  // credential lives on the workspace (ADR-044); resolveNeedsReconnect reads the
  // same signal the sync path uses so the banner clears once sync can resume.
  const needsReconnect = await resolveNeedsReconnect(
    userData.repo_status,
    userData.github_installation_id,
    user.id,
  );

  try {
    const kbRoot = path.join(userData.workspace_path, "knowledge-base");
    const tree = await buildTree(kbRoot);
    return NextResponse.json({ tree, lastSync, needsReconnect });
  } catch (err) {
    logger.error({ err }, "kb/tree: unexpected error");
    return NextResponse.json(
      { error: "An unexpected error occurred" },
      { status: 500 },
    );
  }
}

export const GET = withUserRateLimit(getHandler, {
  perMinute: 60,
  feature: "kb.tree",
});
