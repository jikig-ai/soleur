import { describe, it, expect, vi, beforeEach } from "vitest";
import type { IncomingMessage, ServerResponse } from "http";

const mockGetUser = vi.fn();
const mockFromConversations = vi.fn();
const mockFromMessages = vi.fn();

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    auth: { getUser: mockGetUser },
    from: (table: string) =>
      table === "conversations" ? mockFromConversations() : mockFromMessages(),
  }),
}));

const mockReportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => mockReportSilentFallback(...args),
}));

const mockAddBreadcrumb = vi.fn();
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: (...args: unknown[]) => mockAddBreadcrumb(...args),
}));

function makeReq(authHeader?: string): IncomingMessage {
  return {
    headers: { authorization: authHeader },
  } as unknown as IncomingMessage;
}

function makeRes(): ServerResponse & { _status: number; _body: string } {
  let status = 0;
  let body = "";
  return {
    writeHead: (s: number) => {
      status = s;
    },
    end: (b?: string) => {
      body = b ?? "";
    },
    get _status() {
      return status;
    },
    get _body() {
      return body;
    },
  } as unknown as ServerResponse & { _status: number; _body: string };
}

describe("handleConversationMessages — observability + auth + ownership", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns 401 + reports silent fallback when Authorization header is missing", async () => {
    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq(undefined);
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-1");

    expect(res._status).toBe(401);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "kb-chat",
        op: expect.stringContaining("missing-auth"),
        extra: expect.objectContaining({ conversationId: "conv-1" }),
      }),
    );
  });

  it("returns 401 + reports silent fallback when token is invalid", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: { message: "bad" } });
    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer bad");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-1");

    expect(res._status).toBe(401);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({
        feature: "kb-chat",
        op: expect.stringContaining("invalid-token"),
      }),
    );
  });

  it("returns 404 + reports silent fallback when conversation is not owned by user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
    mockFromConversations.mockReturnValue({
      select: () => ({
        eq: () => ({
          eq: () => ({
            single: async () => ({ data: null, error: null }),
          }),
        }),
      }),
    });

    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer ok");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-other-owner");

    expect(res._status).toBe(404);
    // When `.single()` returns no row with a null error (RLS-filtered or
    // genuinely missing), the handler still mirrors with a null `err` arg —
    // `expect.anything()` does not match null per vitest's matcher contract.
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "kb-chat",
        op: expect.stringContaining("not-owned-or-missing"),
        extra: expect.objectContaining({ conversationId: "conv-other-owner" }),
      }),
    );
  });

  it("returns 200 + adds Sentry breadcrumb on success path with non-empty messages", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
    mockFromConversations.mockReturnValue({
      select: () => ({
        eq: () => ({
          eq: () => ({
            single: async () => ({
              data: {
                id: "conv-1",
                total_cost_usd: 0,
                input_tokens: 0,
                output_tokens: 0,
                workflow_ended_at: null,
              },
              error: null,
            }),
          }),
        }),
      }),
    });
    mockFromMessages.mockReturnValue({
      select: () => ({
        eq: () => ({
          order: async () => ({
            data: [
              { id: "m-1", role: "user", content: "hi", leader_id: null, created_at: "t1" },
              { id: "m-2", role: "assistant", content: "hello", leader_id: "cto", created_at: "t2" },
            ],
            error: null,
          }),
        }),
      }),
    });

    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer ok");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-1");

    expect(res._status).toBe(200);
    expect(mockAddBreadcrumb).toHaveBeenCalledWith(
      expect.objectContaining({
        category: "kb-chat",
        message: "history-fetch-success",
        data: expect.objectContaining({ conversationId: "conv-1", count: 2 }),
      }),
    );
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("returns 200 with empty messages array when row exists but has no messages (NOT 404)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
    mockFromConversations.mockReturnValue({
      select: () => ({
        eq: () => ({
          eq: () => ({
            single: async () => ({
              data: {
                id: "conv-empty",
                total_cost_usd: 0,
                input_tokens: 0,
                output_tokens: 0,
                workflow_ended_at: null,
              },
              error: null,
            }),
          }),
        }),
      }),
    });
    mockFromMessages.mockReturnValue({
      select: () => ({
        eq: () => ({
          order: async () => ({ data: [], error: null }),
        }),
      }),
    });

    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer ok");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-empty");

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);
    expect(body.messages).toEqual([]);
    expect(mockAddBreadcrumb).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ conversationId: "conv-empty", count: 0 }),
      }),
    );
  });
});
