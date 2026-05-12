// POST /dashboard/settings/privacy/reauth
//
// Phase 7 of feat-dsar-art15-export-endpoint (#3637, plan rev-2).
// FR2 + AC3 + AC27 + RK4.
//
// Two modes:
//
//   mode: "password"
//     - Body: { password: string }
//     - Re-verifies the active user's password via
//       supabase.auth.signInWithPassword(email, password). Email is
//       sourced from supabase.auth.getUser() so the client cannot
//       supply an arbitrary identity.
//     - On success: issue a reauth event with no authTime (password
//       path doesn't go through an IdP — AC27 is OAuth-only).
//
//   mode: "oauth_completed"
//     - Body: {} — the client has just completed signInWithOAuth({
//       prompt:'login', max_age:300 }) and returned to this page.
//     - Reads the current session's `auth_time` claim (from the JWT
//       access token) and issues a reauth event bound to that claim.
//       consumeReauthEvent then validates auth_time<=300s at the
//       downstream POST /api/account/export call.
//
// Returns: { event_id } on success; 401 on auth failure or stale
// session; 400 on malformed body.
//
// CSRF protection: validateOrigin.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { issueReauthEvent } from "@/server/dsar-reauth";

interface AccessTokenClaims {
  sub?: string;
  email?: string;
  auth_time?: number;
  session_id?: string;
}

function decodeJwtClaims(jwt: string): AccessTokenClaims | null {
  try {
    const payload = jwt.split(".")[1];
    if (!payload) return null;
    const decoded = Buffer.from(
      payload.replace(/-/g, "+").replace(/_/g, "/"),
      "base64",
    ).toString("utf-8");
    return JSON.parse(decoded) as AccessTokenClaims;
  } catch {
    return null;
  }
}

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("dashboard/settings/privacy/reauth", origin);

  const supabase = await createClient();
  const { data: userData } = await supabase.auth.getUser();
  if (!userData?.user || !userData.user.email) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const user = userData.user as { id: string; email: string };

  const { data: sessionData } = await supabase.auth.getSession();
  const session = sessionData?.session;
  if (!session) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }
  const claims = decodeJwtClaims(session.access_token);
  const sessionId =
    (session as unknown as { session_id?: string }).session_id ??
    claims?.session_id ??
    user.id;

  const body = (await request.json().catch(() => null)) as
    | { mode?: "password" | "oauth_completed"; password?: string }
    | null;

  if (body?.mode === "password") {
    if (typeof body.password !== "string" || body.password.length === 0) {
      return NextResponse.json({ error: "Missing password" }, { status: 400 });
    }
    const { error: signinErr } = await supabase.auth.signInWithPassword({
      email: user.email,
      password: body.password,
    });
    if (signinErr) {
      return NextResponse.json(
        { error: "Password verification failed" },
        { status: 401 },
      );
    }
    const { eventId } = issueReauthEvent({
      userId: user.id,
      sessionId,
      // Password path — AC27 auth_time validation is OAuth-only.
    });
    return NextResponse.json({ event_id: eventId });
  }

  if (body?.mode === "oauth_completed") {
    if (!claims?.auth_time) {
      // No auth_time in the JWT — either the IdP didn't supply one or
      // the session isn't OAuth-derived. RK4 + AC27: refuse rather
      // than fall back to "trust the session" so a misconfigured IdP
      // cannot bypass the reauth gate.
      return NextResponse.json(
        {
          error: "OAuth provider did not return an auth_time claim",
          remediation:
            "Log out and back in via the OAuth provider; if the " +
            "problem persists, use the password re-entry path or " +
            "contact legal@jikigai.com.",
        },
        { status: 401 },
      );
    }
    const { eventId } = issueReauthEvent({
      userId: user.id,
      sessionId,
      authTime: claims.auth_time,
    });
    return NextResponse.json({ event_id: eventId });
  }

  return NextResponse.json(
    { error: "Missing or unrecognised mode" },
    { status: 400 },
  );
}
