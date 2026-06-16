// Shared routine read queries (#5345 PR-1). ONE implementation backing BOTH the
// dashboard routes (Phase 4) and the agent MCP tools (Phase 5) — no duplicated
// query. Callers pass a Supabase client (cookie-session for routes, same for
// the agent's authenticated context) so RLS (operator-select) is enforced.

import {
  EXPECTED_CRON_FUNCTIONS,
} from "@/server/inngest/cron-manifest";
import { ROUTINE_METADATA, type RoutineMeta } from "@/server/inngest/routine-metadata";

// Minimal structural type so this module does not depend on the supabase-js
// generic client type (which the project leaves untyped).
interface OrderedQuery {
  limit: (n: number) => Promise<{ data: unknown; error: unknown }>;
  // Keyset filter is a row-comparison (started_at, id) < (cursor) expressed as
  // a PostgREST `.or()` so same-millisecond ties are not skipped at the page
  // boundary (a bare `.lt("started_at", …)` drops every row sharing the
  // boundary timestamp — crons fan out on identical cron ticks).
  or: (filter: string) => {
    limit: (n: number) => Promise<{ data: unknown; error: unknown }>;
  };
}
interface SupabaseLike {
  from: (table: string) => {
    select: (cols: string) => {
      order: (
        col: string,
        opts: { ascending: boolean },
      ) => {
        order: (col: string, opts: { ascending: boolean }) => OrderedQuery;
      };
    } & Promise<{ data: unknown; error: unknown }>;
  };
}

export interface RunSummary {
  status: string;
  trigger_source: string;
  started_at: string;
  ended_at: string | null;
  duration_ms: number | null;
  error_summary: string | null;
}

export interface RoutineListItem extends RoutineMeta {
  fnId: string;
  lastRun: RunSummary | null;
}

export interface RecentRun extends RunSummary {
  id: string;
  routine_id: string;
}

export interface RecentRunsPage {
  runs: RecentRun[];
  nextCursor: string | null;
}

const LATEST_COLS =
  "routine_id,status,trigger_source,started_at,ended_at,duration_ms,error_summary";
const RUN_COLS =
  "id,routine_id,status,trigger_source,started_at,ended_at,duration_ms,error_summary";

/** All routines (grouped/sorted client-side) with each one's latest run. */
export async function listRoutinesWithLastRun(
  supabase: SupabaseLike,
): Promise<RoutineListItem[]> {
  const { data, error } = await supabase
    .from("routine_runs_latest")
    .select(LATEST_COLS);
  if (error) throw error;
  const rows = (data ?? []) as Array<RunSummary & { routine_id: string }>;
  const byId = new Map<string, RunSummary>(
    rows.map((r) => [r.routine_id, r]),
  );
  // EXPECTED_CRON_FUNCTIONS is the canonical routine set; a missing metadata
  // entry is impossible (parity test) but null-guarded defensively.
  return EXPECTED_CRON_FUNCTIONS.filter((fnId) => ROUTINE_METADATA[fnId]).map(
    (fnId) => ({
      fnId,
      ...ROUTINE_METADATA[fnId],
      lastRun: byId.get(fnId) ?? null,
    }),
  );
}

/**
 * Reverse-chronological execution history, keyset-paginated on the full
 * (started_at, id) tuple. The cursor is `<started_at>|<id>` — comparing only
 * started_at would skip rows that share the boundary row's millisecond.
 */
export async function listRecentRuns(
  supabase: SupabaseLike,
  opts: { cursor?: string | null; limit?: number } = {},
): Promise<RecentRunsPage> {
  const limit = Math.min(Math.max(opts.limit ?? 50, 1), 200);
  const ordered = supabase
    .from("routine_runs")
    .select(RUN_COLS)
    .order("started_at", { ascending: false })
    .order("id", { ascending: false });
  let q: { limit: (n: number) => Promise<{ data: unknown; error: unknown }> } =
    ordered;
  if (opts.cursor) {
    const sep = opts.cursor.lastIndexOf("|");
    // Tolerate a legacy (started_at-only) cursor: treat the whole value as the
    // timestamp and fall back to a plain started_at row-comparison.
    const ts = sep === -1 ? opts.cursor : opts.cursor.slice(0, sep);
    const id = sep === -1 ? null : opts.cursor.slice(sep + 1);
    q = ordered.or(
      id === null
        ? `started_at.lt.${ts}`
        : `started_at.lt.${ts},and(started_at.eq.${ts},id.lt.${id})`,
    );
  }
  const { data, error } = await q.limit(limit + 1);
  if (error) throw error;
  const rows = (data ?? []) as RecentRun[];
  const hasMore = rows.length > limit;
  const page = hasMore ? rows.slice(0, limit) : rows;
  const last = page[page.length - 1];
  const nextCursor = hasMore && last ? `${last.started_at}|${last.id}` : null;
  return { runs: page, nextCursor };
}
