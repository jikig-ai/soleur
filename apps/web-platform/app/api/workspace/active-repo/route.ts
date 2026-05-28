import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { normalizeRepoUrl } from "@/lib/repo-url";

/**
 * GET /api/workspace/active-repo
 *
 * Returns the repo connected to the user's ACTIVE workspace (ADR-044, #4543).
 * The source of truth is `workspaces` — NEVER `users.repo_url` (the
 * dual-ownership trap): a joined member's own users row is empty, so reading it
 * is the exact #4543 wrong-repo bug at the UI layer. Powers `live-repo-badge`.
 *
 * Self-heals J5 (access revocation): when `current_workspace_id` points at a
 * workspace the user is no longer a member of, the claim is reset to the
 * personal (solo) workspace and `fellBackToSolo` is reported so the badge can
 * render the revocation interstitial. The reset is a corrective write on the
 * caller's OWN session state (idempotent, never cross-tenant) — safe to run on
 * a read poll, and not a CSRF target (resetting a victim to their own solo
 * workspace confers no attacker benefit).
 */
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const userId = user.id;
  // ADR-038 N2: the solo workspace id equals the user id.
  const soloWorkspaceId = userId;
  const service = createServiceClient();

  // Active claim — read the source of truth (user_session_state), not the JWT
  // app_metadata (getUser returns raw_app_meta_data, which omits hook claims).
  const { data: sessionState } = await service
    .from("user_session_state")
    .select("current_workspace_id")
    .eq("user_id", userId)
    .maybeSingle();
  const claim = (sessionState?.current_workspace_id as string | null) ?? null;

  let activeWorkspaceId = claim ?? soloWorkspaceId;
  let fellBackToSolo = false;

  // J5: a non-solo claim that the user no longer has membership in → self-heal.
  if (activeWorkspaceId !== soloWorkspaceId) {
    const { data: membership } = await service
      .from("workspace_members")
      .select("user_id")
      .eq("workspace_id", activeWorkspaceId)
      .eq("user_id", userId)
      .maybeSingle();
    if (!membership) {
      // Reset to the personal workspace via the membership-checked RPC (the
      // user is always a member of their own solo workspace). Sets both
      // current_workspace_id and current_organization_id consistently.
      await supabase.rpc("set_current_workspace_id", {
        p_workspace_id: soloWorkspaceId,
      });
      activeWorkspaceId = soloWorkspaceId;
      fellBackToSolo = true;
    }
  }

  const { data: ws } = await service
    .from("workspaces")
    .select("repo_url, repo_status")
    .eq("id", activeWorkspaceId)
    .maybeSingle();

  const repoUrl = normalizeRepoUrl(ws?.repo_url ?? null) || null;
  let repoName: string | null = null;
  if (repoUrl) {
    const match = repoUrl.match(/github\.com\/([^/]+\/[^/]+?)(?:\.git)?\/?$/);
    repoName = match?.[1] ?? null;
  }

  return NextResponse.json({
    workspaceId: activeWorkspaceId,
    repoUrl,
    repoName,
    repoStatus: (ws?.repo_status as string | null) ?? "not_connected",
    fellBackToSolo,
  });
}
