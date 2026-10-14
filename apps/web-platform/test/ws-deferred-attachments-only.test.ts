/**
 * #9297 D2: an attachments-only FIRST message on a pending (deferred) session
 * materializes the conversation. Models the seams of
 * `ws-handler-cc-session-id-wiring.test.ts` (absolute-resolving
 * `vi.mock("../server/...")` for agent-runner + cc-dispatcher, FULL
 * `@sentry/nextjs` mock), NOT `ws-deferred-creation.test.ts` (whose relative
 * `./agent-runner` mocks resolve under test/ and are no-ops).
 *
 * `createConversation` is module-private: it is observed via `mockInsert`
 * (the `conversations` insert) and `session.conversationId`.
 */
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key";

import { describe, it, expect, vi, beforeEach } from "vitest";
import { WebSocket } from "ws";

const USER_ID = "user-1";
const PENDING_ID = "0a1b2c3d-4e5f-4a6b-8c7d-9e0f1a2b3c4d";
const OTHER_CONV_ID = "1b2c3d4e-5f6a-4b7c-8d9e-0f1a2b3c4d5e";

const {
  mockDispatchSoleurGo,
  mockSendUserMessage,
  mockStartAgentSession,
  mockReportSilentFallback,
  mockInsert,
  mockRpc,
  mockExistingRow,
} = vi.hoisted(() => ({
  mockDispatchSoleurGo: vi.fn().mockResolvedValue(undefined),
  mockSendUserMessage: vi.fn().mockResolvedValue(undefined),
  mockStartAgentSession: vi.fn().mockResolvedValue(undefined),
  mockReportSilentFallback: vi.fn(),
  mockInsert: vi.fn().mockResolvedValue({ error: null }),
  mockRpc: vi.fn((name: string, args?: Record<string, unknown>) =>
    Promise.resolve(
      name === "bind_agent_engine_run"
        ? {
            data: {
              binding: {
                workspaceId: String(args?.p_workspace_id ?? "ws-mock-workspace-1"),
                execution: {
                  kind: "conversation",
                  conversationId: String(args?.p_conversation_id ?? "conv-1"),
                },
                engineId: "claude-code",
                authMode: "managed",
                adapterVersion: "claude-code-v1",
                boundAt: new Date().toISOString(),
              },
            },
            error: null,
          }
        : { data: [{ status: "ok", active_count: 1, effective_cap: 2 }], error: null },
    ),
  ),
  // The row the two-tab 23505 fallback resolves to (set per test).
  mockExistingRow: { current: null as null | Record<string, unknown> },
}));

vi.mock("@/lib/legal/tc-version", () => ({
  TC_VERSION: "1.0.0",
  TC_DOCUMENT_SHA: "79b2d2c00136cfcd1e61cb7ee9654aeb2b80cf21f2b2d33d1f063f10948d9300",
}));

/** Recursive thenable-less chain: every builder method returns the chain. */
function makeConversationsChain() {
  const chain: Record<string, unknown> = {
    insert: mockInsert,
    update: vi.fn(() => chain),
  };
  for (const m of ["select", "eq", "is", "order", "limit", "neq", "in"]) {
    chain[m] = vi.fn(() => chain);
  }
  chain.single = vi.fn(async () => ({
    data: { id: "conv-1", status: "active" },
    error: null,
  }));
  chain.maybeSingle = vi.fn(async () => ({ data: mockExistingRow.current, error: null }));
  return chain;
}

function makeUsersChain() {
  const chain: Record<string, unknown> = {};
  chain.select = vi.fn(() => chain);
  chain.eq = vi.fn(() => chain);
  chain.maybeSingle = vi.fn(async () => ({
    data: { id: USER_ID, repo_url: "https://github.com/acme/repo" },
    error: null,
  }));
  chain.single = vi.fn(async () => ({
    data: { tc_accepted_version: "1.0.0", repo_url: "https://github.com/acme/repo" },
    error: null,
  }));
  return chain;
}

function tableChain(table: string) {
  if (table === "users") return makeUsersChain();
  if (table === "workspaces") {
    const chain: Record<string, unknown> = {};
    chain.select = vi.fn(() => chain);
    chain.eq = vi.fn(() => chain);
    chain.maybeSingle = vi.fn(async () => ({
      data: { repo_url: "https://github.com/acme/repo" },
      error: null,
    }));
    return chain;
  }
  if (table === "user_session_state") {
    const chain: Record<string, unknown> = {};
    chain.select = vi.fn(() => chain);
    chain.eq = vi.fn(() => chain);
    chain.maybeSingle = vi.fn(async () => ({
      data: { current_workspace_id: null },
      error: null,
    }));
    return chain;
  }
  return makeConversationsChain();
}

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => tableChain(table),
    auth: { getUser: vi.fn().mockResolvedValue({ data: { user: { id: USER_ID } }, error: null }) },
    rpc: mockRpc,
  }),
  serverUrl: "https://test.supabase.co",
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({
    from: (table: string) => tableChain(table),
    rpc: mockRpc,
  })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("../server/cc-dispatcher", async () => {
  const actual = await vi.importActual<typeof import("../server/cc-dispatcher")>(
    "../server/cc-dispatcher",
  );
  return {
    ...actual,
    dispatchSoleurGo: mockDispatchSoleurGo,
    hasActiveCcQuery: () => false,
    resolveConciergeDocumentContext: async () => ({}),
  };
});

vi.mock("@/server/conversation-writer", async () => {
  const actual = await vi.importActual<typeof import("@/server/conversation-writer")>(
    "@/server/conversation-writer",
  );
  return { ...actual, updateConversationFor: vi.fn().mockResolvedValue({ ok: true }) };
});

vi.mock("../server/agent-runner", () => ({
  startAgentSession: mockStartAgentSession,
  sendUserMessage: mockSendUserMessage,
  resolveReviewGate: vi.fn(),
  abortSession: vi.fn(),
}));

// FULL Sentry mock: a partial mock makes the real dispatcher throw into the
// chat catch, so positives go red and negatives green for the wrong reason.
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: vi.fn(),
  captureMessage: vi.fn(),
  captureException: vi.fn(),
}));

vi.mock("@/server/observability", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/observability")>();
  return {
    ...actual,
    reportSilentFallback: mockReportSilentFallback,
    warnSilentFallback: vi.fn(),
  };
});

// The two-tab 23505 fallback re-validates the EXISTING row's engine binding via
// an RPC this harness does not model; the guard itself is not under test here.
vi.mock("../server/agent-engine-route-guard", async (importOriginal) => {
  const actual = await importOriginal<typeof import("../server/agent-engine-route-guard")>();
  return { ...actual, assertLegacyConversationEngineBinding: vi.fn().mockResolvedValue(undefined) };
});

vi.mock("@/server/agent-session-registry", async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>();
  return {
    ...actual,
    getUserWorkspace: vi.fn(() => "ws-mock-workspace-1"),
    resolveUserWorkspaceBinding: vi.fn(async () => "ws-mock-workspace-1"),
  };
});

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";

type Sent = Array<Record<string, unknown>>;

function createPendingSession(
  pendingOverrides: Partial<NonNullable<ClientSession["pending"]>> = {},
): { session: ClientSession; sent: Sent } {
  const sent: Sent = [];
  const ws = {
    readyState: WebSocket.OPEN,
    send: (data: string) => sent.push(JSON.parse(data)),
    ping: vi.fn(),
    close: vi.fn(),
  } as unknown as WebSocket;
  const session: ClientSession = {
    ws,
    lastActivity: Date.now(),
    pending: { id: PENDING_ID, routing: { kind: "soleur_go_pending" }, ...pendingOverrides },
  };
  sessions.set(USER_ID, session);
  return { session, sent };
}

/** `chatSchema` is a strictObject: fixtures carry exactly these four keys. */
function att(storagePath: string, filename = "notes.md", contentType = "text/markdown") {
  return { storagePath, filename, contentType, sizeBytes: 12 };
}
const validAtt = () => att(`${USER_ID}/${PENDING_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.md`);

async function sendChat(content: string, attachments?: unknown[]) {
  await handleMessage(
    USER_ID,
    JSON.stringify({ type: "chat", content, ...(attachments ? { attachments } : {}) }),
  );
}

const errorFrames = (sent: Sent) => sent.filter((m) => m.type === "error");

beforeEach(() => {
  vi.clearAllMocks();
  sessions.clear();
  mockExistingRow.current = null;
  mockInsert.mockResolvedValue({ error: null });
  mockDispatchSoleurGo.mockResolvedValue(undefined);
});

describe("pending-session first message: attachments-only (#9297 D2)", () => {
  // CONTROL (passes before the fix): proves the seam. "hi" + attachments
  // reaches dispatch, so the RED cases below fail on the guard, not the harness.
  it("control: text + attachments materializes and dispatches (soleur-go)", async () => {
    const { session, sent } = createPendingSession();
    const a = validAtt();

    await sendChat("hi", [a]);

    expect(errorFrames(sent)).toEqual([]);
    expect(mockInsert).toHaveBeenCalledTimes(1);
    expect(session.conversationId).toBe(PENDING_ID);
    expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    const args = mockDispatchSoleurGo.mock.calls[0]![0] as {
      userMessage: string;
      attachments: unknown[];
    };
    expect(args.userMessage).toBe("hi");
    expect(args.attachments).toEqual([a]);
  });

  it("empty content + one valid attachment materializes and dispatches '' + the attachments (soleur-go)", async () => {
    const { session, sent } = createPendingSession();
    const a = validAtt();

    await sendChat("", [a]);

    expect(errorFrames(sent).map((e) => e.message)).not.toContainEqual(
      expect.stringContaining("Please include a message"),
    );
    expect(mockInsert).toHaveBeenCalledTimes(1);
    expect(session.conversationId).toBe(PENDING_ID);
    expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    const args = mockDispatchSoleurGo.mock.calls[0]![0] as {
      userMessage: string;
      attachments: unknown[];
    };
    expect(args.userMessage).toBe("");
    expect(args.attachments).toEqual([a]);
  });

  // The legacy-leader branch is unreachable end to end (start_session always
  // sets soleur-go pending routing), so this stays a unit-level test only.
  it("legacy branch (no pending routing): empty content + attachment reaches sendUserMessage('')", async () => {
    const { session, sent } = createPendingSession({ routing: undefined });
    const a = validAtt();

    await sendChat("", [a]);

    expect(errorFrames(sent)).toEqual([]);
    expect(mockInsert).toHaveBeenCalledTimes(1);
    expect(mockSendUserMessage).toHaveBeenCalledWith(USER_ID, PENDING_ID, "", undefined, [a]);
    expect(mockDispatchSoleurGo).not.toHaveBeenCalled();
    expect(session.conversationId).toBe(PENDING_ID);
  });

  it("'@cto ' + attachments materializes (positive: stripped-empty text but files present)", async () => {
    const { session, sent } = createPendingSession();

    await sendChat("@cto ", [validAtt()]);

    expect(errorFrames(sent)).toEqual([]);
    expect(mockInsert).toHaveBeenCalledTimes(1);
    expect(session.conversationId).toBe(PENDING_ID);
    expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
  });

  describe("still rejected (negative space)", () => {
    function expectRejected(sent: Sent, session: ClientSession, text: RegExp) {
      const errors = errorFrames(sent);
      expect(errors).toHaveLength(1);
      expect(String(errors[0]!.message)).toMatch(text);
      expect(mockInsert).not.toHaveBeenCalled();
      expect(mockDispatchSoleurGo).not.toHaveBeenCalled();
      expect(mockSendUserMessage).not.toHaveBeenCalled();
      expect(session.conversationId).toBeUndefined();
      expect(session.pending?.id).toBe(PENDING_ID);
    }

    it("empty content + attachments: [] (an empty array is truthy, never test !msg.attachments)", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", []);
      expectRejected(sent, session, /Please include a message/);
    });

    it("empty content and NO attachments", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("");
      expectRejected(sent, session, /Please include a message/);
    });

    it("'@cto ' and NO attachments", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("@cto ");
      expectRejected(sent, session, /Please include a message/);
    });

    it("empty content + an attachment under ANOTHER conversation's prefix creates no row", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [att(`${USER_ID}/${OTHER_CONV_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });

    it("empty content + an attachment under ANOTHER user's prefix creates no row", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [att(`user-2/${PENDING_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });

    it("empty content + a '..' traversal attachment creates no row", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [att(`${USER_ID}/${PENDING_ID}/../x/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });

    it("empty content + an unsupported-type attachment creates no row", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [
        att(`${USER_ID}/${PENDING_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.exe`, "virus.exe", "application/x-msdownload"),
      ]);
      expectRejected(sent, session, /not supported/i);
    });

    it("a SIBLING-folder prefix (`<pending>x/`) is rejected (trailing slash is part of the prefix)", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [att(`${USER_ID}/${PENDING_ID}x/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });

    it("pre-validation also applies under LEGACY routing (no pending routing)", async () => {
      const { session, sent } = createPendingSession({ routing: undefined });
      await sendChat("", [att(`user-2/${PENDING_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
      expect(mockStartAgentSession).not.toHaveBeenCalled();
    });

    it("an extension-mismatched ref (right prefix + type, wrong suffix) is rejected BEFORE createConversation", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [att(`${USER_ID}/${PENDING_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.png`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });

    it("text PRESENT + a forged ref creates no conversation row and no message (reconnect re-mint)", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("hello", [att(`${USER_ID}/${OTHER_CONV_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });

    it("text PRESENT + a bad ref AFTER a good one rejects the whole message under LEGACY routing too", async () => {
      const { session, sent } = createPendingSession({ routing: undefined });
      await sendChat("hello", [validAtt(), att(`${USER_ID}/${PENDING_ID}/../x/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
      expect(mockStartAgentSession).not.toHaveBeenCalled();
    });

    it("one bad ref among good ones rejects the whole message", async () => {
      const { session, sent } = createPendingSession();
      await sendChat("", [validAtt(), att(`user-2/${PENDING_ID}/0f0e0d0c-0b0a-4908-8706-050403020100.md`)]);
      expectRejected(sent, session, /attachment could not be found/i);
    });
  });

  describe("id divergence (two-tab context_path 23505 fallback)", () => {
    const CONTEXT_PATH = "knowledge-base/project/plans/some-plan.md";

    function forceContextPathConflict() {
      mockInsert.mockResolvedValue({
        error: {
          code: "23505",
          message: "duplicate key value violates unique constraint",
          constraint: "conversations_context_path_user_uniq",
        },
      });
      mockExistingRow.current = {
        id: OTHER_CONV_ID,
        active_workflow: "soleur_go_pending",
        context_path: CONTEXT_PATH,
        engine_binding_state: "bound",
      };
    }

    const divergedCalls = () =>
      mockReportSilentFallback.mock.calls.filter(
        (c) => (c[1] as { op?: string } | undefined)?.op === "attachments-pending-id-diverged",
      );

    it("resolvedId !== pendingId with attachments is captured AND fails closed (error frame, no dispatch, no message insert)", async () => {
      const { session, sent } = createPendingSession({ contextPath: CONTEXT_PATH });
      forceContextPathConflict();

      await sendChat("", [validAtt()]);

      expect(divergedCalls()).toHaveLength(1);
      expect(divergedCalls()[0]![0]).toBeNull();
      expect(divergedCalls()[0]![1]).toEqual(
        expect.objectContaining({
          extra: expect.objectContaining({
            pendingId: PENDING_ID,
            resolvedId: OTHER_CONV_ID,
            attachmentCount: 1,
          }),
        }),
      );
      const errors = errorFrames(sent);
      expect(errors).toHaveLength(1);
      expect(String(errors[0]!.message)).toMatch(/attachment could not be found/i);
      // Only the (conflicting) conversations insert ran: no messages insert.
      expect(mockInsert).toHaveBeenCalledTimes(1);
      expect(mockDispatchSoleurGo).not.toHaveBeenCalled();
      expect(mockSendUserMessage).not.toHaveBeenCalled();
      expect(mockStartAgentSession).not.toHaveBeenCalled();
    });

    it("resolvedId !== pendingId WITHOUT attachments is not captured and still proceeds", async () => {
      const { session } = createPendingSession({ contextPath: CONTEXT_PATH });
      forceContextPathConflict();

      await sendChat("hello");

      expect(session.conversationId).toBe(OTHER_CONV_ID);
      expect(divergedCalls()).toHaveLength(0);
      expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    });

    it("resolvedId === pendingId with attachments is not captured", async () => {
      createPendingSession();

      await sendChat("", [validAtt()]);

      expect(divergedCalls()).toHaveLength(0);
      expect(mockDispatchSoleurGo).toHaveBeenCalledTimes(1);
    });
  });
});
