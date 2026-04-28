import { describe, test, expect } from "vitest";
import { applyStreamEvent, type ChatMessage } from "../lib/chat-state-machine";
import type { WSMessage } from "../lib/types";
import type { DomainLeaderId } from "../server/domain-leaders";

type StreamEvent = Parameters<typeof applyStreamEvent>[2];

/**
 * Verifies the reconnect-cleanup contract for #2135. The hook's `connect()`
 * callback clears `activeStreamsRef` and all pending timeout timers before
 * handing off to a fresh WebSocket, so events on the new socket cannot mutate
 * indices computed against the pre-disconnect message array.
 *
 * We exercise the contract at the state-machine boundary rather than simulate
 * a full WS connection: the cleanup logic is "empty the map, clear timers" —
 * we assert that, after a simulated cleanup, the reducer starts fresh even
 * when driven by an event that references a pre-disconnect leader.
 */
describe("WS reconnect cleanup (#2135)", () => {
  test("after cleanup, a stream_start begins a fresh bubble for the same leader", () => {
    // Pre-disconnect: leader 'cmo' has an in-flight stream.
    let messages: ChatMessage[] = [];
    let activeStreams = new Map<DomainLeaderId, number>();
    const s1 = applyStreamEvent(messages, activeStreams, {
      type: "stream_start",
      leaderId: "cmo",
    } as WSMessage as StreamEvent);
    messages = s1.messages;
    activeStreams = s1.activeStreams;
    const s2 = applyStreamEvent(messages, activeStreams, {
      type: "stream",
      content: "partial",
      partial: true,
      leaderId: "cmo",
    } as WSMessage as StreamEvent);
    messages = s2.messages;
    activeStreams = s2.activeStreams;
    expect(activeStreams.size).toBe(1);

    // Simulate reconnect cleanup: the hook clears its activeStreamsRef and
    // timeoutTimersRef at the top of connect().
    activeStreams = new Map<DomainLeaderId, number>();

    // After cleanup, a new stream_start for 'cmo' must produce a NEW bubble
    // rather than mutate the pre-disconnect bubble at index 0.
    const s3 = applyStreamEvent(messages, activeStreams, {
      type: "stream_start",
      leaderId: "cmo",
    } as WSMessage as StreamEvent);

    expect(s3.messages).toHaveLength(2);
    expect(s3.messages[0].content).toBe("partial"); // pre-disconnect bubble preserved
    expect(s3.messages[1].state).toBe("thinking"); // new bubble is fresh
    expect(s3.activeStreams.get("cmo")).toBe(1); // points to the NEW index
  });

  test("stale event after cleanup targeting a missing stream is a no-op", () => {
    // Simulates an in-flight onmessage handler that beats the cleanup to the
    // event loop. With activeStreams cleared, tool_use for an absent leader
    // must not mutate the array (no silent index mutation).
    const messages: ChatMessage[] = [
      {
        id: "stream-cmo-x",
        role: "assistant",
        content: "stale",
        type: "text",
        state: "streaming",
      },
    ];
    const activeStreams = new Map<DomainLeaderId, number>();

    const result = applyStreamEvent(messages, activeStreams, {
      type: "tool_use",
      leaderId: "cmo",
      label: "Reading file...",
    } as WSMessage as StreamEvent);

    expect(result.messages).toEqual(messages);
    expect(result.activeStreams.size).toBe(0);
  });
});
