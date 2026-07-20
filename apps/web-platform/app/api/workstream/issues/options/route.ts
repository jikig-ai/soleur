// GET /api/workstream/issues/options — session-gated picker options (labels /
// assignees / milestones) for the edit-fields drawer. NOT in PUBLIC_PATHS
// (cookie-session auth, same treatment as the sibling issues route). Serves the
// active workspace's connected-repo options via the shared getWorkstreamIssueOptions
// accessor (owner/repo/installation resolve SERVER-SIDE, never request input).
//
// The accessor is DEGRADE-SAFE (empty arrays + Sentry on any failure), so this
// route never 502s the drawer — an editor opens with empty menus rather than a
// broken board.

import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getWorkstreamIssueOptions } from "@/server/workstream/get-workstream-issue-options";

export const dynamic = "force-dynamic";

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const options = await getWorkstreamIssueOptions(user.id);
  return NextResponse.json(options);
}
