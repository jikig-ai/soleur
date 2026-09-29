import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { TC_VERSION } from "@/lib/legal/tc-version";
import * as credentials from "@/server/codex-credential-provider";

const fixture = vi.hoisted(() => ({
  userId: "synthetic-codex-user",
  conversationId: "synthetic-codex-conversation",
  workspaceId: "a1b2c3d4-0000-4000-8000-000000000123",
  repoUrl: "https://github.com/example/synthetic-repo.git",
  mode: "api-key" as "api-key" | "managed",
  rpc: vi.fn(async () => ({ data: null, error: null })),
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
  getFreshTenantClient: vi.fn(async () => ({ rpc: fixture.rpc, from: fixture.from })),
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
          auth_mode_generation: 0,
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
      clientTurnId: "synthetic-turn", ...(attachments ? { attachments } : {}),
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
});
