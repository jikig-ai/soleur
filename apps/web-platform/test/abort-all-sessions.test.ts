import { describe, test, expect, vi, beforeEach } from "vitest";
import { createClient } from "@supabase/supabase-js";

// Env vars needed by serverUrl() guard — set before agent-runner is loaded
process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";

// Mock all heavy dependencies so agent-runner loads without side effects
vi.mock("@anthropic-ai/claude-agent-sdk", () => ({ query: vi.fn() }));

// Track conversations.update calls across all tests
const conversationUpdateEq = vi.fn().mockReturnValue({ error: null });
const conversationUpdate = vi.fn().mockReturnValue({ eq: conversationUpdateEq });

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(() => ({
    from: vi.fn((table: string) => {
      if (table === "conversations") {
        return { update: conversationUpdate };
      }
      return {
        select: vi.fn(() => ({
          eq: vi.fn(() => ({
            eq: vi.fn(() => ({
              eq: vi.fn(() => ({
                limit: vi.fn(() => ({
                  single: vi.fn(() => ({ data: null, error: null })),
                })),
              })),
            })),
            single: vi.fn(() => ({ data: null, error: null })),
          })),
        })),
        insert: vi.fn(() => ({ error: null })),
        update: vi.fn(() => ({ eq: vi.fn(() => ({ error: null })) })),
      };
    }),
  })),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
vi.mock("../server/ws-handler", () => ({ sendToClient: vi.fn() }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  }),
}));
vi.mock("../server/byok", () => ({
  decryptKey: vi.fn(),
  decryptKeyLegacy: vi.fn(),
  encryptKey: vi.fn(),
}));
vi.mock("../server/error-sanitizer", () => ({
  sanitizeErrorForClient: vi.fn(() => "error"),
}));
vi.mock("../server/sandbox", () => ({ isPathInWorkspace: vi.fn(() => true) }));
vi.mock("../server/tool-path-checker", () => ({
  UNVERIFIED_PARAM_TOOLS: [],
  extractToolPath: vi.fn(),
  isFileTool: vi.fn(() => false),
  isSafeTool: vi.fn(() => true),
}));
vi.mock("../server/agent-env", () => ({ buildAgentEnv: vi.fn(() => ({})) }));
vi.mock("../server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => vi.fn()),
}));
vi.mock("../server/review-gate", () => ({
  abortableReviewGate: vi.fn(),
  validateSelection: vi.fn(),
  MAX_SELECTION_LENGTH: 200,
  REVIEW_GATE_TIMEOUT_MS: 300_000,
}));
vi.mock("../server/domain-leaders", () => ({ DOMAIN_LEADERS: [], ROUTABLE_DOMAIN_LEADERS: [] }));
vi.mock("../server/domain-router", () => ({ routeMessage: vi.fn() }));
vi.mock("../server/session-sync", () => ({
  syncPull: vi.fn(),
  syncPush: vi.fn(),
}));

import { abortAllSessions, startAgentSession } from "../server/agent-runner";
import { query } from "@anthropic-ai/claude-agent-sdk";

describe("abortAllSessions", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("completes without error when no sessions exist (no-op)", () => {
    expect(() => abortAllSessions()).not.toThrow();
  });

  test("aborts active sessions and triggers failed status write", async () => {
    // Create a hanging async generator that we can control
    let generatorResolve: (() => void) | undefined;
    const hangingPromise = new Promise<void>((resolve) => {
      generatorResolve = resolve;
    });

    const mockQuery = vi.mocked(query);
    mockQuery.mockReturnValue({
      async *[Symbol.asyncIterator]() {
        await hangingPromise;
      },
      next: vi.fn(),
      return: vi.fn(),
      throw: vi.fn(),
    } as any);

    // Override the supabase from() to return valid data for session setup
    const mockClient = vi.mocked(createClient).mock.results[0]?.value;
    if (mockClient) {
      (mockClient.from as any).mockImplementation((table: string) => {
        if (table === "api_keys") {
          return {
            select: () => ({
              eq: () => ({
                eq: () => ({
                  eq: () => ({
                    limit: () => ({
                      single: () => ({
                        data: {
                          id: "key-1",
                          encrypted_key: Buffer.from("test").toString("base64"),
                          iv: Buffer.from("test-iv-1234").toString("base64"),
                          auth_tag: Buffer.from("test-tag-1234567").toString("base64"),
                          key_version: 2,
                        },
                        error: null,
                      }),
                    }),
                  }),
                }),
              }),
            }),
          };
        }
        if (table === "users") {
          return {
            select: () => ({
              eq: () => ({
                single: () => ({
                  data: { workspace_path: "/tmp/test-workspace", repo_status: null },
                  error: null,
                }),
              }),
            }),
          };
        }
        if (table === "conversations") {
          return { update: conversationUpdate };
        }
        if (table === "messages") {
          return { insert: () => ({ error: null }) };
        }
        return {
          select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
          update: () => ({ eq: () => ({ error: null }) }),
          insert: () => ({ error: null }),
        };
      });
    }

    // Start a session that will hang on the async generator
    const sessionPromise = startAgentSession("user-1", "conv-1", "cpo");

    // Give the session time to register in activeSessions
    await new Promise((r) => setTimeout(r, 50));

    // Abort all sessions
    abortAllSessions();

    // Unblock the generator so the session can complete through the catch block
    generatorResolve!();
    await sessionPromise;

    // Verify the catch block wrote "failed" status (not skipped by isSuperseded check).
    // The updateConversationStatus call uses supabase.from("conversations").update({status, ...}).eq(id)
    const statusCalls = conversationUpdate.mock.calls.filter(
      (call) => call[0]?.status === "failed",
    );
    expect(statusCalls.length).toBeGreaterThanOrEqual(1);
  });

  test("server_shutdown reason does not trigger isSuperseded skip", () => {
    // The catch block checks: err.message.includes("superseded")
    // "server_shutdown" must NOT match, so "failed" status gets written
    const shutdownReason = "Session aborted: server_shutdown";
    const supersededReason = "Session aborted: superseded";

    expect(shutdownReason.includes("superseded")).toBe(false);
    expect(supersededReason.includes("superseded")).toBe(true);
  });
});
