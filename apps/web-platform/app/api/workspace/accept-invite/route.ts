import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { acceptWorkspaceInvitation } from "@/server/workspace-invitations";
import { sendInviteAcceptedEmail } from "@/server/notifications";
import { reportSilentFallback } from "@/server/observability";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/accept-invite", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { invitationId?: unknown };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (typeof body.invitationId !== "string") {
    return NextResponse.json({ error: "invalid_body" }, { status: 400 });
  }

  const service = createServiceClient();
  const { data: invRow } = await service
    .from("workspace_invitations")
    .select("inviter_user_id, invitee_user_id, invitee_email, workspace_id, workspaces!inner(name)")
    .eq("id", body.invitationId)
    .single();

  if (invRow) {
    const isInvitee =
      invRow.invitee_user_id === user.id ||
      (!invRow.invitee_user_id &&
        invRow.invitee_email?.toLowerCase() === user.email?.toLowerCase());

    if (!isInvitee) {
      return NextResponse.json(
        { error: "not_intended_invitee" },
        { status: 403 },
      );
    }
  }

  const result = await acceptWorkspaceInvitation(body.invitationId, user.id);

  if (!result.ok) {
    const status =
      result.reason === "invitation_not_found" || result.reason === "expired"
        ? 404
        : result.reason === "not_intended_invitee"
          ? 403
          : result.reason === "already_accepted" || result.reason === "already_declined" || result.reason === "already_member" || result.reason === "revoked"
            ? 409
            : 500;
    return NextResponse.json({ error: result.reason }, { status });
  }

  // ADR-044 (#4543): switch the new member INTO the shared workspace so they
  // land there with full read access (CPO Decision #5) instead of staying on
  // their solo workspace. Without this, the post-accept redirect to
  // /dashboard/settings/team resolves a null current_organization_id and
  // notFound()s (the reported post-accept 404), and the KB resolves the member's
  // empty solo row. set_current_workspace_id is membership-checked (the member
  // row was just inserted) and sets BOTH current_workspace_id and
  // current_organization_id. Best-effort: the accept already committed, so a
  // switch failure must not fail the request — the member can switch manually
  // via the workspace switcher. Mirror to Sentry so a recurring failure on this
  // brand-survival surface is visible.
  const { error: switchError } = await supabase.rpc("set_current_workspace_id", {
    p_workspace_id: result.workspaceId,
  });
  if (switchError) {
    reportSilentFallback(
      { code: switchError.code, message: switchError.message },
      {
        feature: "workspace-invitations",
        op: "accept.set-active-workspace",
        message: `set_current_workspace_id after accept failed: ${switchError.message}`,
        extra: { userId: user.id, workspaceId: result.workspaceId },
      },
    );
  }

  if (invRow?.inviter_user_id) {
    const accepterName = user.user_metadata?.full_name ?? user.email ?? "A user";
    const workspaceArr = invRow.workspaces as unknown as Array<{ name: string }> | null;
    const workspaceName = workspaceArr?.[0]?.name ?? "Workspace";
    sendInviteAcceptedEmail(invRow.inviter_user_id, accepterName, workspaceName).catch(() => {});
  }

  return NextResponse.json({
    ok: true,
    workspaceId: result.workspaceId,
  });
}
