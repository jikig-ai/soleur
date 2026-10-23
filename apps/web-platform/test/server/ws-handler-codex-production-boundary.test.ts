import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type * as ChildProcessModule from "node:child_process";
import { TC_VERSION } from "@/lib/legal/tc-version";
import * as credentials from "@/server/codex-credential-provider";
import * as codexRuntimeModule from "@/server/codex-conversation-runtime";
import { createEngineRegistry } from "@/server/agent-engine-registry";

type SyntheticRpcArgs = Record<string, unknown> & { p_attempt_key?: string };

const fixture = vi.hoisted(() => ({
  userId: "synthetic-codex-user",
  conversationId: "synthetic-codex-conversation",
  workspaceId: "a1b2c3d4-0000-4000-8000-000000000123",
  repoUrl: "https://github.com/example/synthetic-repo.git",
  mode: "api-key" as "api-key" | "managed",
  generation: 0,
  tenantGate: null as Promise<void> | null,
  tenantMintStarted: vi.fn(),
  rpc: vi.fn(async (_name: string, _args?: SyntheticRpcArgs): Promise<{ data: unknown; error: unknown }> => ({ data: null, error: null })),
  rpcStarts: vi.fn((_name: string, _signal?: AbortSignal) => {}),
  from: vi.fn(),
  spawn: vi.fn(() => { throw new Error("Unexpected provider process launch"); }),
  captureException: vi.fn(),
  reportSilentFallback: vi.fn(),
  hashUserId: vi.fn(() => "synthetic-user-hash"),
  sendUserMessage: vi.fn(),
  startAgentSession: vi.fn(),
  dispatchSoleurGo: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    // PostgREST configures abortSignal synchronously and starts fetch only when
    // its thenable is awaited. Keep that ordering observable in timeout tests.
    rpc: (name: string, args?: SyntheticRpcArgs) => {
      let signal: AbortSignal | undefined;
      const builder = {
        abortSignal(value: AbortSignal) { signal = value; return builder; },
        then(onFulfilled: (value: { data: unknown; error: unknown }) => unknown, onRejected: (reason: unknown) => unknown) {
          fixture.rpcStarts(name, signal);
          return fixture.rpc(name, args).then(onFulfilled, onRejected);
        },
      };
      return builder;
    },
    from: fixture.from,
  }),
}));
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => {
    fixture.tenantMintStarted();
    if (fixture.tenantGate) await fixture.tenantGate;
    return { rpc: fixture.rpc, from: fixture.from };
  }),
  getMyRevocationStatus: vi.fn(async () => null),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));
vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: vi.fn(async () => fixture.repoUrl),
}));
vi.mock("@/server/agent-runner", () => ({
  startAgentSession: fixture.startAgentSession,
  sendUserMessage: fixture.sendUserMessage,
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));
vi.mock("@/server/cc-dispatcher", () => ({
  dispatchSoleurGo: fixture.dispatchSoleurGo,
  getCcStartSessionRateLimiter: vi.fn(),
  handleInteractivePromptResponseCase: vi.fn(),
  hasActiveCcQuery: vi.fn(() => false),
  resolveCcBashGate: vi.fn(),
  drainAutonomousDisclosureGates: vi.fn(),
  markConversationAcked: vi.fn(),
  resolveConciergeDocumentContext: vi.fn(),
  closeCcConversation: vi.fn(),
}));
vi.mock("node:child_process", async (importOriginal) => ({
  ...await importOriginal<typeof ChildProcessModule>(),
  spawn: fixture.spawn,
}));
vi.mock("@sentry/nextjs", () => ({ captureException: fixture.captureException }));
vi.mock("@/server/observability", () => ({
  hashUserId: fixture.hashUserId,
  reportSilentFallback: fixture.reportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

// Runtime, deployment registry, adapter factories and dispatch bridge stay real.
import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";

describe("Codex real production handler boundary", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    fixture.mode = "api-key";
    fixture.generation = 0;
    fixture.tenantGate = null;
    fixture.tenantMintStarted.mockReset();
    fixture.rpc.mockReset().mockResolvedValue({ data: null, error: null });
    fixture.rpcStarts.mockReset();
    vi.useFakeTimers();
    fixture.from.mockImplementation((table: string) => {
      const chain: Record<string, unknown> = {};
      chain.select = vi.fn(() => chain);
      chain.eq = vi.fn(() => chain);
      const result = () => ({
        error: null,
        data: table === "agent_engine_runs" ? {
          id: "synthetic-codex-run", execution_kind: "conversation",
          conversation_id: fixture.conversationId, workspace_id: fixture.workspaceId,
          engine_id: "codex", auth_mode: fixture.mode, adapter_version: "codex-v1",
          auth_mode_generation: fixture.generation,
          created_at: "2026-01-01T00:00:00Z",
        } : {
          id: fixture.conversationId, user_id: fixture.userId,
          workspace_id: fixture.workspaceId, repo_url: fixture.repoUrl,
        },
      });
      chain.single = vi.fn(async () => result());
      chain.maybeSingle = vi.fn(async () => result());
      return chain;
    });
  });

  afterEach(() => {
    sessions.delete(fixture.userId);
    vi.clearAllTimers();
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  async function chat(attachments?: unknown[]) {
    const send = vi.fn();
    const session = {
      ws: { readyState: 1, send, close: vi.fn() },
      conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION,
      tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession;
    sessions.set(fixture.userId, session);
    await handleMessage(fixture.userId, JSON.stringify({
      type: "chat", content: "Synthetic qualification boundary prompt",
      clientTurnId: "90000000-0000-4000-8000-000000000001", ...(attachments ? { attachments } : {}),
    }));
    return send.mock.calls.map(([value]) => JSON.parse(value as string) as { type: string });
  }

  function assertNoExecution(frames: { type: string }[]) {
    expect(frames.map((frame) => frame.type)).toEqual(["error"]);
    expect(fixture.rpc).not.toHaveBeenCalled();
    expect(fixture.from).not.toHaveBeenCalledWith("api_keys");
    expect(fixture.from).not.toHaveBeenCalledWith("messages");
    expect(fixture.spawn).not.toHaveBeenCalled();
    expect(fixture.sendUserMessage).not.toHaveBeenCalled();
    expect(fixture.startAgentSession).not.toHaveBeenCalled();
    expect(fixture.dispatchSoleurGo).not.toHaveBeenCalled();
  }

  it.each(["api-key", "managed"] as const)("rejects %s before credentials, attempts or provider calls", async (mode) => {
    fixture.mode = mode;
    fixture.generation = 0;
    const credentialFactory = vi.spyOn(credentials, "createCodexApiKeyProviderForUser");
    const frames = await chat();
    assertNoExecution(frames);
    expect(credentialFactory).not.toHaveBeenCalled();
    expect(fixture.captureException).toHaveBeenCalledOnce();
    expect(fixture.hashUserId).toHaveBeenCalledWith(fixture.userId);
    expect(fixture.captureException).toHaveBeenCalledWith(expect.objectContaining({ code: "engine_disabled" }));
    // Confirm the fixture reached binding lookup rather than an earlier auth gate.
    expect(fixture.from).toHaveBeenCalledWith("agent_engine_runs");
    expect(fixture.from.mock.calls.filter(([table]) => table === "agent_engine_runs")).toHaveLength(2);
  });

  it("rejects unqualified attachments before attempts or provider calls", async () => {
    fixture.mode = "api-key";
    const frames = await chat([{ id: "synthetic-attachment" }]);
    assertNoExecution(frames);
    expect(fixture.captureException).toHaveBeenCalledWith(expect.objectContaining({
      message: "Codex conversation attachments are not qualified",
    }));
  });

  it.each(["api-key", "managed"] as const)("withholds a switched %s conversation and reports the mode and unsent turn", async (mode) => {
    fixture.mode = mode;
    fixture.generation = 1;
    fixture.rpc.mockImplementation(async (name: string) => name === "codex_history_transfer_acknowledged"
      ? { data: false, error: null }
      : name === "issue_codex_history_transfer_notice"
        ? { data: true, error: null }
      : name === "mark_codex_history_transfer_notice_delivered"
        ? { data: true, error: null }
      : { data: null, error: null });

    const frames = await chat();

    expect(frames).toEqual([expect.objectContaining({
      type: "codex_history_transfer_required",
      conversationId: fixture.conversationId,
      authModeGeneration: 1,
      authMode: mode,
      clientTurnId: "90000000-0000-4000-8000-000000000001",
      noticeNonce: expect.stringMatching(/^[A-Za-z0-9_-]{43}$/),
    })]);
    expect(fixture.rpc).toHaveBeenCalledWith("codex_history_transfer_acknowledged", {
      p_conversation_id: fixture.conversationId,
      p_auth_mode_generation: 1,
    });
    expect(fixture.rpc).toHaveBeenCalledWith("issue_codex_history_transfer_notice", expect.objectContaining({
      p_conversation_id: fixture.conversationId,
      p_auth_mode_generation: 1,
      p_member_user_id: fixture.userId,
      p_nonce_hash: expect.stringMatching(/^[a-f0-9]{64}$/),
    }));
    expect(fixture.rpc).toHaveBeenCalledWith("mark_codex_history_transfer_notice_delivered", expect.objectContaining({
      p_conversation_id: fixture.conversationId,
      p_auth_mode_generation: 1,
      p_member_user_id: fixture.userId,
      p_nonce_hash: expect.stringMatching(/^[a-f0-9]{64}$/),
    }));
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.from).not.toHaveBeenCalledWith("api_keys");
    expect(fixture.from).not.toHaveBeenCalledWith("messages");
    expect(fixture.spawn).not.toHaveBeenCalled();
    expect(fixture.sendUserMessage).not.toHaveBeenCalled();
    expect(fixture.startAgentSession).not.toHaveBeenCalled();
    expect(fixture.dispatchSoleurGo).not.toHaveBeenCalled();
  });

  it("does not send an acknowledgment notice unless server issuance is recorded", async () => {
    fixture.mode = "managed";
    fixture.generation = 1;
    fixture.rpc.mockImplementation(async (name: string) => name === "codex_history_transfer_acknowledged"
      ? { data: false, error: null }
      : name === "issue_codex_history_transfer_notice"
        ? { data: false, error: null }
        : { data: null, error: null });

    const frames = await chat();

    expect(frames).not.toContainEqual(expect.objectContaining({ type: "codex_history_transfer_required" }));
    expect(frames).toContainEqual(expect.objectContaining({ type: "error" }));
    expect(fixture.spawn).not.toHaveBeenCalled();
    expect(fixture.sendUserMessage).not.toHaveBeenCalled();
  });

  function noticeSession() {
    const send = vi.fn();
    const session = {
      ws: { readyState: 1, send, close: vi.fn() },
      conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION,
      tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession;
    sessions.set(fixture.userId, session);
    return { session, send, frames: () => send.mock.calls.map(([value]) => JSON.parse(value as string)) };
  }

  const noticeChat = () => handleMessage(fixture.userId, JSON.stringify({
    type: "chat", content: "Synthetic held turn", clientTurnId: "synthetic-notice-turn",
  }));
  const acknowledgeNotice = (noticeNonce: string) => handleMessage(fixture.userId, JSON.stringify({
    type: "codex_history_transfer_acknowledge", conversationId: fixture.conversationId,
    authModeGeneration: 1, noticeNonce,
  }));

  it("waits for delivery persistence before accepting a fast acknowledgment", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    let delivered = false;
    let releaseMarker!: () => void;
    const markerGate = new Promise<void>((resolve) => { releaseMarker = resolve; });
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered") {
        await markerGate;
        delivered = true;
        return { data: true, error: null };
      }
      return { data: name !== "record_codex_history_transfer_acknowledgment" || delivered, error: null };
    });
    const turn = noticeChat();
    let ack: Promise<void> | undefined;
    try {
      await vi.waitFor(() => expect(client.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_required" })));
      ack = acknowledgeNotice(client.frames().find((frame) => frame.type === "codex_history_transfer_required").noticeNonce);
      // Let authorization and any unguarded RPC run while the marker is pending.
      for (let step = 0; step < 30; step += 1) await Promise.resolve();
      expect(fixture.rpc).not.toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", expect.anything());
      releaseMarker();
      await Promise.all([turn, ack]);
      expect(client.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));
      expect(client.frames()).not.toContainEqual(expect.objectContaining({ type: "error" }));
      expect(fixture.spawn).not.toHaveBeenCalled();
    } finally {
      releaseMarker();
      await turn;
      if (ack) await ack;
    }
  });

  it("recovers an ambiguous committed delivery marker without issuing a new nonce", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    let markerCalls = 0;
    let delivered = false;
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered") {
        markerCalls += 1;
        delivered = true;
        if (markerCalls === 1) throw new Error("Synthetic committed marker response lost");
      }
      return { data: name !== "record_codex_history_transfer_acknowledgment" || delivered, error: null };
    });
    await noticeChat();
    expect(markerCalls).toBe(2);
    expect(client.frames()).not.toContainEqual(expect.objectContaining({ type: "error" }));
    await acknowledgeNotice(client.frames()[0].noticeNonce);
    expect(client.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "issue_codex_history_transfer_notice")).toHaveLength(1);
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it("retains a delivered notice through persistent marker failure and recovers on explicit acknowledgment retry", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    let markerAvailable = false;
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered" && !markerAvailable) {
        throw new Error("Synthetic marker storage unavailable");
      }
      return { data: true, error: null };
    });
    await noticeChat();
    expect(client.frames().map((frame) => frame.type)).toEqual(["codex_history_transfer_required"]);
    const nonce = client.frames()[0].noticeNonce;
    await acknowledgeNotice(nonce);
    expect(client.frames()).toContainEqual(expect.objectContaining({
      type: "error", errorCode: "codex_history_transfer_acknowledgment_failed",
    }));
    expect(fixture.rpc).not.toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", expect.anything());
    markerAvailable = true;
    await acknowledgeNotice(nonce);
    expect(client.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "issue_codex_history_transfer_notice")).toHaveLength(1);
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it("bounds a hung marker and can retry the same notice after storage recovers", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    let available = false;
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered" && !available) {
        return new Promise<never>(() => {});
      }
      return { data: true, error: null };
    });
    const turn = noticeChat();
    await vi.waitFor(() => expect(fixture.rpc).toHaveBeenCalledWith("mark_codex_history_transfer_notice_delivered", expect.anything()));
    await vi.advanceTimersByTimeAsync(10_001);
    await turn;
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered")).toHaveLength(2);
    expect(client.frames().map((frame) => frame.type)).toEqual(["codex_history_transfer_required"]);
    available = true;
    await acknowledgeNotice(client.frames()[0].noticeNonce);
    expect(client.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it("aborts each stalled marker fetch before retrying and leaves no active signal after timeout", async () => {
    fixture.generation = 1;
    noticeSession();
    const markerSignals: AbortSignal[] = [];
    fixture.rpcStarts.mockImplementation((name, signal) => {
      if (name !== "mark_codex_history_transfer_notice_delivered") return;
      expect(signal).toBeInstanceOf(AbortSignal);
      expect(markerSignals.every((previous) => previous.aborted)).toBe(true);
      expect(signal?.aborted).toBe(false);
      markerSignals.push(signal!);
    });
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered") return new Promise<never>(() => {});
      return { data: true, error: null };
    });
    const turn = noticeChat();
    await vi.waitFor(() => expect(fixture.rpcStarts).toHaveBeenCalledWith("mark_codex_history_transfer_notice_delivered", expect.anything()));
    await vi.advanceTimersByTimeAsync(10_001);
    await turn;
    expect(markerSignals).toHaveLength(2);
    expect(markerSignals.every((signal) => signal.aborted)).toBe(true);
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered")).toHaveLength(2);
  });

  it("does not let an unrelated nonce trigger privileged delivery recovery", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "mark_codex_history_transfer_notice_delivered") throw new Error("Synthetic marker failure");
      return { data: name === "issue_codex_history_transfer_notice", error: null };
    });
    await noticeChat();
    const markerCalls = fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered").length;
    await acknowledgeNotice("B".repeat(43));
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered")).toHaveLength(markerCalls);
    expect(client.frames()).toContainEqual(expect.objectContaining({ errorCode: "codex_history_transfer_acknowledgment_rejected" }));
    expect(client.frames()).not.toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it.each(["outage", "committed-response-lost"])("recovers the retained nonce after a new socket session following %s", async (failure) => {
    fixture.generation = 1;
    const original = noticeSession();
    let storageAvailable = false;
    let delivered = false;
    let consumed = false;
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered") {
        if (storageAvailable || failure === "committed-response-lost") delivered = true;
        if (!storageAvailable) throw new Error("Synthetic marker response unavailable");
      }
      if (name === "record_codex_history_transfer_acknowledgment") {
        const accepted = delivered && !consumed;
        consumed ||= accepted;
        return { data: accepted, error: null };
      }
      return { data: true, error: null };
    });
    await noticeChat();
    const nonce = original.frames()[0].noticeNonce;
    const reconnected = noticeSession();
    storageAvailable = true;
    await acknowledgeNotice(nonce);
    expect(reconnected.frames()).toEqual([expect.objectContaining({ type: "codex_history_transfer_acknowledged" })]);
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered")).toHaveLength(3);
    expect(fixture.rpc.mock.calls.filter(([name]) => name === "issue_codex_history_transfer_notice")).toHaveLength(1);
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.from).not.toHaveBeenCalledWith("messages");
    expect(fixture.spawn).not.toHaveBeenCalled();
    expect(fixture.sendUserMessage).not.toHaveBeenCalled();
  });

  it("shares a reconnect marker recovery between simultaneous acknowledgments without consuming twice", async () => {
    const client = noticeSession();
    let releaseMarker!: () => void;
    const markerGate = new Promise<void>((resolve) => { releaseMarker = resolve; });
    let delivered = false;
    let consumed = false;
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "mark_codex_history_transfer_notice_delivered") { await markerGate; delivered = true; }
      if (name === "codex_history_transfer_acknowledged") return { data: consumed, error: null };
      if (name === "record_codex_history_transfer_acknowledgment") {
        const accepted = delivered && !consumed;
        consumed ||= accepted;
        return { data: accepted, error: null };
      }
      return { data: true, error: null };
    });
    const first = acknowledgeNotice("A".repeat(43));
    const second = acknowledgeNotice("A".repeat(43));
    try {
      await vi.waitFor(() => expect(fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered")).toHaveLength(1));
      expect(fixture.rpc).not.toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", expect.anything());
      releaseMarker();
      await Promise.all([first, second]);
      expect(client.frames().filter((frame) => frame.type === "codex_history_transfer_acknowledged")).toHaveLength(2);
      expect(client.frames().filter((frame) => frame.type === "error")).toHaveLength(0);
      expect(fixture.rpc.mock.calls.filter(([name]) => name === "mark_codex_history_transfer_notice_delivered")).toHaveLength(1);
    } finally {
      releaseMarker();
      await Promise.all([first, second]);
    }
  });

  it("does not consume or reply into a replacement socket during reconnect recovery", async () => {
    noticeSession();
    let releaseMarker!: () => void;
    const gate = new Promise<void>((resolve) => { releaseMarker = resolve; });
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "mark_codex_history_transfer_notice_delivered") await gate;
      return { data: true, error: null };
    });
    const ack = acknowledgeNotice("A".repeat(43));
    try {
      await vi.waitFor(() => expect(fixture.rpc).toHaveBeenCalledWith("mark_codex_history_transfer_notice_delivered", expect.anything()));
      const replacement = noticeSession();
      releaseMarker();
      await ack;
      expect(fixture.rpc).not.toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", expect.anything());
      expect(replacement.frames()).toEqual([]);
    } finally {
      releaseMarker();
      await ack;
    }
  });

  it("confirms a durable acknowledgment after the record RPC commits but loses its response", async () => {
    fixture.generation = 1;
    const original = noticeSession();
    let acknowledgmentCommitted = false;
    let recordCalls = 0;
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: acknowledgmentCommitted, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered") return { data: !acknowledgmentCommitted, error: null };
      if (name === "record_codex_history_transfer_acknowledgment") {
        recordCalls += 1;
        acknowledgmentCommitted = true;
        throw new Error("Synthetic committed acknowledgment response lost");
      }
      return { data: true, error: null };
    });

    await noticeChat();
    const nonce = original.frames()[0].noticeNonce;
    await acknowledgeNotice(nonce);
    expect(original.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));

    const reconnected = noticeSession();
    await acknowledgeNotice(nonce);
    expect(reconnected.frames()).toContainEqual(expect.objectContaining({ type: "codex_history_transfer_acknowledged" }));
    expect(recordCalls).toBe(1);
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.from).not.toHaveBeenCalledWith("messages");
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it("does not acknowledge into a replacement session after waiting for delivery", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    let releaseMarker!: () => void;
    const gate = new Promise<void>((resolve) => { releaseMarker = resolve; });
    fixture.rpc.mockImplementation(async (name: string) => {
      if (name === "codex_history_transfer_acknowledged") return { data: false, error: null };
      if (name === "mark_codex_history_transfer_notice_delivered") await gate;
      return { data: true, error: null };
    });
    const turn = noticeChat();
    let ack: Promise<void> | undefined;
    try {
      await vi.waitFor(() => expect(client.frames()).toHaveLength(1));
      ack = acknowledgeNotice(client.frames()[0].noticeNonce);
      for (let step = 0; step < 30; step += 1) await Promise.resolve();
      const replacement = noticeSession();
      releaseMarker();
      await Promise.all([turn, ack]);
      expect(fixture.rpc).not.toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", expect.anything());
      expect(replacement.frames()).toEqual([]);
    } finally {
      releaseMarker();
      await turn;
      if (ack) await ack;
    }
  });

  it("discards an unsent issuance when socket send throws", async () => {
    fixture.generation = 1;
    const client = noticeSession();
    client.send.mockImplementationOnce(() => { throw new Error("Synthetic socket send failure"); });
    fixture.rpc.mockImplementation(async (name: string) => ({
      data: name !== "codex_history_transfer_acknowledged",
      error: name === "delete_codex_history_transfer_notice_issuance" ? new Error("Synthetic cleanup failure") : null,
    }));
    await noticeChat();
    expect(fixture.rpc).toHaveBeenCalledWith("delete_codex_history_transfer_notice_issuance", expect.objectContaining({
      p_conversation_id: fixture.conversationId, p_auth_mode_generation: 1,
      p_member_user_id: fixture.userId, p_nonce_hash: expect.stringMatching(/^[a-f0-9]{64}$/),
    }));
    expect(fixture.rpc).not.toHaveBeenCalledWith("mark_codex_history_transfer_notice_delivered", expect.anything());
    expect(fixture.reportSilentFallback).toHaveBeenCalledWith(expect.any(Error), {
      feature: "codex-history-transfer", op: "discard-unsent-notice",
    });
    expect(client.send.mock.results[0]?.type).toBe("throw");
  });

  it("records the active member's acknowledgment for the exact conversation generation", async () => {
    fixture.rpc.mockResolvedValue({ data: true, error: null });
    const send = vi.fn();
    sessions.set(fixture.userId, {
      ws: { readyState: 1, send, close: vi.fn() },
      conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION,
      tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession);

    await handleMessage(fixture.userId, JSON.stringify({
      type: "codex_history_transfer_acknowledge",
      conversationId: fixture.conversationId,
      authModeGeneration: 1,
      noticeNonce: "A".repeat(43),
    }));

    expect(fixture.rpc).toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", {
      p_conversation_id: fixture.conversationId,
      p_auth_mode_generation: 1,
      p_nonce_hash: "0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a",
    });
    expect(send.mock.calls.map(([value]) => JSON.parse(value as string))).toContainEqual({
      type: "codex_history_transfer_acknowledged",
      conversationId: fixture.conversationId,
      authModeGeneration: 1,
    });
    expect(fixture.from).not.toHaveBeenCalledWith("messages");
    expect(fixture.spawn).not.toHaveBeenCalled();
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.sendUserMessage).not.toHaveBeenCalled();
    expect(fixture.dispatchSoleurGo).not.toHaveBeenCalled();
  });

  it("routes abort_turn through the real handler into the active Codex dispatch signal", async () => {
    fixture.mode = "api-key";
    fixture.rpc.mockImplementation(async (name: string) => name === "start_agent_engine_attempt"
      ? { data: { id: "synthetic-codex-attempt" }, error: null }
      : { data: null, error: null });
    const started = vi.fn();
    let dispatchSignal: AbortSignal | undefined;
    const adapter = {
      start: vi.fn(async function* (context: { signal: AbortSignal }) {
        dispatchSignal = context.signal;
        started();
        await new Promise<void>((resolve) => context.signal.addEventListener("abort", () => resolve(), { once: true }));
        yield { runId: "synthetic-codex-run", eventId: "cancelled-event", sequence: 1, payload: { type: "status", status: "cancelled" } as const };
      }),
      dispose: vi.fn().mockResolvedValue(undefined),
    };
    const registry = createEngineRegistry([{
      id: "codex", version: "codex-v1", transport: "remote", enabledForNewRuns: false, enabledForExistingRuns: true,
      authModes: ["api-key"], qualifications: [{ authMode: "api-key", adapterVersion: "codex-v1", workflow: "conversation", dataClass: "synthetic", expiresAt: Date.now() + 60_000, evidenceRef: "synthetic-handler-test", capabilities: { streaming: "verified" } }],
    }]);
    vi.spyOn(codexRuntimeModule, "codexConversationRuntime").mockReturnValue({
      runtime: {
        userId: fixture.userId,
        transport: {} as never,
        apiKeyProvider: { mode: "api-key", acquire: vi.fn(), refresh: vi.fn(), logout: vi.fn() },
        createCodex: () => adapter as never,
      },
      registry,
      dataClass: "synthetic",
      evidence: {
        endpoint: "https://api.openai.com/v1", allowedHosts: ["api.openai.com"], acceptedDataClasses: ["synthetic"],
        vendorDpaStatus: "verified", transferGeography: "scc", deletionSupport: "verified", approvalRequired: false,
      },
    });

    const send = vi.fn();
    sessions.set(fixture.userId, {
      ws: { readyState: 1, send, close: vi.fn() },
      conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION,
      tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession);
    const turn = handleMessage(fixture.userId, JSON.stringify({
      type: "chat", content: "Synthetic cancellation prompt", clientTurnId: "synthetic-cancel-turn",
    }));
    await vi.waitFor(() => expect(started).toHaveBeenCalledOnce());
    await handleMessage(fixture.userId, JSON.stringify({ type: "abort_turn", conversationId: fixture.conversationId }));
    await turn;

    expect(dispatchSignal?.aborted).toBe(true);
    expect(adapter.start).toHaveBeenCalledOnce();
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it("cancels a chat while tenant authorization is pending before binding or provider dispatch", async () => {
    let releaseTenant!: () => void;
    fixture.tenantGate = new Promise<void>((resolve) => { releaseTenant = resolve; });
    const send = vi.fn();
    sessions.set(fixture.userId, {
      ws: { readyState: 1, send, close: vi.fn() },
      conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION,
      tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession);

    const turn = handleMessage(fixture.userId, JSON.stringify({
      type: "chat", content: "Synthetic pending authorization prompt",
      clientTurnId: "90000000-0000-4000-8000-000000000002",
    }));
    await vi.waitFor(() => expect(fixture.tenantMintStarted).toHaveBeenCalledOnce());
    await handleMessage(fixture.userId, JSON.stringify({ type: "abort_turn", conversationId: fixture.conversationId }));
    releaseTenant();
    await turn;

    expect(fixture.from).not.toHaveBeenCalledWith("agent_engine_runs");
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it.each(["B-active", "B-completed", "A-throws"])("withholds superseded turn output when %s", async (variant) => {
    fixture.rpc.mockImplementation(async (name: string, args?: { p_attempt_key?: string }) => name === "start_agent_engine_attempt"
      ? { data: { id: args?.p_attempt_key ?? "synthetic-attempt" }, error: null }
      : { data: null, error: null });
    let releaseA!: () => void;
    let releaseB!: () => void;
    const gateA = new Promise<void>((resolve) => { releaseA = resolve; });
    const gateB = new Promise<void>((resolve) => { releaseB = resolve; });
    let signalA: AbortSignal | undefined;
    const started = vi.fn();
    const adapter = {
      start: vi.fn(async function* (context: { signal: AbortSignal; idempotencyKey: string }) {
        started(context.idempotencyKey);
        if (context.idempotencyKey === "synthetic-turn-A") {
          signalA = context.signal;
          await gateA;
          if (variant === "A-throws") throw new Error("Synthetic old provider failure");
          yield { runId: "synthetic-codex-run", eventId: "synthetic-A-text", sequence: 1, payload: { type: "text", text: "Delayed A output" } as const };
          yield { runId: "synthetic-codex-run", eventId: "synthetic-A-terminal", sequence: 2, payload: { type: "status", status: "cancelled" } as const };
        } else {
          yield { runId: "synthetic-codex-run", eventId: "synthetic-B-text", sequence: 1, payload: { type: "text", text: "Current B output" } as const };
          await gateB;
          yield { runId: "synthetic-codex-run", eventId: "synthetic-B-terminal", sequence: 2, payload: { type: "status", status: "completed" } as const };
        }
      }),
      dispose: vi.fn(async () => undefined),
    };
    const registry = createEngineRegistry([{
      id: "codex", version: "codex-v1", transport: "remote", enabledForNewRuns: false, enabledForExistingRuns: true,
      authModes: ["api-key"], qualifications: [{ authMode: "api-key", adapterVersion: "codex-v1", workflow: "conversation", dataClass: "synthetic", expiresAt: Date.now() + 60_000, evidenceRef: "synthetic-handler-test", capabilities: { streaming: "verified" } }],
    }]);
    vi.spyOn(codexRuntimeModule, "codexConversationRuntime").mockReturnValue({
      runtime: { userId: fixture.userId, transport: {} as never,
        apiKeyProvider: { mode: "api-key", acquire: vi.fn(), refresh: vi.fn(), logout: vi.fn() },
        createCodex: () => adapter as never },
      registry, dataClass: "synthetic",
      evidence: { endpoint: "https://api.openai.com/v1", allowedHosts: ["api.openai.com"], acceptedDataClasses: ["synthetic"], vendorDpaStatus: "verified", transferGeography: "scc", deletionSupport: "verified", approvalRequired: false },
    });
    const send = vi.fn();
    sessions.set(fixture.userId, {
      ws: { readyState: 1, send, close: vi.fn() }, conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION, tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession);
    const turnA = handleMessage(fixture.userId, JSON.stringify({ type: "chat", content: "Synthetic A", clientTurnId: "synthetic-turn-A" }));
    let turnB: Promise<void> | undefined;
    try {
      await vi.waitFor(() => expect(started).toHaveBeenCalledWith("synthetic-turn-A"));
      turnB = handleMessage(fixture.userId, JSON.stringify({ type: "chat", content: "Synthetic B", clientTurnId: "synthetic-turn-B" }));
      await vi.waitFor(() => expect(send.mock.calls.map(([value]) => JSON.parse(value as string))).toContainEqual(expect.objectContaining({ type: "stream", content: "Current B output" })));
      expect(signalA?.aborted).toBe(true);
      expect(signalA?.reason).toBe("superseded");
      if (variant === "B-completed") {
        releaseB();
        await turnB;
      }
      send.mockClear();
      releaseA();
      await turnA;
      const afterReplacement = send.mock.calls.map(([value]) => JSON.parse(value as string));
      expect(afterReplacement).toEqual([]);
    } finally {
      releaseA(); releaseB();
      await turnA;
      if (turnB) await turnB;
    }
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

  it("preserves the active cancelled terminal after explicit Stop", async () => {
    fixture.rpc.mockImplementation(async (name: string) => name === "start_agent_engine_attempt"
      ? { data: { id: "synthetic-stop-attempt" }, error: null }
      : { data: null, error: null });
    const started = vi.fn();
    const adapter = {
      start: vi.fn(async function* (context: { signal: AbortSignal }) {
        started();
        await new Promise<void>((resolve) => context.signal.addEventListener("abort", () => resolve(), { once: true }));
        yield { runId: "synthetic-codex-run", eventId: "synthetic-stop-terminal", sequence: 1, payload: { type: "status", status: "cancelled" } as const };
      }),
      dispose: vi.fn(async () => undefined),
    };
    const registry = createEngineRegistry([{
      id: "codex", version: "codex-v1", transport: "remote", enabledForNewRuns: false, enabledForExistingRuns: true,
      authModes: ["api-key"], qualifications: [{ authMode: "api-key", adapterVersion: "codex-v1", workflow: "conversation", dataClass: "synthetic", expiresAt: Date.now() + 60_000, evidenceRef: "synthetic-stop-test", capabilities: { streaming: "verified" } }],
    }]);
    vi.spyOn(codexRuntimeModule, "codexConversationRuntime").mockReturnValue({
      runtime: { userId: fixture.userId, transport: {} as never,
        apiKeyProvider: { mode: "api-key", acquire: vi.fn(), refresh: vi.fn(), logout: vi.fn() },
        createCodex: () => adapter as never },
      registry, dataClass: "synthetic",
      evidence: { endpoint: "https://api.openai.com/v1", allowedHosts: ["api.openai.com"], acceptedDataClasses: ["synthetic"], vendorDpaStatus: "verified", transferGeography: "scc", deletionSupport: "verified", approvalRequired: false },
    });
    const send = vi.fn();
    sessions.set(fixture.userId, {
      ws: { readyState: 1, send, close: vi.fn() }, conversationId: fixture.conversationId,
      lastActivity: Date.now(), tcVersionAtHandshake: TC_VERSION, tcRecheckCacheUntil: Date.now() + 1_000_000,
    } as unknown as ClientSession);
    const turn = handleMessage(fixture.userId, JSON.stringify({ type: "chat", content: "Synthetic Stop", clientTurnId: "synthetic-turn-stop" }));
    await vi.waitFor(() => expect(started).toHaveBeenCalledOnce());
    await handleMessage(fixture.userId, JSON.stringify({ type: "abort_turn", conversationId: fixture.conversationId }));
    await turn;
    expect(send.mock.calls.map(([value]) => JSON.parse(value as string))).toContainEqual(expect.objectContaining({ type: "stream_end", conversationId: fixture.conversationId }));
    expect(fixture.spawn).not.toHaveBeenCalled();
  });

});
