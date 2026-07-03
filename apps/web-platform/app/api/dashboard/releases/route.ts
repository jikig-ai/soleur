// GET /api/dashboard/releases (#5958) — session-gated in-app Releases feed.
// Returns the app's web-v* GitHub Releases, cleaned server-side (PII strip +
// security-fixes title-only + web-v*-only filter), newest first. The data is
// user-independent (Soleur's own releases); the session gate just keeps the
// surface authenticated, matching sibling read routes. NOT in PUBLIC_PATHS
// (cookie-session auth).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { fetchWebReleases } from "@/server/release-notes";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  try {
    const releases = await fetchWebReleases();
    return NextResponse.json({ releases });
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "releases-list" } });
    return NextResponse.json({ error: "releases_query_error" }, { status: 502 });
  }
}
