// GET /api/workstream/issues — session-gated read-only Workstream board feed.
// NOT in PUBLIC_PATHS (cookie-session auth, same treatment as the routines
// route). Serves a non-PII in-repo seed via the shared getWorkstreamIssues()
// accessor — the SAME fn the workstream_issues_list agent tool calls (no
// duplicated query). Mirrors app/api/dashboard/routines/route.ts exactly.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { getWorkstreamIssues } from "@/server/workstream/seed-issues";

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
    const issues = getWorkstreamIssues();
    return NextResponse.json({ issues });
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "workstream-issues" } });
    return NextResponse.json(
      { error: "workstream_query_error" },
      { status: 502 },
    );
  }
}
