// Progressive Workstream issues feed — frame vocabulary + pure helpers, plus
// the client fetcher that consumes `GET /api/workstream/issues` negotiated as
// `text/event-stream`. Client-safe leaf: imports types from `./workstream`
// only (same layering rule as lib/support-sse.ts — no React, no components/,
// no server-only imports).
//
// Frame semantics are DELTA (each frame carries only new information — the
// cumulative-vs-delta ambiguity produced duplicated output in 2026-04-13's
// websocket fix): one `issues` frame per upstream GitHub REST page, upserted
// by id; a single optional `statuses` frame re-points already-emitted cards
// once the Project board Status map lands (ADR-097 precedence); `done`/`error`
// are terminal. A stream that ends without `done` is a TRUNCATED feed and must
// surface as an error — never as a silently-complete board.

import type { WorkstreamIssue, WorkstreamStatus } from "./workstream";

/** Board-precedence meta (same payload as the bulk `{issues, board}` JSON). */
export interface WorkstreamFeedBoardMeta {
  onKanbanOrg: boolean;
  projectWritable: boolean;
}

/** Minimal reconcile payload for a card whose derived column/`live` changed
 *  once board precedence was applied. */
export interface WorkstreamStatusOverride {
  id: string;
  status: WorkstreamStatus;
  live: boolean;
}

export type WorkstreamFeedEvent =
  | { type: "meta"; board: WorkstreamFeedBoardMeta }
  | { type: "issues"; issues: WorkstreamIssue[] }
  | { type: "statuses"; overrides: WorkstreamStatusOverride[] }
  | { type: "done"; openTruncated: boolean }
  | { type: "error"; code: string };

/** The response shape every fetcher on this key resolves — identical to the
 *  bulk JSON arm so write-path reconcilers and the nav badge are untouched. */
export interface WorkstreamIssuesResponse {
  issues: WorkstreamIssue[];
  board?: WorkstreamFeedBoardMeta;
}

/** Serialize one feed event as a single SSE `data:` frame (server side). */
export function formatWorkstreamSseFrame(event: WorkstreamFeedEvent): string {
  return `data: ${JSON.stringify(event)}\n\n`;
}

/**
 * Parse concatenated SSE text into complete events + an unterminated tail the
 * caller threads back in on the next chunk. Malformed `data:` payloads and
 * non-`data:` parts are dropped, never thrown — a garbled frame must not kill
 * the feed (parse contract mirrors parseSupportSseChunks).
 */
export function parseWorkstreamSseChunks(buffer: string): {
  events: WorkstreamFeedEvent[];
  rest: string;
} {
  const events: WorkstreamFeedEvent[] = [];
  const parts = buffer.split("\n\n");
  // The final element is the (possibly empty) unterminated tail — keep it.
  const rest = parts.pop() ?? "";
  for (const part of parts) {
    const line = part.trimStart();
    if (!line.startsWith("data:")) continue;
    const payload = line.slice("data:".length).trim();
    if (payload.length === 0) continue;
    try {
      const parsed = JSON.parse(payload) as WorkstreamFeedEvent;
      if (
        parsed &&
        typeof parsed === "object" &&
        typeof (parsed as { type?: unknown }).type === "string"
      ) {
        events.push(parsed);
      }
    } catch {
      // Drop a malformed frame — the stream continues.
    }
  }
  return { events, rest };
}

/**
 * Merge one progressive commit into the cached response. Upsert-by-id over the
 * current set: streamed copies replace same-id entries, and entries the stream
 * has not emitted yet are KEPT — which is what preserves optimistic `SOLAA-N*`
 * temp cards (and any locally-edited card) across mid-stream commits.
 */
export function mergeStreamedIssues(
  current: WorkstreamIssuesResponse | undefined,
  partial: WorkstreamIssuesResponse,
): WorkstreamIssuesResponse {
  const merged = new Map<string, WorkstreamIssue>();
  for (const i of current?.issues ?? []) merged.set(i.id, i);
  for (const i of partial.issues) merged.set(i.id, i);
  return { issues: [...merged.values()], board: partial.board };
}

/**
 * Apply a `statuses` reconcile frame: patch `status` + `live` on the listed ids
 * only. `live: false` removes the marker (the field is `live?: boolean`).
 */
export function applyStatusOverrides(
  issues: WorkstreamIssue[],
  overrides: WorkstreamStatusOverride[],
): WorkstreamIssue[] {
  if (overrides.length === 0) return issues;
  const byId = new Map(overrides.map((o) => [o.id, o]));
  return issues.map((i) => {
    const o = byId.get(i.id);
    if (!o) return i;
    const next: WorkstreamIssue = { ...i, status: o.status };
    if (o.live) next.live = true;
    else delete next.live;
    return next;
  });
}

/**
 * The board's SWR fetcher: negotiate the SSE arm, commit each `issues`/
 * `statuses` frame via `onPartial` while the stream is open, and resolve the
 * SAME `{issues, board}` object at `done` that the JSON arm returns.
 *
 * Terminal rules (P4 — a truncated feed is never a silent success):
 *   - `!res.ok` → throw (jsonFetcher parity; SWR records `error`).
 *   - non-SSE content-type (older deploy / buffering proxy) → `res.json()`.
 *   - `error` frame OR the body ending without `done` → throw; progressive
 *     commits already applied surface as the existing `error && data` banner.
 */
export async function fetchWorkstreamIssuesFeed(
  key: readonly [string, ...unknown[]] | string,
  onPartial?: (partial: WorkstreamIssuesResponse) => void,
): Promise<WorkstreamIssuesResponse> {
  const url = Array.isArray(key) ? key[0] : key;
  const res = await fetch(url, {
    headers: { Accept: "text/event-stream" },
  });
  if (!res.ok) {
    throw new Error(`Request failed: ${res.status} ${url}`);
  }
  const contentType = res.headers.get("content-type") ?? "";
  if (!contentType.includes("text/event-stream") || !res.body) {
    return (await res.json()) as WorkstreamIssuesResponse;
  }

  const acc = new Map<string, WorkstreamIssue>();
  let board: WorkstreamFeedBoardMeta | undefined;
  let sawDone = false;

  // Skip commits until at least one real issue has streamed — an early
  // meta-only commit would flash a false EmptyState under the skeleton.
  const commit = () => {
    if (acc.size === 0) return;
    onPartial?.({ issues: [...acc.values()], board });
  };

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buf = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    buf += decoder.decode(value, { stream: true });
    const parsed = parseWorkstreamSseChunks(buf);
    buf = parsed.rest;
    for (const event of parsed.events) {
      switch (event.type) {
        case "meta":
          board = event.board;
          break;
        case "issues":
          for (const i of event.issues) acc.set(i.id, i);
          commit();
          break;
        case "statuses": {
          const patched = applyStatusOverrides([...acc.values()], event.overrides);
          for (const i of patched) acc.set(i.id, i);
          commit();
          break;
        }
        case "done":
          sawDone = true;
          break;
        case "error":
          throw new Error(`workstream feed error: ${event.code}`);
      }
    }
    if (sawDone) break;
  }
  if (!sawDone) {
    throw new Error(`workstream feed ended before done: ${url}`);
  }
  return { issues: [...acc.values()], board };
}
