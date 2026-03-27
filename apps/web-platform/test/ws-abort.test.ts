// Set env vars BEFORE dynamic imports — ws-handler.ts and agent-runner.ts
// create Supabase clients at module load time.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeEach, beforeAll } from "vitest";
import type { ClientSession } from "../server/ws-handler";

let abortActiveSession: (userId: string, session: ClientSession) => void;
let agentRunnerModule: { abortSession: (userId: string, conversationId: string, reason?: string) => void };

beforeAll(async () => {
  try {
    // Dynamic imports ensure env vars are set before modules evaluate
    agentRunnerModule = await import("../server/agent-runner");
    const wsHandler = await import("../server/ws-handler");
    abortActiveSession = wsHandler.abortActiveSession;
    vi.spyOn(agentRunnerModule, "abortSession");
  } catch {
    // @anthropic-ai/claude-agent-sdk not installed (CI) — tests will skip via guard
  }
});

describe("abortActiveSession", () => {
  let mockWs: ClientSession["ws"];

  beforeEach(() => {
    vi.clearAllMocks();
    mockWs = { readyState: 1, send: vi.fn(), ping: vi.fn() } as unknown as ClientSession["ws"];
  });

  test("aborts the active session and clears conversationId", () => {
    if (!abortActiveSession) return; // SDK not available in CI
    const session: ClientSession = { ws: mockWs, conversationId: "conv-A" };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).toHaveBeenCalledWith("user-1", "conv-A", "superseded");
    expect(session.conversationId).toBeUndefined();
  });

  test("no-ops when conversationId is undefined", () => {
    if (!abortActiveSession) return;
    const session: ClientSession = { ws: mockWs };

    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).not.toHaveBeenCalled();
    expect(session.conversationId).toBeUndefined();
  });

  test("is idempotent — second call is a no-op after first clears conversationId", () => {
    if (!abortActiveSession) return;
    const session: ClientSession = { ws: mockWs, conversationId: "conv-C" };

    abortActiveSession("user-1", session);
    abortActiveSession("user-1", session);

    expect(agentRunnerModule.abortSession).toHaveBeenCalledTimes(1);
  });
});
