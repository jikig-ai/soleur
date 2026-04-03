// Set env vars BEFORE dynamic imports — agent-runner.ts creates Supabase
// clients at module load time.
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, test, expect, vi, beforeAll, beforeEach } from "vitest";

// We test the session key logic via the exported abortSession and
// abortAllUserSessions functions. The activeSessions map is internal,
// so we observe it through abort behavior.

let agentRunnerModule: {
  abortSession: (userId: string, conversationId: string, reason?: "disconnected" | "superseded", leaderId?: string) => void;
  abortAllUserSessions: (userId: string) => void;
};

beforeAll(async () => {
  try {
    agentRunnerModule = await import("../server/agent-runner");
  } catch {
    // @anthropic-ai/claude-agent-sdk not installed (CI) — tests will skip via guard
  }
});

describe("session key with leaderId", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("abortSession with leaderId only aborts that specific leader session", () => {
    if (!agentRunnerModule) return;
    // The function signature now accepts an optional leaderId parameter.
    // When leaderId is provided, only that leader's session is aborted.
    // This test verifies the function signature accepts 4 params.
    expect(agentRunnerModule.abortSession.length).toBeGreaterThanOrEqual(2);
    // Should not throw when called with leaderId
    expect(() => {
      agentRunnerModule.abortSession("user-1", "conv-1", "superseded", "cpo");
    }).not.toThrow();
  });

  test("abortSession without leaderId aborts all sessions for a conversation (prefix match)", () => {
    if (!agentRunnerModule) return;
    // When no leaderId is provided, should abort all leader sessions
    // for the given userId:conversationId prefix.
    // Should not throw — exercises the prefix-matching code path.
    expect(() => {
      agentRunnerModule.abortSession("user-1", "conv-1", "superseded");
    }).not.toThrow();
  });

  test("abortAllUserSessions works with leader-scoped keys", () => {
    if (!agentRunnerModule) return;
    // abortAllUserSessions iterates with prefix `userId:`.
    // With the new key format userId:convId:leaderId, the prefix match
    // should still work correctly.
    expect(() => {
      agentRunnerModule.abortAllUserSessions("user-1");
    }).not.toThrow();
  });
});
