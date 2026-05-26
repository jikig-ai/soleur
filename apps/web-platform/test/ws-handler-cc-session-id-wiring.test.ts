/**
 * RED tests for issue #3266 Phase 2 — ws-handler threads the persisted
 * `conversations.session_id` through to `dispatchSoleurGo` on the
 * cc-soleur-go chat path. This activates the dormant prefill guard on the
 * cc path post-restart by ensuring the runner's cold-Query construction
 * receives the persisted session_id.
 *
 * Tested via the exported `dispatchSoleurGoForConversation` helper (the
 * single call site for the cc dispatch through-line).
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";

const { mockDispatchSoleurGo, mockUpdateConversationFor } = vi.hoisted(() => ({
  mockDispatchSoleurGo: vi.fn().mockResolvedValue(undefined),
  mockUpdateConversationFor: vi.fn().mockResolvedValue({ ok: true }),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: vi.fn(),
    auth: { getUser: vi.fn() },
  }),
  serverUrl: "https://test.supabase.co",
}));

// PR-C §2.10 (#3244): import-only stub. This test mocks conversation-
// writer directly so the tenant code path is not exercised.
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: vi.fn() })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("../server/cc-dispatcher", async () => {
  const actual = await vi.importActual<
    typeof import("../server/cc-dispatcher")
  >("../server/cc-dispatcher");
  return {
    ...actual,
    dispatchSoleurGo: mockDispatchSoleurGo,
    hasActiveCcQuery: () => false,
    resolveConciergeDocumentContext: async () => ({}),
  };
});

vi.mock("@/server/conversation-writer", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/conversation-writer")
  >("@/server/conversation-writer");
  return {
    ...actual,
    updateConversationFor: mockUpdateConversationFor,
  };
});

vi.mock("../server/agent-runner", () => ({
  startAgentSession: vi.fn(),
  sendUserMessage: vi.fn(),
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  captureException: vi.fn(),
}));

import { dispatchSoleurGoForConversation } from "../server/ws-handler";

beforeEach(() => {
  mockDispatchSoleurGo.mockClear();
  mockUpdateConversationFor.mockClear();
  mockUpdateConversationFor.mockResolvedValue({ ok: true });
});

describe("dispatchSoleurGoForConversation — sessionId forwarding (#3266 Phase 2)", () => {
  it("forwards a non-null sessionId to dispatchSoleurGo", async () => {
    await dispatchSoleurGoForConversation(
      "u1",
      "conv-1",
      "hi",
      { kind: "soleur_go_active", workflow: "brainstorm" },
      undefined,
      undefined,
      "sess-X",
    );

    expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    const args = mockDispatchSoleurGo.mock.calls[0]![0] as {
      sessionId?: string | null;
      userId: string;
      conversationId: string;
    };
    expect(args.sessionId).toBe("sess-X");
    expect(args.userId).toBe("u1");
    expect(args.conversationId).toBe("conv-1");
  });

  it("forwards a null sessionId (fresh conversation) without converting to undefined", async () => {
    await dispatchSoleurGoForConversation(
      "u1",
      "conv-2",
      "hi",
      { kind: "soleur_go_pending" },
      undefined,
      undefined,
      null,
    );

    expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    const args = mockDispatchSoleurGo.mock.calls[0]![0] as {
      sessionId?: string | null;
    };
    expect(args.sessionId).toBeNull();
  });

  it("forwards undefined sessionId when caller omits it (back-compat)", async () => {
    await dispatchSoleurGoForConversation(
      "u1",
      "conv-3",
      "hi",
      { kind: "soleur_go_pending" },
    );

    expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    const args = mockDispatchSoleurGo.mock.calls[0]![0] as {
      sessionId?: string | null;
    };
    expect(args.sessionId).toBeUndefined();
  });
});
