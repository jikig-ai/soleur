// feat-stream-since-disconnect (#5273) — unit tests for the in-memory
// per-conversation replay buffer. The buffer is the testable core of the
// feature; integration of the write hook + reattach handler is covered by the
// ws-handler suite. Mirrors `TtlDedupMap` lifecycle discipline (ADR-059).
//
// Run: cd apps/web-platform && ./node_modules/.bin/vitest run test/server/stream-replay-buffer.test.ts

import { describe, it, expect, vi } from "vitest";
import {
  StreamReplayBuffer,
  type BufferedFrame,
} from "@/server/stream-replay-buffer";
import type { WSMessage } from "@/lib/types";

// A small streaming frame (well under any byte cap).
function streamFrame(content = "hi"): Extract<WSMessage, { type: "stream" }> {
  return { type: "stream", content, partial: true, leaderId: "cto" };
}

function newBuffer(
  overrides: Partial<{
    maxFrames: number;
    maxConversations: number;
    ttlMs: number;
    maxBytesPerConversation: number;
    sweepInterval: number;
    onEvict: (info: { conversationId: string; reason: string }) => void;
  }> = {},
) {
  return new StreamReplayBuffer({
    maxFrames: overrides.maxFrames ?? 2000,
    maxConversations: overrides.maxConversations ?? 500,
    ttlMs: overrides.ttlMs ?? 60_000,
    maxBytesPerConversation: overrides.maxBytesPerConversation ?? 1_000_000,
    sweepInterval: overrides.sweepInterval,
    onEvict: overrides.onEvict,
  });
}

describe("StreamReplayBuffer.stamp", () => {
  it("assigns a monotonic seq starting at 0 per conversation", () => {
    const buf = newBuffer();
    const a0 = buf.stamp("conv-a", streamFrame(), 1);
    const a1 = buf.stamp("conv-a", streamFrame(), 2);
    const b0 = buf.stamp("conv-b", streamFrame(), 3);
    expect(a0.seq).toBe(0);
    expect(a1.seq).toBe(1);
    expect(b0.seq).toBe(0); // independent counter per conversation
  });

  it("mutates the passed frame so the serialized object carries seq", () => {
    const buf = newBuffer();
    const msg = streamFrame();
    const stamped = buf.stamp("conv-a", msg, 1);
    // The same object reference is returned with seq assigned (the caller
    // JSON.stringifies it immediately after).
    expect((msg as { seq?: number }).seq).toBe(0);
    expect(stamped).toBe(msg);
  });

  it("evicts the oldest frame when the per-conversation ring cap is exceeded", () => {
    const onEvict = vi.fn();
    const buf = newBuffer({ maxFrames: 3, onEvict });
    for (let i = 0; i < 5; i++) buf.stamp("conv-a", streamFrame(`f${i}`), i + 1);
    const { frames } = buf.replayFrom("conv-a", -1);
    // Ring holds at most 3; oldest two (seq 0,1) evicted.
    expect(frames.map((f) => f.seq)).toEqual([2, 3, 4]);
    expect(onEvict).toHaveBeenCalled();
  });

  it("evicts oldest frames when the per-buffer byte cap is exceeded", () => {
    // Each ~100-byte frame; cap forces eviction down to the newest.
    const big = "x".repeat(100);
    const buf = newBuffer({ maxBytesPerConversation: 250 });
    for (let i = 0; i < 5; i++) buf.stamp("conv-a", streamFrame(big), i + 1);
    const { frames } = buf.replayFrom("conv-a", -1);
    // Byte cap keeps only the newest frames that fit.
    expect(frames.length).toBeLessThan(5);
    expect(frames.length).toBeGreaterThan(0);
    // Newest frame is always retained.
    expect(frames[frames.length - 1].seq).toBe(4);
  });

  it("LRU-evicts the oldest whole conversation buffer at the global map cap", () => {
    const onEvict = vi.fn();
    const buf = newBuffer({ maxConversations: 2, onEvict });
    buf.stamp("conv-a", streamFrame(), 1);
    buf.stamp("conv-b", streamFrame(), 2);
    // Touch conv-a so it becomes most-recently-used; conv-b is now oldest.
    buf.stamp("conv-a", streamFrame(), 3);
    // Adding a third conversation evicts the LRU (conv-b).
    buf.stamp("conv-c", streamFrame(), 4);
    expect(buf.replayFrom("conv-b", -1).status).toBe("incomplete");
    expect(buf.replayFrom("conv-a", -1).status).toBe("complete");
    expect(buf.replayFrom("conv-c", -1).status).toBe("complete");
    expect(onEvict).toHaveBeenCalledWith(
      expect.objectContaining({ conversationId: "conv-b", reason: "map" }),
    );
  });
});

describe("StreamReplayBuffer.replayFrom", () => {
  it("returns frames with seq > ackSeq in order", () => {
    const buf = newBuffer();
    for (let i = 0; i < 5; i++) buf.stamp("conv-a", streamFrame(`f${i}`), i + 1);
    const { frames, status } = buf.replayFrom("conv-a", 2);
    expect(status).toBe("complete");
    expect(frames.map((f) => f.seq)).toEqual([3, 4]);
  });

  it("treats ackSeq=-1 (no prior ack) as the whole buffered tail", () => {
    const buf = newBuffer();
    buf.stamp("conv-a", streamFrame(), 1);
    buf.stamp("conv-a", streamFrame(), 2);
    const { frames, status } = buf.replayFrom("conv-a", -1);
    expect(status).toBe("complete");
    expect(frames.map((f) => f.seq)).toEqual([0, 1]);
  });

  it("returns incomplete when the cursor is older than the oldest buffered frame", () => {
    const buf = newBuffer({ maxFrames: 3 });
    for (let i = 0; i < 6; i++) buf.stamp("conv-a", streamFrame(), i + 1);
    // Oldest retained seq is 3; a client holding ackSeq=0 missed seq 1,2 → gap.
    const { status } = buf.replayFrom("conv-a", 0);
    expect(status).toBe("incomplete");
  });

  it("returns incomplete for a conversation with no buffer entry (cleared/evicted)", () => {
    const buf = newBuffer();
    expect(buf.replayFrom("never-existed", -1).status).toBe("incomplete");
  });

  it("returns complete+empty for an existing-but-empty buffer (turn just started)", () => {
    const buf = newBuffer();
    buf.stamp("conv-a", streamFrame(), 1);
    buf.resetTurn("conv-a");
    const { frames, status } = buf.replayFrom("conv-a", 0);
    expect(status).toBe("complete");
    expect(frames).toEqual([]);
  });
});

describe("StreamReplayBuffer counter lifecycle", () => {
  it("resetTurn clears frames but keeps the seq counter", () => {
    const buf = newBuffer();
    buf.stamp("conv-a", streamFrame(), 1); // seq 0
    buf.stamp("conv-a", streamFrame(), 2); // seq 1
    buf.resetTurn("conv-a");
    const next = buf.stamp("conv-a", streamFrame(), 3);
    expect(next.seq).toBe(2); // continues, does NOT rewind to 0
    expect(buf.replayFrom("conv-a", -1).frames.map((f) => f.seq)).toEqual([2]);
  });

  it("clear removes frames but NOT the counter (resume must not rewind)", () => {
    const buf = newBuffer();
    for (let i = 0; i < 11; i++) buf.stamp("conv-a", streamFrame(), i + 1); // seq 0..10
    buf.clear("conv-a");
    // Frames are gone → a resume now is incomplete (honest fallback).
    expect(buf.replayFrom("conv-a", 5).status).toBe("incomplete");
    // But the counter persists: a NEW frame continues at seq 11, never 0, so a
    // stale prior cursor (lastRenderedSeq=10) can never match a fresh frame.
    const next = buf.stamp("conv-a", streamFrame(), 99);
    expect(next.seq).toBe(11);
  });

  it("resetTurn on a new conversation respects the global map cap (no bypass)", () => {
    const onEvict = vi.fn();
    const buf = newBuffer({ maxConversations: 2, onEvict });
    buf.stamp("conv-a", streamFrame(), 1);
    buf.stamp("conv-b", streamFrame(), 2);
    // resetTurn for a THIRD, never-stamped conversation must evict the LRU
    // (conv-a), not grow the map past the cap.
    buf.resetTurn("conv-c", 3);
    expect(buf.conversationCount).toBeLessThanOrEqual(2);
    expect(onEvict).toHaveBeenCalledWith(
      expect.objectContaining({ reason: "map" }),
    );
  });

  it("clearAll empties every buffer and counter", () => {
    const buf = newBuffer();
    buf.stamp("conv-a", streamFrame(), 1);
    buf.stamp("conv-b", streamFrame(), 2);
    buf.clearAll();
    expect(buf.replayFrom("conv-a", -1).status).toBe("incomplete");
    expect(buf.replayFrom("conv-b", -1).status).toBe("incomplete");
    // After clearAll the counter is reset too → fresh start at 0.
    expect(buf.stamp("conv-a", streamFrame(), 3).seq).toBe(0);
  });
});

describe("StreamReplayBuffer TTL sweep", () => {
  it("sweeps conversations idle past ttlMs on a later write (no timer)", () => {
    const buf = newBuffer({ ttlMs: 1000, sweepInterval: 1 });
    buf.stamp("conv-old", streamFrame(), 1_000);
    // A much later write to a different conversation triggers the amortized
    // sweep; conv-old is now past its TTL and dropped.
    buf.stamp("conv-new", streamFrame(), 10_000);
    expect(buf.replayFrom("conv-old", -1).status).toBe("incomplete");
    expect(buf.replayFrom("conv-new", -1).status).toBe("complete");
  });
});

describe("StreamReplayBuffer replay scenarios (#5273)", () => {
  it("flapping: each reconnect with an advancing ackSeq replays only the new tail", () => {
    const buf = newBuffer();
    for (let i = 0; i < 3; i++) buf.stamp("conv-a", streamFrame(), i + 1); // seq 0,1,2
    // First reconnect: client had rendered seq 0 → gets 1,2.
    expect(buf.replayFrom("conv-a", 0).frames.map((f) => f.seq)).toEqual([1, 2]);
    // More frames arrive, client now at seq 2.
    buf.stamp("conv-a", streamFrame(), 4); // seq 3
    buf.stamp("conv-a", streamFrame(), 5); // seq 4
    // Second reconnect: client at seq 2 → gets only 3,4 (not the whole tail).
    expect(buf.replayFrom("conv-a", 2).frames.map((f) => f.seq)).toEqual([3, 4]);
    // Third reconnect at seq 4 → nothing new, still complete.
    const r = buf.replayFrom("conv-a", 4);
    expect(r.frames).toEqual([]);
    expect(r.status).toBe("complete");
  });

  it("trailing-emit after clear: a frame stamped post-clear re-seeds a buffer at the continued seq", () => {
    const buf = newBuffer();
    for (let i = 0; i < 3; i++) buf.stamp("conv-a", streamFrame(), i + 1); // seq 0,1,2
    buf.clear("conv-a"); // abort/grace teardown — frames gone, counter kept
    // The runner's abort branch emits one trailing frame AFTER clear ran.
    const trailing = buf.stamp("conv-a", streamFrame("aborted"), 9);
    expect(trailing.seq).toBe(3); // counter continued, never rewound to 0
    // A reconnect now sees only the trailing frame (honest: the turn ended).
    expect(buf.replayFrom("conv-a", 2).frames.map((f) => f.seq)).toEqual([3]);
  });

  it("turn-completed-while-gone: a buffered terminal session_ended is replayed", () => {
    const buf = newBuffer();
    buf.stamp("conv-a", streamFrame("partial"), 1); // seq 0
    buf.stamp(
      "conv-a",
      { type: "session_ended", reason: "turn_complete", conversationId: "conv-a" },
      2,
    ); // seq 1
    // User was gone at turn-end; reconnect within grace replays the tail
    // INCLUDING the terminal frame → client renders "ended while you were away".
    const { frames, status } = buf.replayFrom("conv-a", -1);
    expect(status).toBe("complete");
    expect(frames.map((f) => f.type)).toEqual(["stream", "session_ended"]);
  });
});

describe("BufferedFrame type", () => {
  it("requires a numeric seq (compile-time invariant, asserted at runtime)", () => {
    const buf = newBuffer();
    const f: BufferedFrame = buf.stamp("conv-a", streamFrame(), 1);
    expect(typeof f.seq).toBe("number");
  });
});

