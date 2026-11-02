// #11599 — behavioural test of the ws-handler `startAgentSession(...).catch` (legacy first-message path): a lease refusal
// for an unresolvable authentication mode sends the typed frame and adds NO call-site error-tracker event. The mock
// harness is the one of ws-deferred-creation.test.ts. Synthesized ids only.
import { describe, it, expect, vi, beforeEach } from "vitest";
import { WebSocket } from "ws";

// Track Supabase calls
const mockInsert = vi.fn().mockResolvedValue({ error: null });
// A chainable thenable: the dispatch path filters an UPDATE with more than one `.eq()` (ws-deferred-creation only needs one).
// biome-ignore lint/suspicious/noExplicitAny: test mock chain
const mockUpdateEq: any = vi.fn(() => {
  // biome-ignore lint/suspicious/noExplicitAny: test mock chain
  const p: any = Promise.resolve({ error: null });
  p.eq = mockUpdateEq;
  p.in = mockUpdateEq;
  return p;
});
const mockUpdate = vi.fn().mockReturnValue({ eq: mockUpdateEq });
const mockSelectSingle = vi.fn().mockResolvedValue({
  data: { id: "conv-1", status: "active" },
  error: null,
});
// Lazy-evaluated `users.repo_url` lets individual tests simulate a
// disconnected user (repo_url=null) to exercise the abort path.
let mockUserRepoUrl: string | null = "https://github.com/acme/repo";

const { mockRpc, mockStartAgentSession, mockCaptureException, mockLogInfo, mockLogError } = vi.hoisted(() => ({
  mockStartAgentSession: vi.fn(),
  mockCaptureException: vi.fn(),
  mockLogInfo: vi.fn(),
  mockLogError: vi.fn(),
  mockRpc: vi.fn((name: string, args?: Record<string, unknown>) => Promise.resolve(
    name === "bind_agent_engine_run"
      ? {
          data: {
            binding: {
              workspaceId: String(args?.p_workspace_id ?? "ws-mock-workspace-1"),
              execution: { kind: "conversation", conversationId: String(args?.p_conversation_id ?? "conv-1") },
              engineId: "claude-code",
              authMode: "managed",
              adapterVersion: "claude-code-v1",
              boundAt: new Date().toISOString(),
            },
          },
          error: null,
        }
      : {
          data: [{ status: "ok", active_count: 1, effective_cap: 2 }],
          error: null,
        },
  )),
}));

// Pin TC_VERSION so the mock row's tc_accepted_version stays in lockstep
// with recheckTcMidSession. Insulates this test from future TC_VERSION
// bumps (the bump PR would otherwise need to touch unrelated WS tests).
vi.mock("@/lib/legal/tc-version", () => ({
  TC_VERSION: "1.0.0",
  TC_DOCUMENT_SHA:
    "79b2d2c00136cfcd1e61cb7ee9654aeb2b80cf21f2b2d33d1f063f10948d9300",
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "users") {
        // `users` reads go through .select().eq().maybeSingle() to fetch
        // repo_url so conversation inserts can be scoped to the current repo.
        // Return shape is evaluated at call time so individual tests can
        // simulate the disconnected state via `mockUserRepoUrl = null`.
        //
        // NOT migrated to `test/mocks/supabase-query-builder.ts`: this
        // inline `chain` is a predicate-aware recursive mock that
        // `start_session` tests rely on for `.eq()` predicate inspection.
        // The shared `buildSupabaseQueryBuilder` serves non-predicate-aware
        // cases. See plan
        // `2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
        // §Non-Goals / R5 for the deliberate carve-out.
        const chain = {
          select: vi.fn(() => chain),
          eq: vi.fn(() => chain),
          maybeSingle: vi.fn(async () => ({
            data: { repo_url: mockUserRepoUrl },
            error: null,
          })),
          // recheckTcMidSession (feat-oauth-tc-consent-3205) reads
          // tc_accepted_version via .single() on every gated inbound
          // message. Return the current TC_VERSION so the mid-session
          // re-check passes; tests that want to exercise the close
          // branch override .single via mockReturnValueOnce.
          single: vi.fn(async () => ({
            data: { tc_accepted_version: "1.0.0", repo_url: mockUserRepoUrl },
            error: null,
          })),
        };
        return chain;
      }
      const convChain: Record<string, unknown> = {
        insert: mockInsert,
        update: mockUpdate,
      };
      const eqChain: Record<string, unknown> = {};
      eqChain.eq = vi.fn(() => eqChain);
      eqChain.single = mockSelectSingle;
      convChain.select = vi.fn(() => eqChain);
      return convChain;
    },
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    rpc: mockRpc,
  }),
}));

// PR-C §2.10 (#3244): ws-handler now mints tenant clients via
// `getFreshTenantClient`. Reuse the same dispatcher shape from the
// service mock — `users` chain serves both `repo_url` reads and the
// auth-probe (`.maybeSingle()` returns non-error).
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({
    from: (table: string) => {
      if (table === "users") {
        const chain: { select: unknown; eq: unknown; maybeSingle: unknown } = {
          select: vi.fn(() => chain),
          eq: vi.fn(() => chain),
          maybeSingle: vi.fn(async () => ({
            data: { id: "user-1", repo_url: mockUserRepoUrl },
            error: null,
          })),
        };
        return chain;
      }
      if (table === "workspaces") {
        // ADR-044 read-cutover: getCurrentRepoUrl reads workspaces.repo_url.
        const chain: { select: unknown; eq: unknown; maybeSingle: unknown } = {
          select: vi.fn(() => chain),
          eq: vi.fn(() => chain),
          maybeSingle: vi.fn(async () => ({
            data: { repo_url: mockUserRepoUrl },
            error: null,
          })),
        };
        return chain;
      }
      if (table === "user_session_state") {
        // resolveCurrentWorkspaceId: null claim → solo workspace fallback.
        const chain: { select: unknown; eq: unknown; maybeSingle: unknown } = {
          select: vi.fn(() => chain),
          eq: vi.fn(() => chain),
          maybeSingle: vi.fn(async () => ({
            data: { current_workspace_id: null },
            error: null,
          })),
        };
        return chain;
      }
      const convChain: Record<string, unknown> = {
        insert: mockInsert,
        update: mockUpdate,
      };
      const eqChain: Record<string, unknown> = {};
      eqChain.eq = vi.fn(() => eqChain);
      eqChain.single = mockSelectSingle;
      convChain.select = vi.fn(() => eqChain);
      return convChain;
    },
    rpc: mockRpc,
  })),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/agent-runner", () => ({
  startAgentSession: mockStartAgentSession,
  sendUserMessage: vi.fn().mockResolvedValue(undefined),
  resolveReviewGate: vi.fn().mockResolvedValue(undefined),
  abortSession: vi.fn(),
}));

// The sanctioned conversations-write wrapper is not under test here.
vi.mock("@/server/conversation-writer", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/conversation-writer")>();
  return { ...actual, updateConversationFor: vi.fn().mockResolvedValue({ ok: true }) };
});

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: vi.fn(),
  addBreadcrumb: vi.fn(),
}));

vi.mock("@/server/error-sanitizer", () => ({
  sanitizeErrorForClient: (err: Error) => err.message,
}));

vi.mock("@/server/logger", () => ({
  default: { info: mockLogInfo, debug: vi.fn(), warn: vi.fn(), error: mockLogError },
  createChildLogger: () => ({
    info: mockLogInfo,
    debug: vi.fn(),
    warn: vi.fn(),
    error: mockLogError,
  }),
}));

vi.mock("./rate-limiter", () => ({
  connectionThrottle: { isAllowed: () => true },
  sessionThrottle: { isAllowed: () => true },
  pendingConnections: { add: () => true, remove: () => {}, get: () => 0 },
  extractClientIp: () => "127.0.0.1",
  logRateLimitRejection: vi.fn(),
}));

vi.mock("./context-validation", () => ({
  validateConversationContext: (ctx: unknown) => ctx,
}));

vi.mock("@/server/agent-session-registry", async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>();
  return {
    ...actual,
    getUserWorkspace: vi.fn(() => "ws-mock-workspace-1"),
    // AC4 (#5240): consumers now resolve the workspace binding durably via
    // resolveUserWorkspaceBinding (Map → DB rehydrate) rather than reading the
    // raw Map. Stub it to the fixed workspace so the deferred-creation flow
    // under test is decoupled from workspace resolution (covered by
    // durable-workspace-binding-resolver.test.ts).
    resolveUserWorkspaceBinding: vi.fn(async () => "ws-mock-workspace-1"),
  };
});

import { handleMessage, sessions, type ClientSession } from "@/server/ws-handler";

/** Create a fake WS that captures sent messages. */
function createMockSession(): { session: ClientSession; sent: unknown[] } {
  const sent: unknown[] = [];
  const ws = {
    readyState: WebSocket.OPEN,
    send: (data: string) => sent.push(JSON.parse(data)),
    ping: vi.fn(),
    close: vi.fn(),
  } as unknown as WebSocket;
  const session: ClientSession = { ws, lastActivity: Date.now() };
  return { session, sent };
}


import { ByokLeaseError } from "@/server/byok-lease";
import { authModeUnresolvedFrame } from "@/server/agent-auth-user-message";

async function firstChat(rejection: unknown) {
  mockStartAgentSession.mockRejectedValue(rejection);
  const { session, sent } = createMockSession();
  sessions.set("user-1", session);
  // Every session started over the wire is routed to Concierge (`soleur_go_pending`); the legacy first-message branch
  // is reached by a session whose pending routing is `legacy`, so that state is set directly.
  session.pending = { id: "00000000-0000-4000-8000-0000000000c1", leaderId: "cto", routing: { kind: "legacy" } } as ClientSession["pending"];
  await handleMessage("user-1", JSON.stringify({ type: "chat", content: "Set up Stripe webhooks" }));
  await vi.waitFor(() => expect(mockStartAgentSession).toHaveBeenCalled());
  return sent as Array<{ type: string; errorCode?: string; message?: string }>;
}

describe("ws-handler startAgentSession catch — lease refusals (#11599)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    sessions.clear();
    mockUserRepoUrl = "https://github.com/acme/repo";
  });

  it.each(["auth_mode_unresolved", "auth_mode_unavailable"] as const)(
    "%s: exactly one typed error frame, zero call-site Sentry captures, INFO not ERROR",
    async (cause) => {
      const sent = await firstChat(new ByokLeaseError(cause, "Authentication unavailable; retry shortly", cause === "auth_mode_unresolved" ? "unbound" : "read_failed"));
      await vi.waitFor(() => expect(sent.filter((m) => m.type === "error")).toHaveLength(1));
      expect(sent.filter((m) => m.type === "error")[0]).toEqual(authModeUnresolvedFrame(cause));
      expect(mockCaptureException).not.toHaveBeenCalled();
      expect(mockLogError).not.toHaveBeenCalled();
    },
  );

  it("positive control (the spy is live): a non-lease error IS captured, logged at ERROR and sent as a generic frame", async () => {
    const sent = await firstChat(new Error("boom"));
    await vi.waitFor(() => expect(mockCaptureException).toHaveBeenCalledTimes(1));
    expect(sent.filter((m) => m.type === "error")[0]?.errorCode).toBeUndefined();
    expect(mockLogError).toHaveBeenCalled();
  });

  it("a real fetch_failed is still mirrored and still sent as the generic frame (never a typed auth-mode frame)", async () => {
    const sent = await firstChat(new ByokLeaseError("fetch_failed", "boom"));
    await vi.waitFor(() => expect(mockCaptureException).toHaveBeenCalledTimes(1));
    expect(sent.filter((m) => m.type === "error")[0]?.errorCode ?? "").not.toMatch(/^auth_mode_/);
  });
});
