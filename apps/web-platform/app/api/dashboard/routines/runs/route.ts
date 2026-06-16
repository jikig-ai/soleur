// GET /api/dashboard/routines/runs?cursor=&limit= (#5345) — session-gated
// reverse-chronological run history (Recent Runs tab). Keyset-paginated.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { listRecentRuns } from "@/server/routines/list-routines";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }
  const url = new URL(request.url);
  const cursor = url.searchParams.get("cursor");
  const limitParam = Number(url.searchParams.get("limit"));
  const limit = Number.isFinite(limitParam) && limitParam > 0 ? limitParam : 50;
  try {
    const page = await listRecentRuns(supabase as never, { cursor, limit });
    return NextResponse.json(page);
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "routine-runs-list" } });
    return NextResponse.json({ error: "runs_query_error" }, { status: 502 });
  }
}
