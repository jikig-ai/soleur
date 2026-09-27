import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { declineWorkspaceInvitation } from "@/server/workspace-invitations";
import {
  verifiedUserId,
  boundedAuthGetUser,
  sessionJwtEmailForVerifiedUser,
} from "@/server/request-auth";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/decline-invite", origin);

  const supabase = await createClient();
  const userId = await verifiedUserId(request);
  if (!userId) {
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
    .select("invitee_user_id, invitee_email")
    .eq("id", body.invitationId)
    .single();

  if (invRow) {
    let isInvitee = invRow.invitee_user_id === userId;
    if (!isInvitee && !invRow.invitee_user_id) {
      // The invitee_email leg needs the caller's email. Read it from the
      // local session JWT (accepted only when the token's `sub` agrees with
      // the verified id — the helper enforces the check); if the JWT cannot
      // supply it, re-verify remotely (same pattern as pending-invites).
      let callerEmail = await sessionJwtEmailForVerifiedUser(supabase, userId);
      if (callerEmail === null) {
        const userData = await boundedAuthGetUser(supabase);
        callerEmail = userData?.user?.email ?? null;
      }
      // BOTH sides must be present: anonymized invitations null
      // invitee_email and a claim-miss JWT yields null callerEmail —
      // `undefined === undefined` would match any caller on an erased row.
      isInvitee =
        callerEmail !== null &&
        invRow.invitee_email != null &&
        invRow.invitee_email.toLowerCase() === callerEmail.toLowerCase();
    }

    if (!isInvitee) {
      return NextResponse.json(
        { error: "not_intended_invitee" },
        { status: 403 },
      );
    }
  }

  const result = await declineWorkspaceInvitation(body.invitationId, userId);

  if (!result.ok) {
    const status =
      result.reason === "invitation_not_found"
        ? 404
        : result.reason === "not_intended_invitee"
          ? 403
          : result.reason === "already_accepted" || result.reason === "already_declined"
            ? 409
            : 500;
    return NextResponse.json({ error: result.reason }, { status });
  }

  return NextResponse.json({ ok: true });
}
