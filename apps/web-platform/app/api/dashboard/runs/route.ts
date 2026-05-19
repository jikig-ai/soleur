// PR-G (#3947) — Server-only Inngest proxy for the audit viewer.
// Cookie-scoped Supabase client for auth; Inngest API call is server-only
// (INNGEST_SIGNING_KEY never reaches the client per TR7).
//
// Returns paginated JSON; 502 on Inngest API error so the audit viewer
// can degrade gracefully (Inngest panel error card; BYOK panel unaffected).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { listInngestRunsForFounder } from "@/lib/inngest/list-runs";

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
    const runs = await listInngestRunsForFounder({
      founderId: user.id,
      limit: 50,
    });
    return NextResponse.json({ runs });
  } catch (e) {
    Sentry.captureException(e, {
      tags: { surface: "audit-runs-proxy" },
      extra: { userId: user.id },
    });
    return NextResponse.json(
      { error: "inngest_api_error" },
      { status: 502 },
    );
  }
}
