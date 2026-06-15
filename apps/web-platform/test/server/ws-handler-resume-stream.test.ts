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
      // resume_stream's conversation lookup uses .maybeSingle() (zero rows ⇒
      // {data:null,error:null}); the legacy resume_session path uses .single().
      // Both terminate the same chain → the shared singleSpy.
      select: () => ({
        eq: () => ({ eq: () => ({ single: singleSpy, maybeSingle: singleSpy }) }),
      }),
    }),
    rpc: vi.fn(async () => ({ error: null })),
  };
  return {
    getFreshTenantClient: vi.fn(async () => tenantClient),
    getMyRevocationStatus: vi.fn(async () => null),
    RuntimeAuthError,
  };
});

// Spy the severity helpers without clobbering the rest of observability (the
// module graph below transitively imports other exports). reportSilentFallback
// = error level; warnSilentFallback = warning level — asserting WHICH helper
// fired encodes the severity contract.
vi.mock("@/server/observability", async (importActual) => {
  const actual = await importActual<typeof import("@/server/observability")>();
  return {
    ...actual,
    reportSilentFallback: vi.fn(),
    warnSilentFallback: vi.fn(),
  };
});

import {
  handleMessage,
  sendToClient,
  sessions,
  type ClientSession,
} from "@/server/ws-handler";
import { streamReplayBuffer } from "@/server/stream-replay-buffer";
import {
  setActiveTurnConversation,
  __test_only__ as registryTestOnly,
} from "@/server/agent-session-registry";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { getCurrentRepoUrl } from "@/server/current-repo-url";
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

describe("ws-handler resume_stream — severity-by-cause (#5290 false-positive fix)", () => {
  beforeEach(() => {
    singleSpy.mockClear();
    streamReplayBuffer.reset();
    vi.mocked(reportSilentFallback).mockClear();
    vi.mocked(warnSilentFallback).mockClear();
    // Default: owner-verified conv + resolvable repo (overridden per-test).
    singleSpy.mockResolvedValue({
      data: { id: CONV_ID, repo_url: REPO_URL },
      error: null,
    });
    vi.mocked(getCurrentRepoUrl).mockResolvedValue(REPO_URL);
  });
  afterEach(() => {
    sessions.delete(USER_ID);
    streamReplayBuffer.reset();
    vi.mocked(getCurrentRepoUrl).mockResolvedValue(REPO_URL);
  });

  function streamFeatureCalls(
    spy: typeof reportSilentFallback | typeof warnSilentFallback,
  ): Array<Record<string, unknown>> {
    return vi
      .mocked(spy)
      .mock.calls.map((c) => c[1] as unknown as Record<string, unknown>)
      .filter((opts) => opts.feature === "stream-replay");
  }

  it("transient currentRepoUrl null → NO handler mirror (upstream owns detection), fallback sent", async () => {
    vi.mocked(getCurrentRepoUrl).mockResolvedValueOnce(null);
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );

    // No double-emit: neither severity helper fires a stream-replay mirror.
    expect(streamFeatureCalls(reportSilentFallback)).toHaveLength(0);
    expect(streamFeatureCalls(warnSilentFallback)).toHaveLength(0);
    // Honest fallback still delivered.
    const frames = sentFrames(session);
    expect(
      frames.some(
        (f) => f.type === "stream_replay" && (f as { status: string }).status === "incomplete",
      ),
    ).toBe(true);
    expect(frames.some((f) => f.type === "stream")).toBe(false);
  });

  it("deferred row not-materialized (maybeSingle → null/null) → WARNING ownership-mismatch cause=not-materialized", async () => {
    singleSpy.mockResolvedValueOnce({ data: null as never, error: null });
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );

    // Benign race → WARNING, not error.
    expect(streamFeatureCalls(reportSilentFallback)).toHaveLength(0);
    const warns = streamFeatureCalls(warnSilentFallback);
    expect(warns).toHaveLength(1);
    expect(warns[0].op).toBe("ownership-mismatch");
    expect((warns[0].extra as Record<string, unknown>).cause).toBe("not-materialized");
    // Lock the operator-facing string (parallels the db-error message), not just
    // truthiness — a wrong-but-non-empty message must fail.
    expect(warns[0].message).toContain("not found or not owned");
    expect(sentFrames(session).some((f) => f.type === "stream_replay")).toBe(true);
  });

  it("genuine DB/transport error → ERROR ownership-mismatch cause=db-error (stays loud, pg_code forwarded)", async () => {
    // A coded error (here 42501) exercises pg_code forwarding. NOTE: an RLS
    // row-denial does NOT actually reach this branch — RLS filters to zero rows
    // (→ the not-materialized warning branch); this asserts the error-class
    // handling + that the SQLSTATE-carrying object is forwarded for the pg_code tag.
    const dbErr = Object.assign(new Error("connection terminated"), { code: "42501" });
    singleSpy.mockResolvedValueOnce({ data: null as never, error: dbErr });
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );

    expect(streamFeatureCalls(warnSilentFallback)).toHaveLength(0);
    const errs = streamFeatureCalls(reportSilentFallback);
    expect(errs).toHaveLength(1);
    expect(errs[0].op).toBe("ownership-mismatch");
    expect((errs[0].extra as Record<string, unknown>).cause).toBe("db-error");
    // The SQLSTATE-carrying error object is forwarded so the helper's pg_code
    // tag stays queryable.
    expect(vi.mocked(reportSilentFallback).mock.calls[0][0]).toBe(dbErr);
  });

  it("genuine cross-repo mismatch (both URLs non-null, differ) → ERROR repo-scope-mismatch cause=url-differs", async () => {
    singleSpy.mockResolvedValueOnce({
      data: { id: CONV_ID, repo_url: "https://github.com/other/repo.git" },
      error: null,
    });
    vi.mocked(getCurrentRepoUrl).mockResolvedValueOnce(REPO_URL);
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID }),
    );

    expect(streamFeatureCalls(warnSilentFallback)).toHaveLength(0);
    const errs = streamFeatureCalls(reportSilentFallback);
    expect(errs).toHaveLength(1);
    expect(errs[0].op).toBe("repo-scope-mismatch");
    expect((errs[0].extra as Record<string, unknown>).cause).toBe("url-differs");
  });

  it("owner-verified + repo match → replays, NO mirror of either severity", async () => {
    stamp("a"); // seq 0
    const session = makeSession(CONV_ID);
    sessions.set(USER_ID, session);

    await handleMessage(
      USER_ID,
      JSON.stringify({ type: "resume_stream", conversationId: CONV_ID, ackSeq: -1 }),
    );

    expect(streamFeatureCalls(reportSilentFallback)).toHaveLength(0);
    expect(streamFeatureCalls(warnSilentFallback)).toHaveLength(0);
    expect(sentFrames(session).some((f) => f.type === "stream")).toBe(true);
  });
});

describe("ws-handler sendToClient write-hook keying (#5273)", () => {
  beforeEach(() => {
    streamReplayBuffer.reset();
    registryTestOnly.clear();
  });
  afterEach(() => {
    sessions.delete(USER_ID);
    streamReplayBuffer.reset();
    registryTestOnly.clear();
  });

  it("buffers a conversationId-less frame during the grace gap via the active-turn binding (cc-path: no session, no registerSession)", () => {
    // Simulate the disconnect grace window: session deleted, but the active-turn
    // binding survives (set by the cc dispatch path). A streaming frame carries
    // no wire conversationId — without the binding it would be dropped.
    setActiveTurnConversation(USER_ID, CONV_ID);
    expect(sessions.has(USER_ID)).toBe(false); // gap: no session

    sendToClient(USER_ID, {
      type: "stream",
      content: "gap-frame",
      partial: true,
      leaderId: "cc_router",
    });

    const { frames, status } = streamReplayBuffer.replayFrom(CONV_ID, -1);
    expect(status).toBe("complete");
    expect(frames.map((f) => (f as { content?: string }).content)).toEqual([
      "gap-frame",
    ]);
  });

  it("prefers the active-turn binding over a stale session.conversationId for a frame lacking conversationId", () => {
    // Backgrounded conv-A frame must not land in conv-B's buffer: the binding
    // (the active turn) wins over the socket's currently-bound conversation.
    setActiveTurnConversation(USER_ID, "conv-A");
    sessions.set(USER_ID, makeSession("conv-B"));

    sendToClient(USER_ID, {
      type: "stream",
      content: "for-A",
      partial: true,
      leaderId: "cto",
    });

    expect(streamReplayBuffer.replayFrom("conv-A", -1).frames.length).toBe(1);
    expect(streamReplayBuffer.replayFrom("conv-B", -1).status).toBe("incomplete");
  });

  it("does not re-stamp an already-seq'd replayed frame (no ring duplication)", () => {
    setActiveTurnConversation(USER_ID, CONV_ID);
    sessions.set(USER_ID, makeSession(CONV_ID));
    // First emit (live) → stamped seq 0.
    sendToClient(USER_ID, { type: "stream", content: "x", partial: true, leaderId: "cto" });
    const before = streamReplayBuffer.replayFrom(CONV_ID, -1).frames.length;
    // Re-emit the SAME buffered frame (carries seq) as the replay handler would.
    const replayed = streamReplayBuffer.replayFrom(CONV_ID, -1).frames[0];
    sendToClient(USER_ID, replayed);
    const after = streamReplayBuffer.replayFrom(CONV_ID, -1).frames.length;
    expect(after).toBe(before); // not appended again
  });
});
