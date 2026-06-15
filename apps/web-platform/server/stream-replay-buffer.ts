// feat-stream-since-disconnect (#5273) — in-memory, per-conversation ring
// buffer that captures every server→client WS frame in the buffered family as
// it is emitted, tagged with a monotonic per-conversation `seq`. On a
// within-grace reconnect the client sends the last `seq` it rendered (an ack
// cursor) and the server replays `seq > ackSeq`, then live streaming resumes.
//
// Lifecycle discipline mirrors `TtlDedupMap` (`observability.ts:413-458`):
// bounded (per-conversation ring cap + per-buffer byte cap + global
// map-cardinality cap), TTL-swept via amortized sweep-on-write (NO new timer),
// oldest-eviction, class-based, process-local, with a `reset()` test seam.
// Justified by the single-backend-instance topology (a reconnect always lands
// on the same process). Extends AP-013 → ADR-027; see ADR-059.
//
// This module is PURE — no Sentry/pino I/O in the class. The caller wires an
// `onEvict` callback (the singleton below mirrors buffer-overflow to Sentry).

import type { WSMessage } from "@/lib/types";
import { mirrorWithDebounce } from "@/server/observability";

// The buffered streaming family — "frames the client re-applies on replay".
// NOT `error` (a replayed error could re-fire a toast and durably widens the
// blast radius of any unsanitized diagnostic field; see ADR-059 / plan Risks).
// Also excluded: `command_stream` / `debug_event` — these carry their own
// phase/append state machine and large (byte-capped) payloads, and are render-
// only/ephemeral; replaying them is out of scope for v1 (a reconnect mid-Bash-
// stream falls back to the honest history refetch).
export type BufferedWSMessage = Extract<
  WSMessage,
  | { type: "stream_start" }
  | { type: "stream" }
  | { type: "stream_end" }
  | { type: "tool_use" }
  | { type: "tool_progress" }
  | { type: "usage_update" }
  | { type: "session_ended" }
  // feat-reasoning-chat-boxes (#5370) — the DURABLE per-turn summary IS buffered
  // (unlike `reasoning_narration`, which stays live-only like debug_event): it
  // must survive a within-grace reconnect replay so the confirmed box does not
  // vanish mid-turn. Persistence (messages row) covers the reload case; buffering
  // covers the reconnect case.
  | { type: "turn_summary" }
>;

// Derived from a `Record<BufferedWSMessage["type"], true>` (NOT a bare array)
// so the buffered-type Set is EXACTLY `BufferedWSMessage["type"]` — bidirec-
// tionally compiler-enforced. A bare `satisfies …[]` only proves the Set ⊆ the
// Extract (a member could be silently OMITTED → that frame type never buffered
// → silent replay gap). The Record forces every Extract member present (missing
// key = tsc error) AND forbids extras (excess key = tsc error). When adding a
// new streaming frame to the buffered family: add it to `BufferedWSMessage`,
// this Record, the `seq?` field in lib/types.ts, and `replaySeqSchema` in
// lib/ws-zod-schemas.ts (the last two are kept in lockstep by `_SchemaCovers`).
const BUFFERED_FRAME_TYPE_MAP: Record<BufferedWSMessage["type"], true> = {
  stream_start: true,
  stream: true,
  stream_end: true,
  tool_use: true,
  tool_progress: true,
  usage_update: true,
  session_ended: true,
  turn_summary: true,
};

export const BUFFERED_FRAME_TYPES: ReadonlySet<WSMessage["type"]> = new Set(
  Object.keys(BUFFERED_FRAME_TYPE_MAP) as BufferedWSMessage["type"][],
);

/** True when a wire frame belongs to the buffered family (write-hook gate). */
export function isBufferedFrame(msg: WSMessage): msg is BufferedWSMessage {
  return BUFFERED_FRAME_TYPES.has(msg.type);
}

// Internal frame type: every buffered frame carries a `seq` (the wire type
// keeps `seq?` optional for rolling-deploy back-compat). Making `seq` required
// here is a compiler invariant that eliminates `seq!` non-null assertions.
export type BufferedFrame = BufferedWSMessage & { seq: number };

export type ReplayStatus = "complete" | "incomplete";

export interface ReplayResult {
  frames: BufferedFrame[];
  status: ReplayStatus;
}

export interface EvictInfo {
  conversationId: string;
  /** "ring" / "bytes" = per-conversation cap (active-turn overflow);
   *  "map" = global cardinality LRU eviction of a whole idle buffer. */
  reason: "ring" | "bytes" | "map";
}

export interface StreamReplayBufferOptions {
  /** Per-conversation ring cap (frame count). */
  maxFrames: number;
  /** Global cap on the number of distinct conversation buffers (LRU-evict). */
  maxConversations: number;
  /** Idle-conversation TTL backstop (ms) swept amortized on write. */
  ttlMs: number;
  /** Per-conversation byte cap (a `stream` frame is a large cumulative snapshot). */
  maxBytesPerConversation: number;
  /** Sweep cadence: run the TTL sweep every Nth write. Default 128. */
  sweepInterval?: number;
  /** Caller hook for eviction observability (the class itself does no I/O). */
  onEvict?: (info: EvictInfo) => void;
}

interface RingEntry {
  frame: BufferedFrame;
  size: number;
}

/**
 * Approximate retained size of a frame for the per-buffer byte cap. Sums the
 * lengths of string-valued fields (the size-dominant term — a `stream` frame's
 * cumulative `content` snapshot) plus a fixed overhead for the discriminator /
 * numeric / boolean fields. Deliberately NOT `JSON.stringify().length`: the
 * send path (`sendToClient`) already serializes every frame, and a second full
 * serialization here doubles hot-path CPU super-linearly for cumulative
 * snapshots (perf review #5290). This is a memory-bound heuristic, not an exact
 * wire size — UTF-16 code-unit lengths approximate the retained JS-string cost.
 */
function frameByteSize(frame: BufferedFrame): number {
  let n = 64; // fixed overhead: type discriminator, leaderId, seq, numbers.
  for (const value of Object.values(frame as Record<string, unknown>)) {
    if (typeof value === "string") n += value.length;
  }
  return n;
}

export class StreamReplayBuffer {
  // The ring of buffered frames per conversation. Map insertion order is
  // maintained as LRU recency (delete+reinsert on each stamp) so the global
  // map-cardinality cap evicts the least-recently-active whole buffer.
  private readonly rings = new Map<string, RingEntry[]>();
  // Running byte total per conversation (avoids O(n) recompute per stamp).
  private readonly byteTotals = new Map<string, number>();
  // The monotonic `nextSeq` per conversation. OUTLIVES `clear` (turn-end /
  // abort / grace) so a resumed conversation never rewinds and a stale prior
  // cursor can never match a fresh frame. Reclaimed only by map-evict, TTL
  // sweep, or `clearAll` — all of which imply any resume is `incomplete` →
  // honest history refetch → the client resets its cursor anyway.
  private readonly counters = new Map<string, number>();
  private readonly lastActivity = new Map<string, number>();
  private writeCount = 0;

  private readonly maxFrames: number;
  private readonly maxConversations: number;
  private readonly ttlMs: number;
  private readonly maxBytes: number;
  private readonly sweepInterval: number;
  private readonly onEvict?: (info: EvictInfo) => void;

  constructor(opts: StreamReplayBufferOptions) {
    this.maxFrames = opts.maxFrames;
    this.maxConversations = opts.maxConversations;
    this.ttlMs = opts.ttlMs;
    this.maxBytes = opts.maxBytesPerConversation;
    this.sweepInterval = opts.sweepInterval ?? 128;
    this.onEvict = opts.onEvict;
  }

  /**
   * Assign the next `seq` to `msg` (mutating it — the caller JSON.stringifies
   * the same object immediately after), append it to the conversation's ring,
   * and enforce the ring / byte / map caps. Returns the same object narrowed to
   * `BufferedFrame`.
   */
  stamp(
    conversationId: string,
    msg: BufferedWSMessage,
    now: number = Date.now(),
  ): BufferedFrame {
    const seq = this.counters.get(conversationId) ?? 0;
    this.counters.set(conversationId, seq + 1);
    const frame = msg as BufferedFrame;
    frame.seq = seq;
    const size = frameByteSize(frame);

    // Maintain LRU recency: pull the existing ring (if any) and re-insert at
    // the end so Map iteration order tracks recency.
    let ring = this.rings.get(conversationId);
    if (ring !== undefined) {
      this.rings.delete(conversationId);
    } else {
      // New conversation — enforce the global cardinality cap BEFORE insert.
      this.evictMapIfNeeded(conversationId);
      ring = [];
    }
    ring.push({ frame, size });
    this.rings.set(conversationId, ring);
    this.lastActivity.set(conversationId, now);
    let total = (this.byteTotals.get(conversationId) ?? 0) + size;

    // Per-conversation ring cap (frame count).
    while (ring.length > this.maxFrames) {
      const removed = ring.shift();
      if (removed) {
        total -= removed.size;
        this.onEvict?.({ conversationId, reason: "ring" });
      }
    }
    // Per-buffer byte cap. Always retain at least the newest frame.
    while (total > this.maxBytes && ring.length > 1) {
      const removed = ring.shift();
      if (removed) {
        total -= removed.size;
        this.onEvict?.({ conversationId, reason: "bytes" });
      }
    }
    this.byteTotals.set(conversationId, total);

    this.maybeSweep(now);
    return frame;
  }

  /**
   * Frames with `seq > ackSeq`, in emission order. `status` is `incomplete`
   * when the conversation has no buffer entry (cleared / evicted / never seen)
   * OR the cursor is older than the oldest buffered frame (a gap was evicted) —
   * in either case the caller emits `stream_replay{incomplete}` and the client
   * falls back to the v1 honest history refetch. The returned `frames` are
   * still populated on `incomplete` (the caller ignores them) so this stays a
   * pure data accessor.
   */
  replayFrom(conversationId: string, ackSeq: number): ReplayResult {
    const ring = this.rings.get(conversationId);
    if (ring === undefined) return { frames: [], status: "incomplete" };
    if (ring.length === 0) return { frames: [], status: "complete" };
    const oldestSeq = ring[0].frame.seq;
    // `ackSeq` is the last seq the client RENDERED, so the next frame it needs
    // is `ackSeq + 1`. Completeness requires that frame to still be buffered:
    // `ackSeq + 1 >= oldestSeq`, i.e. `ackSeq >= oldestSeq - 1`. A smaller
    // `ackSeq` means frames between the cursor and the oldest retained frame
    // were evicted → a gap → `incomplete`. Load-bearing off-by-one; do not
    // "simplify" the `- 1` away.
    const status: ReplayStatus =
      ackSeq < oldestSeq - 1 ? "incomplete" : "complete";
    const frames = ring
      .filter((e) => e.frame.seq > ackSeq)
      .map((e) => e.frame);
    return { frames, status };
  }

  /** Turn-start: clear the frame ring but KEEP the seq counter. */
  resetTurn(conversationId: string, now: number = Date.now()): void {
    const ring = this.rings.get(conversationId);
    if (ring !== undefined) {
      ring.length = 0;
    } else {
      // New conversation — enforce the global cardinality cap BEFORE insert,
      // mirroring `stamp` (a burst of turn-starts that emit few/no frames must
      // not grow the map past `maxConversations` until the next TTL sweep).
      this.evictMapIfNeeded(conversationId);
      this.rings.set(conversationId, []);
    }
    this.byteTotals.set(conversationId, 0);
    this.lastActivity.set(conversationId, now);
  }

  /**
   * Turn-end / abort / grace-expiry / close: drop the frames + byte/activity
   * bookkeeping but PRESERVE the seq counter so a resume never rewinds. After
   * `clear`, a resume returns `incomplete` (frames gone) → honest fallback.
   */
  clear(conversationId: string): void {
    this.rings.delete(conversationId);
    this.byteTotals.delete(conversationId);
    this.lastActivity.delete(conversationId);
    // counters intentionally retained.
  }

  /** SIGTERM drain: drop everything, counters included. */
  clearAll(): void {
    this.rings.clear();
    this.byteTotals.clear();
    this.lastActivity.clear();
    this.counters.clear();
    this.writeCount = 0;
  }

  /** Test seam — alias of {@link clearAll}. */
  reset(): void {
    this.clearAll();
  }

  /** Whole-conversation reclamation (map-evict / TTL sweep): drops counters too. */
  private dropConversation(conversationId: string): void {
    this.rings.delete(conversationId);
    this.byteTotals.delete(conversationId);
    this.lastActivity.delete(conversationId);
    this.counters.delete(conversationId);
  }

  private evictMapIfNeeded(incomingId: string): void {
    if (this.rings.size < this.maxConversations) return;
    // Map insertion order = LRU; the first key is the least-recently-active.
    const oldest = this.rings.keys().next().value;
    if (oldest !== undefined && oldest !== incomingId) {
      this.dropConversation(oldest);
      this.onEvict?.({ conversationId: oldest, reason: "map" });
    }
  }

  private maybeSweep(now: number): void {
    this.writeCount++;
    if (this.sweepInterval <= 0) return;
    if (this.writeCount % this.sweepInterval !== 0) return;
    for (const [cid, ts] of this.lastActivity) {
      if (now - ts > this.ttlMs) this.dropConversation(cid);
    }
  }

  /** Test/diagnostic: current number of distinct conversation buffers. */
  get conversationCount(): number {
    return this.rings.size;
  }
}

// ---------------------------------------------------------------------------
// Process-local singleton. Defaults are safe in-code values; an operator may
// override via env (documented in .env.example) — no Doppler provisioning
// required. The `onEvict` hook mirrors active-turn ring/byte overflow to
// Sentry (debounced) so a too-low cap surfaces without SSH.
// ---------------------------------------------------------------------------

function intFromEnv(name: string, fallback: number): number {
  const raw = process.env[name];
  if (raw === undefined) return fallback;
  const n = Number.parseInt(raw, 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

// Default TTL = DISCONNECT_GRACE_MS (the 30s grace constant in ws-handler) +
// a 15s margin. Hardcoded (not imported from ws-handler) to avoid a
// ws-handler → buffer import cycle; kept in sync by intent, not by reference.
const DEFAULT_TTL_MS = 45_000;

export const streamReplayBuffer = new StreamReplayBuffer({
  maxFrames: intFromEnv("STREAM_REPLAY_BUFFER_MAX_FRAMES", 2000),
  maxConversations: intFromEnv("STREAM_REPLAY_BUFFER_MAX_CONVERSATIONS", 500),
  ttlMs: intFromEnv("STREAM_REPLAY_BUFFER_TTL_MS", DEFAULT_TTL_MS),
  // ~1 MB per conversation — a generous bound on cumulative `stream` snapshots.
  maxBytesPerConversation: intFromEnv(
    "STREAM_REPLAY_BUFFER_MAX_BYTES",
    1_000_000,
  ),
  onEvict: (info) => {
    // Ring/byte eviction at stamp time = overflow during an active turn → a
    // cap is too low for this turn's volume. Map eviction = idle reclamation
    // (expected under cardinality pressure); do not page on it.
    if (info.reason === "map") return;
    mirrorWithDebounce(
      new Error(
        `stream-replay buffer overflow (${info.reason}) — cap too low for active turn`,
      ),
      {
        feature: "stream-replay",
        op: "buffer-overflow",
        extra: { conversationId: info.conversationId, reason: info.reason },
      },
      info.conversationId,
      `stream-replay-overflow-${info.reason}`,
    );
  },
});
