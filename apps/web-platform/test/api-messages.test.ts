import { describe, test, expect, vi, beforeEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";
import type { IncomingMessage, ServerResponse } from "http";

// ---------------------------------------------------------------------------
// Mocks — vi.hoisted ensures these are available when vi.mock factories run
// ---------------------------------------------------------------------------

const { mockGetUser, mockFrom } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
}));

// Module-scope createServiceClient() — mock must be wired in factory
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

import { handleConversationMessages } from "@/server/api-messages";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeReq(token?: string): IncomingMessage {
  return {
    headers: token
      ? { authorization: `Bearer ${token}` }
      : {},
  } as unknown as IncomingMessage;
}

function makeRes(): ServerResponse & { _status: number; _body: string } {
  const res = {
    _status: 0,
    _body: "",
    writeHead(status: number) {
      res._status = status;
      return res;
    },
    end(body?: string) {
      res._body = body ?? "";
    },
  } as unknown as ServerResponse & { _status: number; _body: string };
  return res;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("handleConversationMessages", () => {
  const CONV_ID = "conv-abc-123";
  const USER_ID = "user-xyz";

  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("response includes cost fields from conversation row", async () => {
    // Auth succeeds
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID } },
      error: null,
    });

    // First from("conversations") call — ownership check returns cost fields
    const convChain = mockQueryChain({
      id: CONV_ID,
      total_cost_usd: "0.004200",  // NUMERIC(12,6) returns string
      input_tokens: 1200,
      output_tokens: 300,
    });

    // Second from("messages") call — returns messages
    const msgChain = mockQueryChain([
      { id: "msg-1", role: "user", content: "hello", leader_id: null, created_at: "2026-01-01" },
    ]);

    mockFrom.mockImplementation((table: string) => {
      if (table === "conversations") return convChain;
      if (table === "messages") return msgChain;
      return mockQueryChain(null);
    });

    const req = makeReq("valid-token");
    const res = makeRes();

    await handleConversationMessages(req, res, CONV_ID);

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);

    // These assertions will FAIL until the handler includes cost fields
    expect(body).toHaveProperty("totalCostUsd", 0.0042);
    expect(body).toHaveProperty("inputTokens", 1200);
    expect(body).toHaveProperty("outputTokens", 300);
    expect(body.messages).toHaveLength(1);
  });

  test("response includes workflowEndedAt when the conversation has it (review F3 #2886)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID } },
      error: null,
    });

    const convChain = mockQueryChain({
      id: CONV_ID,
      total_cost_usd: "0",
      input_tokens: 0,
      output_tokens: 0,
      workflow_ended_at: "2026-04-27T12:00:00Z",
    });
    const msgChain = mockQueryChain([]);
    mockFrom.mockImplementation((table: string) => {
      if (table === "conversations") return convChain;
      if (table === "messages") return msgChain;
      return mockQueryChain(null);
    });

    const req = makeReq("valid-token");
    const res = makeRes();

    await handleConversationMessages(req, res, CONV_ID);

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);
    expect(body.workflowEndedAt).toBe("2026-04-27T12:00:00Z");
  });

  test("workflowEndedAt is null when the conversation has not ended (review F3 #2886)", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID } },
      error: null,
    });

    const convChain = mockQueryChain({
      id: CONV_ID,
      total_cost_usd: "0",
      input_tokens: 0,
      output_tokens: 0,
      workflow_ended_at: null,
    });
    const msgChain = mockQueryChain([]);
    mockFrom.mockImplementation((table: string) => {
      if (table === "conversations") return convChain;
      if (table === "messages") return msgChain;
      return mockQueryChain(null);
    });

    const req = makeReq("valid-token");
    const res = makeRes();

    await handleConversationMessages(req, res, CONV_ID);

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);
    expect(body.workflowEndedAt).toBeNull();
  });

  test("cost fields default to zero when conversation has no cost data", async () => {
    mockGetUser.mockResolvedValue({
      data: { user: { id: USER_ID } },
      error: null,
    });

    const convChain = mockQueryChain({
      id: CONV_ID,
      total_cost_usd: null,
      input_tokens: null,
      output_tokens: null,
    });

    const msgChain = mockQueryChain([]);

    mockFrom.mockImplementation((table: string) => {
      if (table === "conversations") return convChain;
      if (table === "messages") return msgChain;
      return mockQueryChain(null);
    });

    const req = makeReq("valid-token");
    const res = makeRes();

    await handleConversationMessages(req, res, CONV_ID);

    expect(res._status).toBe(200);
    const body = JSON.parse(res._body);

    expect(body.totalCostUsd).toBe(0);
    expect(body.inputTokens).toBe(0);
    expect(body.outputTokens).toBe(0);
  });
});
