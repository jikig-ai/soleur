import { NextResponse } from "next/server";
import path from "path";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { buildTree } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { repoNeedsReconnect } from "@/lib/repo-status";

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

  // #4712 — deterministic reconnect signal. `ready` + NULL install id is the
  // #4706 silent-freeze class (webhook reconcile selects by install id).
  const needsReconnect = repoNeedsReconnect(
    userData.repo_status,
    userData.github_installation_id,
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
