// GET /api/dashboard/routines/runs?cursor=&limit=&routineId=&status=&triggerSource=&since=
// (#5345 + #5412) — session-gated reverse-chronological run history (Recent Runs
// tab + per-routine drawer). Keyset-paginated; optional validated filters.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { listRecentRuns } from "@/server/routines/list-routines";
import { EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/cron-manifest";

export const dynamic = "force-dynamic";

// #5412 — filter param domains. status excludes the client-only "running"
// optimistic state (persisted rows are only completed/failed). Invalid values
// are dropped (treated as no filter), never passed to the query.
const STATUS_VALUES = new Set(["completed", "failed"]);
const TRIGGER_VALUES = new Set(["scheduled", "manual", "agent"]);

function pickEnum(raw: string | null, allowed: Set<string>): string | null {
  return raw && allowed.has(raw) ? raw : null;
}

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

  // Validate filters: drop anything outside its domain (no injection, no noise).
  const routineIdRaw = url.searchParams.get("routineId");
  const routineId =
    routineIdRaw && EXPECTED_CRON_FUNCTIONS.includes(routineIdRaw)
      ? routineIdRaw
      : null;
  const status = pickEnum(url.searchParams.get("status"), STATUS_VALUES);
  const triggerSource = pickEnum(
    url.searchParams.get("triggerSource"),
    TRIGGER_VALUES,
  );
  const sinceRaw = url.searchParams.get("since");
  const since =
    sinceRaw && !Number.isNaN(Date.parse(sinceRaw))
      ? new Date(sinceRaw).toISOString()
      : null;

  try {
    const page = await listRecentRuns(supabase as never, {
      cursor,
      limit,
      routineId,
      status,
      triggerSource,
      since,
    });
    return NextResponse.json(page);
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "routine-runs-list" } });
    return NextResponse.json({ error: "runs_query_error" }, { status: 502 });
  }
}
