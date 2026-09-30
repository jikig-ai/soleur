// Progressive Workstream issues feed — frame vocabulary + pure helpers, plus
// the client fetcher that consumes `GET /api/workstream/issues` negotiated as
// `text/event-stream`. Client-safe leaf: imports types from `./workstream`
// only (same layering rule as lib/support-sse.ts — no React, no components/,
// no server-only imports).
//
// Frame semantics are DELTA (each frame carries only new information — the
// cumulative-vs-delta ambiguity produced duplicated output in 2026-04-13's
// websocket fix): one `issues` frame per upstream GitHub REST page, upserted
// by id; board-precedence reconciles arrive as plain `issues` frames carrying
// the full re-mapped card once the Project Status map lands (ADR-097) — the
// upsert is already whole-object, so no second frame type exists; `done`/
// `error` are terminal. A stream that ends without `done` is a TRUNCATED feed
// and must surface as an error — never as a silently-complete board.

import type {
  WorkstreamBoardMeta,
  WorkstreamIssue,
} from "./workstream";

export type WorkstreamFeedEvent =
  | { type: "meta"; board: WorkstreamBoardMeta }
  | { type: "issues"; issues: WorkstreamIssue[] }
  | { type: "done"; openTruncated: boolean }
  | { type: "error"; code: string };

/** The response shape every fetcher on this key resolves — identical to the
 *  bulk JSON arm so write-path reconcilers and the nav badge are untouched.
 *  `openTruncated` is additive-only: only the SSE arm can observe the upstream
 *  open-page cap mid-feed (the bulk arm had nowhere to surface it). */
export interface WorkstreamIssuesResponse {
  issues: WorkstreamIssue[];
  board?: WorkstreamBoardMeta;
  openTruncated?: boolean;
  /** Set on mid-stream commits only — subscribers (the nav badge) hold their
   *  last complete snapshot rather than render a streamed-subset count. */
  partial?: boolean;
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

// ---------------------------------------------------------------------------
// Locally-pending ids. SWR's mutation-overlap rule discards the fetcher's
// resolved value whenever a `scopedMutate` landed mid-fetch — i.e. on EVERY
// progressive feed — so the cache keeps the last committed product. Mid-stream
// commits merge (preserving optimistic `SOLAA-N*` temps and any locally-edited
// card); the `done` commit is AUTHORITATIVE — it prunes anything the feed never
// emitted (upstream deletes, done-column churn) EXCEPT ids the local write
// paths marked pending: a create ack'd mid-feed whose upstream page already
// passed would otherwise vanish until the next refresh.
// ---------------------------------------------------------------------------

// Marks carry the feed epoch they were written in. A mark from an OLDER feed
// is expired at the next feed's `done` — by then every upstream page was
// re-fetched, so an id that never emitted is a ghost (e.g. a locally-created
// issue deleted upstream) and must not be preserved forever.
let feedEpoch = 0;
const pendingRealIds = new Map<string, number>();

/** Write paths call this after a real-id write lands locally (create ack, and
 *  every PATCH reconcile — the reconcile writes the canonical copy into the
 *  cache and the authoritative `done` commit must not overwrite it with a
 *  pre-write streamed copy from an earlier page). A later frame emitting the
 *  id clears the mark automatically. */
export function markLocallyWrittenIssueId(id: string): void {
  pendingRealIds.set(id, feedEpoch);
}

/** Drop a pending mark — e.g. the write path rolled back after an ack. */
export function unmarkLocallyWrittenIssueId(id: string): void {
  pendingRealIds.delete(id);
}

// In-flight optimistic writes: a streamed copy fetched BEFORE the write
// landed upstream must not snap the user's card back. The window is small
// (optimistic mutate → PATCH ack/rollback), so mark at write start and clear
// in a finally — these ids are never cleared by frame emits.
const inflightWriteIds = new Set<string>();

/** Write paths call this at optimistic-mutate start (patch/delete). */
export function markInflightWriteId(id: string): void {
  inflightWriteIds.add(id);
}

/** Clear on ack OR rollback — the reconcile writes the canonical copy. */
export function clearInflightWriteId(id: string): void {
  inflightWriteIds.delete(id);
}

/** True when the id is a real GitHub issue number — optimistic `SOLAA-N*`
 *  temp cards return false (they are always "pending"). */
function isRealIssueId(id: string): boolean {
  const n = Number(id);
  return Number.isInteger(n) && n > 0;
}

/**
 * Merge one progressive commit into the cached response. Upsert-by-id over the
 * current set: streamed copies replace same-id entries, and entries the stream
 * has not emitted yet are KEPT — what preserves optimistic `SOLAA-N*` temps
 * and locally-written cards across mid-stream commits.
 */
export function mergeStreamedIssues(
  current: WorkstreamIssuesResponse | undefined,
  partial: WorkstreamIssuesResponse,
): WorkstreamIssuesResponse {
  const merged = new Map<string, WorkstreamIssue>();
  for (const i of current?.issues ?? []) merged.set(i.id, i);
  for (const i of partial.issues) {
    // A pre-write fetched copy must not snap an in-flight optimistic write back.
    if (!inflightWriteIds.has(i.id)) merged.set(i.id, i);
  }
  return {
    issues: [...merged.values()],
    board: partial.board ?? current?.board,
    // Carry the truncation flag forward — dropping it mid-feed would flicker
    // the under-count banner off until `done`.
    openTruncated: current?.openTruncated,
    partial: true,
  };
}

/**
 * The AUTHORITATIVE commit for `done` (and the fetcher's resolved value): the
 * streamed accumulator IS the canonical set — entries the feed never emitted
 * are pruned — except locally-pending ids (non-numeric `SOLAA-N*` temps plus
 * `markLocallyWrittenIssueId` marks), which are real writes upstream hasn't
 * reflected back yet. This is what makes the final committed payload
 * byte-shape-identical to the bulk response (AC4) under SWR's mutation
 * discard: the resolve never lands, so the last committed product must be
 * exactly what the resolve would have written.
 */
export function mergeFinalIssues(
  current: WorkstreamIssuesResponse | undefined,
  partial: WorkstreamIssuesResponse,
): WorkstreamIssuesResponse {
  const keep = (i: WorkstreamIssue) =>
    !isRealIssueId(i.id) ||
    (pendingRealIds.get(i.id) ?? -1) >= feedEpoch ||
    inflightWriteIds.has(i.id);
  // Dedupe by id — a create ack racing a streamed emission of the real id can
  // otherwise produce two same-id entries in the authoritative commit.
  const pending = [
    ...new Map(
      (current?.issues ?? []).filter(keep).map((i) => [i.id, i]),
    ).values(),
  ];
  const pendingIds = new Set(pending.map((i) => i.id));
  // pending wins over a same-id streamed copy (the local write is newer than
  // anything a racing frame could have fetched).
  return {
    issues: [...pending, ...partial.issues.filter((i) => !pendingIds.has(i.id))],
    board: partial.board ?? current?.board,
    openTruncated: partial.openTruncated,
  };
}

// Client-side stall watchdog — the server's ~90 s cap closes a wedged stream,
// but a half-open transport (mobile blip, proxy dead) never delivers the close,
// leaving `isValidating` spinning indefinitely. use-support-chat's idle timer
// is the in-repo precedent. 60 s (not less): a single wedged upstream page can
// legitimately take ~48 s (15 s timeout × 3 attempts + backoff), and the server
// emits `: ka` keepalives every 15 s — a real stream never stays silent this
// long, so the watchdog only bites on genuinely dead transports.
const FEED_STALL_MS = 60_000;

/**
 * The board's SWR fetcher: negotiate the SSE arm, commit each `issues` frame
 * via `onPartial(partial, false)` while the stream is open, commit the
 * authoritative canonical set via `onPartial(partial, true)` at `done`, and
 * resolve the SAME `{issues, board}` object the JSON arm returns.
 *
 * Terminal rules (P4 — a truncated feed is never a silent success):
 *   - `!res.ok` → throw (jsonFetcher parity; SWR records `error`).
 *   - non-SSE content-type (older deploy / buffering proxy) → `res.json()`.
 *   - `error` frame, a >45 s stall, OR the body ending without `done` → throw;
 *     progressive commits already applied surface as the existing
 *     `error && data` banner.
 */
export async function fetchWorkstreamIssuesFeed(
  key: readonly [string, ...unknown[]] | string,
  onPartial?: (partial: WorkstreamIssuesResponse, final: boolean) => void,
  opts?: { stallMs?: number },
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

  feedEpoch += 1; // marks written during this run expire NEXT feed if unemitted
  const stallMs = opts?.stallMs ?? FEED_STALL_MS;
  const acc = new Map<string, WorkstreamIssue>();
  let board: WorkstreamBoardMeta | undefined;
  let final: WorkstreamIssuesResponse | undefined;

  // Skip commits until at least one real issue has streamed — an early
  // meta-only commit would flash a false EmptyState under the skeleton.
  const commit = () => {
    if (acc.size === 0) return;
    onPartial?.({ issues: [...acc.values()], board }, false);
  };

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  const readWithStall = (): Promise<ReadableStreamReadResult<Uint8Array>> => {
    let t: ReturnType<typeof setTimeout> | undefined;
    const stall = new Promise<never>((_, reject) => {
      t = setTimeout(
        () => reject(new Error(`workstream feed stalled >${stallMs}ms`)),
        stallMs,
      );
    });
    return Promise.race([reader.read(), stall]).finally(() =>
      clearTimeout(t),
    );
  };

  let buf = "";
  try {
    for (;;) {
      const { done, value } = await readWithStall();
      if (done) break;
      buf += decoder.decode(value, { stream: true });
      const parsed = parseWorkstreamSseChunks(buf);
      buf = parsed.rest;
      let doneEvent: Extract<WorkstreamFeedEvent, { type: "done" }> | undefined;
      for (const event of parsed.events) {
        switch (event.type) {
          case "meta":
            board = event.board;
            break;
          case "issues":
            for (const i of event.issues) {
              acc.set(i.id, i);
              pendingRealIds.delete(i.id); // the feed confirmed this id
            }
            commit();
            break;
          case "done":
            doneEvent = event;
            break;
          case "error":
            throw new Error(`workstream feed error: ${event.code}`);
        }
      }
      if (doneEvent) {
        final = {
          issues: [...acc.values()],
          board,
          openTruncated: doneEvent.openTruncated,
        };
        // Authoritative commit: prunes ghosts, keeps locally-pending writes.
        onPartial?.(final, true);
        break;
      }
    }
  } catch (err) {
    try {
      await reader.cancel();
    } catch {
      // reader already released
    }
    throw err;
  }
  if (!final) {
    throw new Error(`workstream feed ended before done: ${url}`);
  }
  return final;
}
