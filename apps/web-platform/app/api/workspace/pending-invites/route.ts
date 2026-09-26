import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getPendingInvitesForUser } from "@/server/workspace-invitations";
import {
  verifiedUserId,
  sessionJwtEmailForVerifiedUser,
} from "@/server/request-auth";
import { reportSilentFallback } from "@/server/observability";

export async function GET(req: Request) {
  // Middleware-verified identity (x-soleur-auth-user-id) replaces the
  // getUser() RTT; absent header falls back to getUser() — fail-closed.
  const userId = await verifiedUserId(req);
  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // The invitee_email half of the resolver needs the caller's email. Read it
  // from the local session JWT — accepted only when the token's `sub` agrees
  // with the verified id (a divergent claim could disclose another account's
  // invitee rows; the helper enforces the check exactly once). If the JWT
  // cannot supply it, re-verify remotely — the one case that pays the RTT.
  const supabase = await createClient();
  // Staleness bound: the JWT `email` claim reflects token-mint time — an email
  // change takes up to the access-token TTL (~1h) to propagate; the remote
  // fallback arm stays auth-server-fresh. Bounded + self-healing (ADR-253
  // amendment 2026-09-26).
  let email = await sessionJwtEmailForVerifiedUser(supabase, userId);
  if (email === null) {
    const {
      data: { user },
    } = await supabase.auth.getUser();
    email = user?.email ?? "";
  }
  if (email === "") {
    // Verified user but no resolvable email → the byEmail leg silently
    // returns nothing. Mirror it — this endpoint exists to rescue the
    // keyless-invitee deadlock, and a silent miss is the failure class it
    // was built to prevent (cq-silent-fallback-must-mirror-to-sentry).
    reportSilentFallback(null, {
      feature: "workspace-invitations",
      op: "pending-invites.email-unresolved",
      message: "verified userId but email unresolved (JWT + getUser both empty)",
    });
  }

  const invites = await getPendingInvitesForUser(userId, email);

  return NextResponse.json({ invites });
}
