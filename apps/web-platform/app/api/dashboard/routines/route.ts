// GET /api/dashboard/routines (#5345) — session-gated Routines list with each
// routine's latest run. NOT in PUBLIC_PATHS (cookie-session auth). Reads
// routine_runs_latest via RLS; never touches INNGEST_SIGNING_KEY (TR1).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { listRoutinesWithLastRun } from "@/server/routines/list-routines";

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
    const routines = await listRoutinesWithLastRun(supabase as never);
    return NextResponse.json({ routines });
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "routines-list" } });
    return NextResponse.json({ error: "routines_query_error" }, { status: 502 });
  }
}
