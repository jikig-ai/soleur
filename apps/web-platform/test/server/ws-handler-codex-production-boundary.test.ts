import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TC_VERSION } from "@/lib/legal/tc-version";
import * as credentials from "@/server/codex-credential-provider";
import * as codexRuntimeModule from "@/server/codex-conversation-runtime";
import { createEngineRegistry } from "@/server/agent-engine-registry";

const fixture = vi.hoisted(() => ({
  userId: "synthetic-codex-user",
  conversationId: "synthetic-codex-conversation",
  workspaceId: "a1b2c3d4-0000-4000-8000-000000000123",
  repoUrl: "https://github.com/example/synthetic-repo.git",
  mode: "api-key" as "api-key" | "managed",
  generation: 0,
  tenantGate: null as Promise<void> | null,
  tenantMintStarted: vi.fn(),
  rpc: vi.fn(async (_name: string): Promise<{ data: unknown; error: null }> => ({ data: null, error: null })),
  from: vi.fn(),
  spawn: vi.fn(() => { throw new Error("Unexpected provider process launch"); }),
  captureException: vi.fn(),
  sendUserMessage: vi.fn(),
  startAgentSession: vi.fn(),
  dispatchSoleurGo: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({ rpc: fixture.rpc, from: fixture.from }),
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
  ...await importOriginal<typeof import("node:child_process")>(),
  spawn: fixture.spawn,
}));
vi.mock("@sentry/nextjs", () => ({ captureException: fixture.captureException }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
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
      : { data: null, error: null });

    const frames = await chat();

    expect(frames).toEqual([{
      type: "codex_history_transfer_required",
      conversationId: fixture.conversationId,
      authModeGeneration: 1,
      authMode: mode,
      clientTurnId: "90000000-0000-4000-8000-000000000001",
    }]);
    expect(fixture.rpc).toHaveBeenCalledWith("codex_history_transfer_acknowledged", {
      p_conversation_id: fixture.conversationId,
      p_auth_mode_generation: 1,
    });
    expect(fixture.rpc).not.toHaveBeenCalledWith("start_agent_engine_attempt", expect.anything());
    expect(fixture.from).not.toHaveBeenCalledWith("api_keys");
    expect(fixture.from).not.toHaveBeenCalledWith("messages");
    expect(fixture.spawn).not.toHaveBeenCalled();
    expect(fixture.sendUserMessage).not.toHaveBeenCalled();
    expect(fixture.startAgentSession).not.toHaveBeenCalled();
    expect(fixture.dispatchSoleurGo).not.toHaveBeenCalled();
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
    }));

    expect(fixture.rpc).toHaveBeenCalledWith("record_codex_history_transfer_acknowledgment", {
      p_conversation_id: fixture.conversationId,
      p_auth_mode_generation: 1,
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
});
