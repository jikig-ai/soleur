// PR-G (#3947) — Server-only Inngest proxy for the audit viewer.
// Cookie-scoped Supabase client for auth; Inngest API call is server-only
// (INNGEST_SIGNING_KEY never reaches the client per TR7).
//
// Returns paginated JSON; 502 on Inngest API error so the audit viewer
// can degrade gracefully (Inngest panel error card; BYOK panel unaffected).

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { listInngestRunsForFounder } from "@/lib/inngest/list-runs";
import { verifiedUserId } from "@/server/request-auth";

export const dynamic = "force-dynamic";

export async function GET(request: Request) {
  const userId = await verifiedUserId(request);
  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  try {
    const runs = await listInngestRunsForFounder({
      founderId: userId,
      limit: 50,
    });
    return NextResponse.json({ runs });
  } catch (e) {
    Sentry.captureException(e, {
      tags: { surface: "audit-runs-proxy" },
      extra: { userId },
    });
    return NextResponse.json(
      { error: "inngest_api_error" },
      { status: 502 },
    );
  }
}
