/**
 * feat-stream-since-disconnect (#5273) — `resume_stream` reattach + replay.
 *
 * Drives the real `handleMessage` with a `resume_stream` frame against a
 * mocked tenant client + repo-url resolver (same harness as the v1
 * resume-rebind test). Asserts the ownership/repo-scope gate, the verbatim
 * replay of buffered frames, the honest `stream_replay{incomplete}` fallback,
 * the ackSeq clamp, the second-tab guard, and — the spec-flow P0 INVARIANT —
 * that the handler does NOT abort the still-running agent (a live frame emitted
 * after reattach is still delivered + buffered).
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

import { TC_VERSION } from "@/lib/legal/tc-version";

const REPO_URL = "https://github.com/acme/repo.git";
const CONV_ID = "conv-stream-1";
const USER_ID = "user-stream-A";

const { singleSpy } = vi.hoisted(() => ({
  singleSpy: vi.fn(async () => ({
    data: { id: "conv-stream-1", repo_url: "https://github.com/acme/repo.git" },
    error: null as { code: string; message: string } | null,
  })),
}));

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: vi.fn(async () => REPO_URL),
}));

vi.mock("@/lib/supabase/tenant", () => {
  class RuntimeAuthError extends Error {
    cause: string;
    constructor(message: string, cause = "unknown") {
      super(message);
      this.cause = cause;
    }
  }
  const tenantClient = {
    from: () => ({
      select: () => ({ eq: () => ({ eq: () => ({ single: singleSpy }) }) }),
    }),
    rpc: vi.fn(async () => ({ error: null })),
  };
  return {
    getFreshTenantClient: vi.fn(async () => tenantClient),
    getMyRevocationStatus: vi.fn(async () => null),
    RuntimeAuthError,
  };
});

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";
import { streamReplayBuffer } from "@/server/stream-replay-buffer";
import type { WSMessage } from "@/lib/types";

function makeSession(conversationId?: string): ClientSession {
  const ws = {
    readyState: 1, // WebSocket.OPEN
    send: vi.fn(),
    close: vi.fn(),
    // biome-ignore lint/suspicious/noExplicitAny: minimal WS test double
  } as any;
  return {
    ws,
    lastActivity: Date.now(),
    tcVersionAtHandshake: TC_VERSION,
    tcRecheckCacheUntil: Date.now() + 1_000_000,
    conversationId,
  };
}

function sentFrames(session: ClientSession): WSMessage[] {
  const sendMock = session.ws.send as unknown as { mock: { calls: unknown[][] } };
  return sendMock.mock.calls.map((c) => JSON.parse(c[0] as string) as WSMessage);
}

function stamp(content: string): void {
  streamReplayBuffer.stamp(CONV_ID, {
    type: "stream",
    content,
    partial: true,
    leaderId: "cto",
  });
}

describe("ws-handler resume_stream — reattach + replay (#5273)", () => {
  beforeEach(() => {
    singleSpy.mockClear();
    streamReplayBuffer.reset();
  });
  afterEach(() => {
    sessions.delete(USER_ID);
    streamReplayBuffer.reset();
  });

  it("replays buffered frames with seq > ackSeq, verbatim and in order", async () => {
    stamp("a"); // seq 0
    stamp("b"); // seq 1
    stamp("c"); // seq 2
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID, ackSeq: 0 }),
    );

    const streamed = sentFrames(session).filter((f) => f.type === "stream");
    expect(streamed.map((f) => (f as { seq?: number }).seq)).toEqual([1, 2]);
    expect((streamed[0] as { content: string }).content).toBe("b");
    // No stream_replay{incomplete} on the happy path.
    expect(sentFrames(session).some((f) => f.type === "stream_replay")).toBe(false);
  });

  it("INVARIANT — does not abort the live agent: a frame emitted AFTER reattach is delivered + buffered", async () => {
    stamp("a"); // seq 0
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID, ackSeq: -0 }),
    );

    // Simulate the STILL-RUNNING agent emitting a fresh live frame post-reattach.
    const { sendToClient } = await import("@/server/ws-handler");
    sendToClient(USER_ID, { type: "stream", content: "live", partial: true, leaderId: "cto" });

    const streamed = sentFrames(session).filter((f) => f.type === "stream");
    // The replayed "a" (seq 0) AND the post-reattach live frame were delivered;
    // the live frame got a fresh seq (1) from the write-hook (agent not aborted).
    expect((streamed.at(-1) as { content: string }).content).toBe("live");
    expect((streamed.at(-1) as { seq?: number }).seq).toBe(1);
    // No session_ended / error frame — reattach is non-destructive.
    expect(sentFrames(session).some((f) => f.type === "session_ended")).toBe(false);
  });

  it("falls back to stream_replay{incomplete} when the cursor is evicted", async () => {
    // Only the newest frame remains buffered (cursor 0 is older than oldest).
    stamp("a"); // seq 0
    stamp("b"); // seq 1
    streamReplayBuffer.clear(CONV_ID); // simulate grace-expiry teardown
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID, ackSeq: 0 }),
    );

    const frames = sentFrames(session);
    expect(frames.some((f) => f.type === "stream_replay" && (f as { status: string }).status === "incomplete")).toBe(true);
    expect(frames.some((f) => f.type === "stream")).toBe(false);
  });

  it("does NOT replay when the conversation is not owned (ownership gate)", async () => {
    singleSpy.mockResolvedValueOnce({ data: null as never, error: null });
    stamp("a");
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );

    const frames = sentFrames(session);
    expect(frames.some((f) => f.type === "stream")).toBe(false);
    expect(frames.some((f) => f.type === "stream_replay")).toBe(true);
  });

  it("does NOT replay across a repo-scope mismatch (defense in depth)", async () => {
    singleSpy.mockResolvedValueOnce({
      data: { id: CONV_ID, repo_url: "https://github.com/other/repo.git" },
      error: null,
    });
    stamp("a");
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );

    const frames = sentFrames(session);
    expect(frames.some((f) => f.type === "stream")).toBe(false);
    expect(frames.some((f) => f.type === "stream_replay")).toBe(true);
  });

  it("clamps an abusive ackSeq (huge → no over-replay; negative → whole tail)", async () => {
    stamp("a"); // seq 0
    stamp("b"); // seq 1
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    // Huge ackSeq: nothing is newer → no frames, status complete (no fallback).
    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID, ackSeq: 999999 }),
    );
    let frames = sentFrames(session);
    expect(frames.some((f) => f.type === "stream")).toBe(false);
    expect(frames.some((f) => f.type === "stream_replay")).toBe(false);

    // Fresh session, omitted ackSeq → replay whole tail (seq 0,1).
    const session2 = makeSession(CONV_ID);
    sessions.set(USER_ID, session2);
    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );
    frames = sentFrames(session2);
    expect(frames.filter((f) => f.type === "stream").map((f) => (f as { seq?: number }).seq)).toEqual([0, 1]);
  });

  it("does NOT interleave a second tab's different conversation (live-conversation guard)", async () => {
    stamp("a");
    // Socket is bound to a DIFFERENT conversation than the resume_stream target.
    const session = makeSession("conv-OTHER");
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID, ackSeq: -1 }),
    );

    const frames = sentFrames(session);
    expect(frames.some((f) => f.type === "stream")).toBe(false);
    expect(frames.some((f) => f.type === "stream_replay")).toBe(true);
  });
});
