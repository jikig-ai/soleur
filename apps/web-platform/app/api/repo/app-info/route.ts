import { NextResponse } from "next/server";
import { getAppSlug } from "@/server/github-app";
import { verifiedUserId } from "@/server/request-auth";

/**
 * GET /api/repo/app-info
 *
 * Returns the GitHub App slug for use in install URLs.
 * Requires authentication to prevent slug enumeration.
 */
export async function GET(request: Request) {
  const userId = await verifiedUserId(request);

  if (!userId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const slug = await getAppSlug();
  return NextResponse.json({ slug });
}
