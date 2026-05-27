import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { acceptWorkspaceInvitation } from "@/server/workspace-invitations";
import { sendInviteAcceptedEmail } from "@/server/notifications";

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
          : result.reason === "already_accepted" || result.reason === "already_declined" || result.reason === "already_member"
            ? 409
            : 500;
    return NextResponse.json({ error: result.reason }, { status });
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
