import { describe, test, expect, vi, beforeEach } from "vitest";

// GET /api/crm/contacts (feat-beta-crm-ui #6172):
//  - 200 { contacts: [board-shaped] } for the authenticated owner
//  - 401 when unauthenticated
//  - 502 { error: "contacts_query_error" } on query error, PII-free body +
//    a synthetic Sentry mirror that carries NO third-party PII (AC5)

const { mockGetUser, mockFrom, mockCaptureException } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockFrom: vi.fn(),
  mockCaptureException: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@sentry/nextjs", () => ({ captureException: mockCaptureException }));

import { GET } from "@/app/api/crm/contacts/route";

// A chainable + thenable query stub: select()/order() chain; awaiting resolves
// to the configured { data, error }.
function queryResult(result: { data: unknown; error: unknown }) {
  const chain: Record<string, unknown> = {};
  chain.select = () => chain;
  chain.order = () => chain;
  chain.then = (res: (v: unknown) => unknown, rej: (e: unknown) => unknown) =>
    Promise.resolve(result).then(res, rej);
  return chain;
}

beforeEach(() => {
  mockGetUser.mockReset();
  mockFrom.mockReset();
  mockCaptureException.mockReset();
});

describe("GET /api/crm/contacts", () => {
  test("401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("200 returns board-shaped contacts (drops user_id/source/next_action)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockFrom.mockReturnValue(
      queryResult({
        data: [
          {
            id: "c1",
            user_id: "u1",
            name: "Priya Raman",
            company: "Northwind Labs",
            role: "Founder",
            source: "referral",
            stage: "new",
            next_action: "call",
            next_action_date: null,
            last_contact: "2026-07-06",
            amount: 2400,
            currency: "USD",
            amount_basis: "hypothetical_acv",
            expected_close_date: null,
            created_at: "2026-07-01T00:00:00Z",
            updated_at: "2026-07-06T00:00:00Z",
          },
        ],
        error: null,
      }),
    );

    const res = await GET();
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({
      contacts: [
        {
          id: "c1",
          company: "Northwind Labs",
          name: "Priya Raman",
          role: "Founder",
          stage: "new",
          amount: 2400,
          currency: "USD",
          last_contact: "2026-07-06",
        },
      ],
    });
    // The board shape must NOT include PII-adjacent internal columns.
    expect(body.contacts[0]).not.toHaveProperty("user_id");
    expect(body.contacts[0]).not.toHaveProperty("source");
    expect(body.contacts[0]).not.toHaveProperty("next_action");
  });

  test("502 + PII-free body + PII-free Sentry mirror on query error (AC5)", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockFrom.mockReturnValue(
      queryResult({
        data: null,
        // A PostgrestError carrying third-party PII in details/message.
        error: {
          code: "42P01",
          message: "relation for Acme Corp missing",
          details: "Failing row contains (Priya Raman, Northwind Labs, secret)",
        },
      }),
    );

    const res = await GET();
    expect(res.status).toBe(502);
    const body = await res.json();
    expect(body).toEqual({ error: "contacts_query_error" });

    // The whole serialized Sentry call must contain no PII from the PG error.
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const [errArg, ctxArg] = mockCaptureException.mock.calls[0];
    const serialized = JSON.stringify({
      msg: (errArg as Error).message,
      ctx: ctxArg,
    });
    expect(serialized).not.toMatch(/Priya|Northwind|Acme|Failing row|secret/);
    expect(errArg).toBeInstanceOf(Error);
    expect((errArg as Error).message).toBe("crm-contacts:42P01");
    expect(ctxArg).toEqual({
      tags: { surface: "crm-contacts" },
      extra: { op: "list", userId: "u1", code: "42P01" },
    });
  });
});
