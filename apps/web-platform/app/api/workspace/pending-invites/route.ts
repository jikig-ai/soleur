import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getPendingInvitesForUser } from "@/server/workspace-invitations";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const invites = await getPendingInvitesForUser(user.id, user.email ?? "");

  return NextResponse.json({ invites });
}
