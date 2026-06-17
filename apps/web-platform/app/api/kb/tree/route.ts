import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";
import { buildTree } from "@/server/kb-reader";
import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { resolveNeedsReconnect } from "@/lib/repo-status";
import { resolveActiveWorkspaceKbRoot } from "@/server/workspace-resolver";
import { resolveInstallationId } from "@/server/resolve-installation-id";

async function getHandler(_req: Request, user: User) {
  const serviceClient = createServiceClient();

  // ADR-044 (#4543): the KB lives on the ACTIVE workspace, not the caller's own
  // `users` row. Reading `users` for an invited member resolves their empty solo
  // row → 404 → "No Project Connected". resolveActiveWorkspaceKbRoot mirrors the
  // active-repo route (claim → solo fallback, never a sibling) and gates on the
  // active workspace's repo_status + the owner's readiness.
  const access = await resolveActiveWorkspaceKbRoot(user.id, serviceClient);
  if (!access.ok) {
    return access.status === 404
      ? NextResponse.json({ error: "Workspace not found" }, { status: 404 })
      : NextResponse.json({ error: "Workspace not ready" }, { status: 503 });
  }

  // #4224/#4712 — lastSync + needsReconnect are SYNC-state signals owned by the
  // workspace owner. For a member viewing a shared workspace, the sync-status
  // surface (staleness banner, reconnect prompt) is a credential-bound owner
  // action deferred to the member-KB-write follow-up (Q2); a member sees the
  // tree with no sync banner. For the SOLO caller (active workspace == own), the
  // signals are read from their own row exactly as before — no regression.
  let lastSync: unknown = null;
  let needsReconnect = false;
  if (access.activeWorkspaceId === user.id) {
    // Intentionally caller-id-scoped: solo own-row sync metadata only (AC2).
    // `kb_sync_history` stays on `users` (not relocated by ADR-044). The install
    // id moved to `workspaces` (PR-2), so it is read via the membership-checked
    // RPC keyed on the active workspace — a direct `users.github_installation_id`
    // read would go NULL for a newly-connected user.
    const { data: ownRow } = await serviceClient
      .from("users")
      .select("kb_sync_history")
      .eq("id", user.id)
      .single();
    const historyArr = Array.isArray(ownRow?.kb_sync_history)
      ? (ownRow.kb_sync_history as unknown[])
      : [];
    lastSync = historyArr.length > 0 ? historyArr[historyArr.length - 1] : null;
    const installationId = await resolveInstallationId(
      user.id,
      access.activeWorkspaceId,
    );
    needsReconnect = await resolveNeedsReconnect(
      access.repoStatus,
      installationId,
      user.id,
    );
  }

  try {
    const tree = await buildTree(access.kbRoot);
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
