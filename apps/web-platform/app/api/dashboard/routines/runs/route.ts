// GET /api/dashboard/routines/runs?cursor=&limit=&routineId=&status=&triggerSource=&since=
// (#5345 + #5412) — session-gated reverse-chronological run history (Recent Runs
// tab + per-routine drawer). Keyset-paginated; optional validated filters.

import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import {
  listRecentRuns,
  listLiveRuns,
  type LiveRun,
} from "@/server/routines/list-routines";
import { EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/cron-manifest";

export const dynamic = "force-dynamic";

// #5412 + #5766 — filter param domains. Terminal statuses persist in routine_runs;
// live statuses (running/stuck/resumed) are reader-computed over routine_run_progress
// and never reach the routine_runs query (DI-P2-F). The filter DOMAIN spans both so a
// status filter cannot silently drop live rows (P1-5). Invalid values are dropped.
const TERMINAL_STATUS = new Set(["completed", "failed"]);
const LIVE_STATUS = new Set(["running", "stuck", "resumed"]);
const STATUS_VALUES = new Set([...TERMINAL_STATUS, ...LIVE_STATUS]);
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
  // Only a TERMINAL status filter reaches the routine_runs query; a live-status
  // filter is applied to the in-flight set below (DI-P2-F).
  const terminalStatus = status && TERMINAL_STATUS.has(status) ? status : null;
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
      status: terminalStatus,
      triggerSource,
      since,
    });

    // In-flight live rows belong at the top and only exist "now", so they are
    // fetched on the FIRST page only. Skipped entirely under a triggerSource
    // filter (the attribution-free table has no trigger_source) or a terminal-only
    // status filter — avoiding a wasted query. Terminal-wins dedup (DI-Q3) drops
    // any live row whose run_id already appears in this page; since a just-finished
    // run's terminal row is the newest, it is always on page 1, so first-page dedup
    // is sufficient. routineId/status/since filters re-apply to the live set.
    let live: LiveRun[] = [];
    if (!cursor && !triggerSource && (!status || LIVE_STATUS.has(status))) {
      live = await listLiveRuns(supabase as never, Date.now());
      const terminalRunIds = new Set(
        page.runs.map((r) => r.run_id).filter((x): x is string => Boolean(x)),
      );
      live = live.filter((l) => !terminalRunIds.has(l.run_id));
      if (routineId) live = live.filter((l) => l.routine_id === routineId);
      if (status === "running" || status === "stuck") {
        live = live.filter((l) => l.status === status);
      } else if (status === "resumed") {
        live = live.filter((l) => l.resumed);
      }
      if (since) {
        live = live.filter((l) => Date.parse(l.started_at) >= Date.parse(since));
      }
    }

    return NextResponse.json({ ...page, live });
  } catch (e) {
    Sentry.captureException(e, { tags: { surface: "routine-runs-list" } });
    return NextResponse.json({ error: "runs_query_error" }, { status: 502 });
  }
}
