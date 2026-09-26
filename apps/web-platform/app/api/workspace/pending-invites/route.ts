import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getPendingInvitesForUser } from "@/server/workspace-invitations";
import { verifiedUserId } from "@/server/request-auth";
import { decodeJwtPayloadUnsafe } from "@/lib/supabase/tenant";

export async function GET(req: Request) {
  // Middleware-verified identity (x-soleur-auth-user-id) replaces the
  // getUser() RTT; absent header falls back to getUser() — fail-closed.
  const userId = await verifiedUserId(req);
  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // The invitee_email half of the resolver needs the caller's email. When
  // middleware minted the identity header the session is already verified, so
  // read email from the local session JWT (cookie decode — no auth-server
  // RTT). If the JWT cannot supply it (header-absent fallback arm, or a
  // token without an email claim), re-verify remotely.
  const supabase = await createClient();
  const { data: sessionData } = await supabase.auth.getSession();
  let email = "";
  const accessToken = sessionData?.session?.access_token;
  if (accessToken) {
    try {
      const payload = decodeJwtPayloadUnsafe(accessToken);
      if (typeof payload.email === "string") email = payload.email;
    } catch {
      // Malformed JWT → remote re-verify below.
    }
  }
  if (!email) {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    email = user?.email ?? "";
  }

  const invites = await getPendingInvitesForUser(userId, email);

  return NextResponse.json({ invites });
}
