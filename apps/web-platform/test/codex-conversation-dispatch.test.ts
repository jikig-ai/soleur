import { describe, expect, it, vi } from "vitest";
import { createEngineRegistry } from "@/server/agent-engine-registry";
import { dispatchCodexConversationToWebSocket } from "@/server/codex-conversation-dispatch";
import type { EngineEventPayload } from "@/server/agent-engine-contract";

function turnFixture(payloads: EngineEventPayload[]) {
  const binding = {
    workspaceId: "synthetic-workspace", execution: { kind: "conversation" as const, conversationId: "synthetic-conversation" },
    engineId: "codex", authMode: "api-key", authModeGeneration: 2, adapterVersion: "codex-v1", boundAt: new Date().toISOString(),
  };
  const repository = {
    getConversationRun: vi.fn().mockResolvedValue({ id: "synthetic-run", binding }),
    getRun: vi.fn().mockResolvedValue({ id: "synthetic-run", binding }),
    startAttempt: vi.fn().mockResolvedValue({ id: "synthetic-attempt" }),
    assertAttemptGeneration: vi.fn().mockResolvedValue(0),
    transitionAttempt: vi.fn().mockResolvedValue(null),
    appendLifecycleEvent: vi.fn().mockResolvedValue(null),
  };
  const adapter = {
    start: vi.fn(async function* () {
      for (const [index, payload] of payloads.entries()) {
        yield { runId: "synthetic-run", eventId: `synthetic-event-${index}`, sequence: index + 1, payload };
      }
    }),
  };
  const send = vi.fn();
  const options: Parameters<typeof dispatchCodexConversationToWebSocket>[0] = {
    repository,
    runtime: {
      userId: "synthetic-user", transport: {} as never,
      apiKeyProvider: { mode: "api-key", acquire: vi.fn(), refresh: vi.fn(), logout: vi.fn() },
      createCodex: () => adapter as never,
    },
    conversationId: "synthetic-conversation", input: { text: "Synthetic turn", attachmentIds: [] },
    context: { runId: "synthetic-run", binding: binding as never, idempotencyKey: "synthetic-turn", signal: new AbortController().signal },
    selection: { engineId: "codex", authMode: "api-key", operation: "existing-run", workflow: "conversation", dataClass: "synthetic", requiredCapabilities: [], now: Date.now() },
    evidence: { endpoint: "https://api.openai.com/v1", allowedHosts: ["api.openai.com"], acceptedDataClasses: ["synthetic"], vendorDpaStatus: "verified", transferGeography: "scc", deletionSupport: "verified", approvalRequired: false },
    leaderId: "cc_router", send,
    registry: createEngineRegistry([{
      id: "codex", version: "codex-v1", transport: "remote", enabledForNewRuns: false, enabledForExistingRuns: true,
      authModes: ["api-key"], qualifications: [{ authMode: "api-key", adapterVersion: "codex-v1", workflow: "conversation", dataClass: "synthetic", expiresAt: Date.now() + 60_000, evidenceRef: "synthetic-test", capabilities: {} }],
    }]),
  };
  return { repository, send, options };
}

describe("Codex conversation dispatch bridge", () => {
  it("loads the persisted Codex binding, persists events, and emits WS frames", async () => {
    const events = [] as unknown[];
    const sent = [] as unknown[];
    const adapter = {
      start: vi.fn(async function* () {
        yield { runId: "run-1", eventId: "e-1", sequence: 1, payload: { type: "text", text: "hello" } as const };
        yield { runId: "run-1", eventId: "e-2", sequence: 2, payload: { type: "status", status: "completed" } as const };
      }),
    };
    const provider = {
      mode: "api-key" as const,
      acquire: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
      refresh: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
      logout: async () => undefined,
    };
    const repository = {
      getConversationRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { workspaceId: "ws-1", execution: { kind: "conversation", conversationId: "conv-1" }, engineId: "codex", authMode: "api-key", authModeGeneration: 2, adapterVersion: "codex-v1", boundAt: new Date().toISOString() } }),
      getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { workspaceId: "ws-1", execution: { kind: "conversation", conversationId: "conv-1" }, engineId: "codex", authMode: "api-key", authModeGeneration: 2, adapterVersion: "codex-v1", boundAt: new Date().toISOString() } }),
      appendEvent: vi.fn(async (event: unknown) => { events.push(event); }),
      startAttempt: vi.fn().mockResolvedValue({ id: "attempt-1" }),
      assertAttemptGeneration: vi.fn().mockResolvedValue(0),
      transitionAttempt: vi.fn().mockResolvedValue(null),
    };
    const registry = createEngineRegistry([{
      id: "codex", version: "codex-v1", transport: "remote", enabledForNewRuns: false, enabledForExistingRuns: true,
      authModes: ["api-key"], qualifications: [{ authMode: "api-key", adapterVersion: "codex-v1", workflow: "conversation", dataClass: "synthetic", expiresAt: Date.now() + 60_000, evidenceRef: "test", capabilities: {} }],
    }]);
    await dispatchCodexConversationToWebSocket({
      repository,
      runtime: { userId: "user-1", transport: {} as never, apiKeyProvider: provider, createCodex: () => adapter as never },
      conversationId: "conv-1",
      input: { text: "hi", attachmentIds: [] },
      context: { runId: "run-1", binding: {} as never, idempotencyKey: "idempotency", signal: new AbortController().signal },
      selection: { engineId: "codex", authMode: "api-key", operation: "existing-run", workflow: "conversation", dataClass: "synthetic", requiredCapabilities: [], now: Date.now() },
      evidence: { endpoint: "https://api.openai.com/v1", allowedHosts: ["api.openai.com"], acceptedDataClasses: ["synthetic"], vendorDpaStatus: "verified", transferGeography: "scc", deletionSupport: "verified", approvalRequired: false },
      leaderId: "cc_router",
      send: (message) => sent.push(message),
      registry,
    });
    expect(repository.getConversationRun).toHaveBeenCalledWith("conv-1");
    expect(repository.startAttempt).toHaveBeenCalledWith("run-1", "idempotency", "api-key", 2);
    expect(repository.assertAttemptGeneration).toHaveBeenCalledWith("attempt-1");
    expect(events).toHaveLength(2);
    expect(sent).toEqual([
      { type: "stream", content: "hello", partial: true, leaderId: "cc_router" },
      { type: "stream_end", leaderId: "cc_router" },
    ]);
  });

  it("rejects a stale binding generation before constructing its mode-specific adapter", async () => {
    const { repository, options } = turnFixture([{ type: "status", status: "completed" }]);
    const createCodex = vi.fn(() => ({ start: vi.fn() } as never));
    const readCredentialMode = vi.fn(() => "api-key");
    const provider = {
      get mode() { return readCredentialMode(); },
      acquire: vi.fn(), refresh: vi.fn(), logout: vi.fn(),
    };
    options.runtime.createCodex = createCodex;
    options.runtime.apiKeyProvider = provider as never;
    repository.startAttempt.mockRejectedValue(Object.assign(new Error("Codex binding changed"), { code: "codex_binding_stale" }));

    await expect(dispatchCodexConversationToWebSocket(options)).rejects.toMatchObject({ code: "codex_binding_stale" });
    expect(repository.startAttempt).toHaveBeenCalledWith("synthetic-run", "synthetic-turn", "api-key", 2);
    expect(readCredentialMode).not.toHaveBeenCalled();
    expect(createCodex).not.toHaveBeenCalled();
    expect(options.send).not.toHaveBeenCalled();
  });

  it.each(["failed", "cancelled", "completed"] as const)("persists the provider's %s terminal outcome", async (status) => {
    const { repository, send, options } = turnFixture([
      { type: "status", status: "running" }, { type: "status", status },
    ]);
    await dispatchCodexConversationToWebSocket(options);
    expect(repository.transitionAttempt.mock.calls).toEqual([
      ["synthetic-attempt", "running"], ["synthetic-attempt", status],
    ]);
    expect(repository.appendLifecycleEvent).toHaveBeenLastCalledWith("synthetic-run", "synthetic-attempt", { type: "status", status });
    expect(send).toHaveBeenLastCalledWith({ type: "stream_end", leaderId: "cc_router" });
  });

  it.each<{ label: string; payloads: EngineEventPayload[] }>([
    { label: "empty stream", payloads: [] },
    { label: "running", payloads: [{ type: "status", status: "running" }] },
    { label: "waiting", payloads: [{ type: "status", status: "waiting" }] },
    { label: "partial text", payloads: [{ type: "text", text: "Partial response" }] },
  ])("fails closed when the provider ends without a terminal status ($label)", async ({ payloads }) => {
    const { repository, options } = turnFixture(payloads);
    await expect(dispatchCodexConversationToWebSocket(options)).rejects.toMatchObject({ code: "codex_terminal_missing" });
    expect(repository.transitionAttempt.mock.calls).toEqual([
      ["synthetic-attempt", "running"], ["synthetic-attempt", "failed"],
    ]);
  });
});
