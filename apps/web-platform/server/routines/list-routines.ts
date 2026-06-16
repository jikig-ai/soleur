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
  // #5412 — optional filters. eq/gte return OrderedQuery (recursive) so
  // multiple filters chain and the cursor `.or()`/`.limit()` still follow.
  // PostgREST parameterizes the value (no injection); callers validate the
  // value domain before passing it (status/triggerSource enums, routineId ∈
  // EXPECTED_CRON_FUNCTIONS, since = ISO).
  eq: (col: string, val: string) => OrderedQuery;
  gte: (col: string, val: string) => OrderedQuery;
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
  // #5412 — surfaced in the per-run detail panel. NOT actor_id/delegating_principal
  // (operator-PII UUIDs deliberately omitted from RUN_COLS); actor_class is a
  // coarse enum (system | human | agent).
  run_id: string | null;
  actor_class: string;
}

export interface RecentRunsPage {
  runs: RecentRun[];
  nextCursor: string | null;
}

const LATEST_COLS =
  "routine_id,status,trigger_source,started_at,ended_at,duration_ms,error_summary";
// #5412: + run_id, actor_class for the per-run detail panel. NEVER add
// actor_id / delegating_principal — those operator-PII UUIDs stay omitted (the
// list-routines.test.ts projection guard asserts their absence). This projection
// also feeds the routine_runs_list agent tool (service-client read); actor_class
// is a coarse enum, safe to surface.
const RUN_COLS =
  "id,routine_id,run_id,status,trigger_source,actor_class,started_at,ended_at,duration_ms,error_summary";

// Cursor-half validators (the cursor is server-minted: ISO ts + UUID id). Used
// to reject a tampered cursor before it reaches the PostgREST `.or()` string.
const CURSOR_TS_RE = /^\d{4}-\d{2}-\d{2}T[\d:.]+(?:[+-]\d{2}:\d{2}|Z)?$/;
const CURSOR_ID_RE = /^[0-9A-Za-z_-]+$/;

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
  opts: {
    cursor?: string | null;
    limit?: number;
    // #5412 — optional filters (validated by the caller before passing).
    routineId?: string | null;
    status?: string | null;
    triggerSource?: string | null;
    since?: string | null;
  } = {},
): Promise<RecentRunsPage> {
  const limit = Math.min(Math.max(opts.limit ?? 50, 1), 200);
  const ordered = supabase
    .from("routine_runs")
    .select(RUN_COLS)
    .order("started_at", { ascending: false })
    .order("id", { ascending: false });
  // Apply filters BEFORE the cursor `.or()`/`.limit()` so the (started_at,id)
  // keyset tuple is preserved (filters AND the cursor row-comparison).
  let base: OrderedQuery = ordered;
  if (opts.routineId) base = base.eq("routine_id", opts.routineId);
  if (opts.status) base = base.eq("status", opts.status);
  if (opts.triggerSource) base = base.eq("trigger_source", opts.triggerSource);
  if (opts.since) base = base.gte("started_at", opts.since);
  let q: { limit: (n: number) => Promise<{ data: unknown; error: unknown }> } =
    base;
  if (opts.cursor) {
    const sep = opts.cursor.lastIndexOf("|");
    // Tolerate a legacy (started_at-only) cursor: treat the whole value as the
    // timestamp and fall back to a plain started_at row-comparison.
    const ts = sep === -1 ? opts.cursor : opts.cursor.slice(0, sep);
    const id = sep === -1 ? null : opts.cursor.slice(sep + 1);
    // The cursor is server-minted (`${last.started_at}|${last.id}`), so a
    // legitimate value is always an ISO timestamp + a UUID. Validate both
    // halves before interpolating into the PostgREST `.or()` predicate —
    // commas/parens in a tampered cursor would otherwise inject extra OR
    // clauses (RLS + the fixed projection still bound the blast radius, but
    // this rejects the malformed query outright). A bad cursor → first page.
    if (!CURSOR_TS_RE.test(ts) || (id !== null && !CURSOR_ID_RE.test(id))) {
      q = base;
    } else {
      q = base.or(
        id === null
          ? `started_at.lt.${ts}`
          : `started_at.lt.${ts},and(started_at.eq.${ts},id.lt.${id})`,
      );
    }
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
