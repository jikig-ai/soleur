import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import logger from "@/server/logger";

const REDIRECT_BASE = "/connect-repo";
const ERROR_REDIRECT = `${REDIRECT_BASE}?resolve_error=1`;

/** Parse a named cookie from the raw Cookie header. */
function getCookie(request: Request, name: string): string | undefined {
  const header = request.headers.get("Cookie") ?? "";
  const match = header.split(";").map((s) => s.trim()).find((s) => s.startsWith(`${name}=`));
  return match ? match.slice(name.length + 1) : undefined;
}

/**
 * GET /api/auth/github-resolve/callback
 *
 * GitHub OAuth callback for username resolution. Exchanges the authorization
 * code for a token, calls GET /user to extract the login, stores it as
 * github_username on the users table, and redirects to /connect-repo.
 *
 * The access token is discarded after username extraction — all repo
 * operations use GitHub App installation tokens.
 */
export async function GET(request: Request) {
  const { searchParams } = new URL(request.url);
  const code = searchParams.get("code");
  const state = searchParams.get("state");

  // --- CSRF: verify state cookie ---
  const stateCookie = getCookie(request, "soleur_github_resolve");

  if (!code) {
    logger.warn({ state, hasStateCookie: !!stateCookie }, "GitHub resolve callback: no code param (user denied or error)");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  if (!stateCookie || stateCookie !== state) {
    logger.warn({ state, stateCookie: stateCookie?.slice(0, 8) }, "GitHub resolve callback: state mismatch (CSRF)");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  // --- Exchange code for token ---
  const clientId = process.env.GITHUB_CLIENT_ID;
  const clientSecret = process.env.GITHUB_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    logger.error("GITHUB_CLIENT_ID or GITHUB_CLIENT_SECRET not configured");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  let accessToken: string;
  try {
    const tokenRes = await fetch("https://github.com/login/oauth/access_token", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: JSON.stringify({
        client_id: clientId,
        client_secret: clientSecret,
        code,
      }),
    });

    if (!tokenRes.ok) {
      const body = await tokenRes.json().catch(() => null);
      logger.error({ status: tokenRes.status, body }, "GitHub resolve callback: token exchange failed");
      return redirectWithDeletedCookie(ERROR_REDIRECT, request);
    }

    const tokenData = await tokenRes.json();
    if (!tokenData.access_token) {
      logger.error({ error: tokenData.error }, "GitHub resolve callback: no access_token in response");
      return redirectWithDeletedCookie(ERROR_REDIRECT, request);
    }

    accessToken = tokenData.access_token;
  } catch (err) {
    logger.error({ err }, "GitHub resolve callback: token exchange threw");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  // --- Get GitHub username ---
  let githubUsername: string;
  try {
    const userRes = await fetch("https://api.github.com/user", {
      headers: {
        Authorization: `Bearer ${accessToken}`,
        Accept: "application/vnd.github+json",
      },
    });

    if (!userRes.ok) {
      logger.error({ status: userRes.status }, "GitHub resolve callback: GET /user failed");
      return redirectWithDeletedCookie(ERROR_REDIRECT, request);
    }

    const userData = await userRes.json();
    if (!userData.login || typeof userData.login !== "string") {
      logger.error({ login: userData.login }, "GitHub resolve callback: empty or invalid login");
      return redirectWithDeletedCookie(ERROR_REDIRECT, request);
    }

    // Validate GitHub username format (alphanumeric + hyphens, max 39 chars)
    if (!/^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,37}[a-zA-Z0-9])?$/.test(userData.login)) {
      logger.error({ login: userData.login.slice(0, 50) }, "GitHub resolve callback: invalid login format");
      return redirectWithDeletedCookie(ERROR_REDIRECT, request);
    }

    githubUsername = userData.login;
  } catch (err) {
    logger.error({ err }, "GitHub resolve callback: GET /user threw");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  // --- Revoke the access token (fire-and-forget) ---
  // The token has no scopes but revoking it limits the window for misuse.
  // Uses DELETE /applications/{client_id}/token with Basic auth.
  try {
    await fetch(`https://api.github.com/applications/${clientId}/token`, {
      method: "DELETE",
      headers: {
        Authorization: `Basic ${btoa(`${clientId}:${clientSecret}`)}`,
        Accept: "application/vnd.github+json",
      },
      body: JSON.stringify({ access_token: accessToken }),
    });
  } catch {
    // Best-effort — don't fail the flow if revocation fails
    logger.warn("GitHub resolve callback: token revocation failed (non-fatal)");
  }

  // --- Get authenticated user ---
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    logger.warn("GitHub resolve callback: no authenticated user (session expired?)");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  // --- Store github_username ---
  const serviceClient = createServiceClient();
  const { error: updateError } = await serviceClient
    .from("users")
    .update({ github_username: githubUsername })
    .eq("id", user.id);

  if (updateError) {
    logger.error({ err: updateError, userId: user.id }, "GitHub resolve callback: failed to store github_username");
    return redirectWithDeletedCookie(ERROR_REDIRECT, request);
  }

  logger.info({ userId: user.id, githubUsername }, "GitHub identity resolved and stored");

  return redirectWithDeletedCookie(REDIRECT_BASE, request);
}

/** Build a redirect response that also deletes the state cookie. */
function redirectWithDeletedCookie(path: string, _request: Request): NextResponse {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://app.soleur.ai";
  const response = NextResponse.redirect(new URL(path, siteUrl), 302);
  response.cookies.set("soleur_github_resolve", "", {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    maxAge: 0,
    path: "/",
  });
  return response;
}
