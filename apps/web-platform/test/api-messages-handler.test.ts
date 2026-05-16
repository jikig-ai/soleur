import { describe, it, expect, vi, beforeEach } from "vitest";
import type { IncomingMessage, ServerResponse } from "http";
import { mockQueryChain } from "./helpers/mock-supabase";

const { mockGetUser, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  }),
}));

const { mockReportSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

const { mockAddBreadcrumb } = vi.hoisted(() => ({
  mockAddBreadcrumb: vi.fn(),
}));
vi.mock("@sentry/nextjs", () => ({
  addBreadcrumb: mockAddBreadcrumb,
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

const conversationRow = {
  id: "conv-1",
  total_cost_usd: 0,
  input_tokens: 0,
  output_tokens: 0,
  workflow_ended_at: null,
};

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
    mockFrom.mockReturnValue(mockQueryChain(null));

    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer ok");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-other-owner");

    expect(res._status).toBe(404);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "kb-chat",
        op: expect.stringContaining("not-owned-or-missing"),
        extra: expect.objectContaining({ conversationId: "conv-other-owner" }),
      }),
    );
  });

  it("returns 200 with non-empty messages — no Sentry breadcrumb (gated to empty-only)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
    // First call: conversations row lookup. Second call: messages list.
    mockFrom
      .mockReturnValueOnce(mockQueryChain(conversationRow))
      .mockReturnValueOnce(
        mockQueryChain([
          { id: "m-1", role: "user", content: "hi", leader_id: null, created_at: "t1" },
          { id: "m-2", role: "assistant", content: "hello", leader_id: "cto", created_at: "t2" },
        ]),
      );

    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer ok");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-1");

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);
    expect(body.messages).toHaveLength(2);
    // Breadcrumb is gated on count===0 to avoid burning the 100-entry buffer
    // on every successful fetch. Non-empty success path should NOT breadcrumb.
    expect(mockAddBreadcrumb).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("returns 200 with empty messages — adds H1-diagnostic Sentry breadcrumb", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "user-1" } }, error: null });
    mockFrom
      .mockReturnValueOnce(mockQueryChain({ ...conversationRow, id: "conv-empty" }))
      .mockReturnValueOnce(mockQueryChain([]));

    const { handleConversationMessages } = await import("@/server/api-messages");
    const req = makeReq("Bearer ok");
    const res = makeRes();

    await handleConversationMessages(req, res, "conv-empty");

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);
    expect(body.messages).toEqual([]);
    expect(mockAddBreadcrumb).toHaveBeenCalledWith(
      expect.objectContaining({
        category: "kb-chat",
        message: "history-fetch-success-empty",
        data: expect.objectContaining({ conversationId: "conv-empty", count: 0 }),
      }),
    );
  });
});
