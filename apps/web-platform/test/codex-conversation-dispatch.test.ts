import { describe, expect, it, vi } from "vitest";
import { createEngineRegistry } from "@/server/agent-engine-registry";
import { dispatchCodexConversationToWebSocket } from "@/server/codex-conversation-dispatch";

describe("Codex conversation dispatch bridge", () => {
  it("loads the persisted Codex binding, persists events, and emits WS frames", async () => {
    const events = [] as unknown[];
    const sent = [] as unknown[];
    const adapter = {
      start: vi.fn(async function* () {
        yield { runId: "run-1", eventId: "e-1", sequence: 1, payload: { type: "text", text: "hello" } as const };
      }),
    };
    const provider = {
      mode: "api-key" as const,
      acquire: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
      refresh: async () => ({ accessToken: "token", expiresAt: Date.now() + 60_000 }),
      logout: async () => undefined,
    };
    const repository = {
      getConversationRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { workspaceId: "ws-1", execution: { kind: "conversation", conversationId: "conv-1" }, engineId: "codex", authMode: "api-key", adapterVersion: "codex-v1", boundAt: new Date().toISOString() } }),
      getRun: vi.fn().mockResolvedValue({ id: "run-1", binding: { workspaceId: "ws-1", execution: { kind: "conversation", conversationId: "conv-1" }, engineId: "codex", authMode: "api-key", adapterVersion: "codex-v1", boundAt: new Date().toISOString() } }),
      appendEvent: vi.fn(async (event: unknown) => { events.push(event); }),
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
    expect(events).toHaveLength(1);
    expect(sent).toEqual([{ type: "stream", content: "hello", partial: true, leaderId: "cc_router" }]);
  });
});
