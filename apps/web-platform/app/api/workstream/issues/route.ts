// GET /api/workstream/issues — session-gated read-only Workstream board feed.
// NOT in PUBLIC_PATHS (cookie-session auth, same treatment as the routines
// route). Serves the active workspace's REAL connected-repo issues via the
// shared getWorkstreamIssues() accessor — the SAME fn the workstream_issues_list
// agent tool calls (no duplicated query). The accessor returns [] for no
// connected repo / no installation (honest empty board) and THROWS on a GitHub
// API failure → 502 here (never empty-masquerading-as-success).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { getWorkstreamIssues } from "@/server/workstream/get-workstream-issues";

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
    const issues = await getWorkstreamIssues(user.id);
    return NextResponse.json({ issues });
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "workstream-issues" } });
    return NextResponse.json(
      { error: "workstream_query_error" },
      { status: 502 },
    );
  }
}
