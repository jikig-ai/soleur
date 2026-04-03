import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getAppSlug } from "@/server/github-app";

/**
 * GET /api/repo/app-info
 *
 * Returns the GitHub App slug for use in install URLs.
 * Requires authentication to prevent slug enumeration.
 */
export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const slug = await getAppSlug();
  return NextResponse.json({ slug });
}
