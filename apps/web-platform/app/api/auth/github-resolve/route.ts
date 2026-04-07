import { NextResponse } from "next/server";
import logger from "@/server/logger";

/**
 * GET /api/auth/github-resolve
 *
 * Initiates a GitHub App OAuth flow to discover the user's GitHub username
 * without linking identities in Supabase. Used by email-only users who need
 * to auto-detect their GitHub App installation.
 *
 * Sets a state nonce cookie for CSRF protection and redirects to GitHub.
 */
export async function GET() {
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL ?? "https://app.soleur.ai";
  const clientId = process.env.GITHUB_CLIENT_ID;
  if (!clientId) {
    logger.error("GITHUB_CLIENT_ID not configured");
    return NextResponse.redirect(new URL("/connect-repo?resolve_error=1", siteUrl));
  }

  const state = crypto.randomUUID();
  const callbackUrl = `${siteUrl}/api/auth/github-resolve/callback`;

  const authorizeUrl = new URL("https://github.com/login/oauth/authorize");
  authorizeUrl.searchParams.set("client_id", clientId);
  authorizeUrl.searchParams.set("state", state);
  authorizeUrl.searchParams.set("redirect_uri", callbackUrl);

  const response = NextResponse.redirect(authorizeUrl.toString(), 302);

  response.cookies.set("soleur_github_resolve", state, {
    httpOnly: true,
    secure: true,
    sameSite: "lax",
    maxAge: 300,
    path: "/",
  });

  logger.info("GitHub identity resolve OAuth initiated");

  return response;
}
