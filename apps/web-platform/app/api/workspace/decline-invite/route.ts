import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { declineWorkspaceInvitation } from "@/server/workspace-invitations";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/workspace/decline-invite", origin);

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

  const result = await declineWorkspaceInvitation(body.invitationId, user.id);

  if (!result.ok) {
    const status =
      result.reason === "invitation_not_found"
        ? 404
        : result.reason === "already_accepted" || result.reason === "already_declined"
          ? 409
          : 500;
    return NextResponse.json({ error: result.reason }, { status });
  }

  return NextResponse.json({ ok: true });
}
