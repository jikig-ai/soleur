/**
 * #11569 — POST /api/dashboard/today/[id]/discard archives the caller's own draft.
 *
 * The route had no test while the messages UPDATE policy did not exist (every call matched zero rows and answered
 * 403). Migration 181 makes the update land, so the route's contract is pinned here: 200 with the archived id, a
 * zero-row result is 403 `forbidden`, a database error is 500 with a Sentry mirror, an unauthenticated caller is 401,
 * and the UPDATE carries the `user_id` and `status = draft` filters the policy's USING clause relies on.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const { mockGetUser, mockFrom, mockValidateOrigin, mockReport } = vi.hoisted(
  () => ({
    mockGetUser: vi.fn(),
    mockFrom: vi.fn(),
    mockValidateOrigin: vi.fn(() => ({
      valid: true,
      origin: "https://app.soleur.ai",
    })),
    mockReport: vi.fn(),
  }),
);

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockFrom,
  })),
}));

vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  hashUserId: vi.fn(() => "founder-hash-stub"),
}));

import { POST } from "@/app/api/dashboard/today/[id]/discard/route";

const FOUNDER = "aaaaaaaa-aaaa-4aaa-aaaa-aaaaaaaaaaaa";
const MSG = "11111111-1111-4111-aaaa-111111111111";

function req(): Request {
  return new Request(`https://app.soleur.ai/api/dashboard/today/${MSG}/discard`, {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
  });
}
const ctx = () => ({ params: Promise.resolve({ id: MSG }) });

interface Wiring {
  row?: { id: string } | null;
  error?: { message: string } | null;
  approval?: { id: string } | null;
  approvalError?: { message: string } | null;
}

function wire({
  row = { id: MSG },
  error = null,
  approval = null,
  approvalError = null,
}: Wiring = {}) {
  const calls = {
    table: "" as string,
    update: undefined as unknown,
    select: undefined as string | undefined,
    filters: [] as Array<[string, unknown]>,
  };
  const chain = {
    update(patch: unknown) {
      calls.update = patch;
      return chain;
    },
    eq(col: string, val: unknown) {
      calls.filters.push([col, val]);
      return chain;
    },
    select(cols: string) {
      calls.select = cols;
      return chain;
    },
    maybeSingle: async () => ({ data: row, error }),
  };
  const approvalChain = {
    eq: () => approvalChain,
    maybeSingle: async () => ({ data: approval, error: approvalError }),
  };
  mockFrom.mockImplementation((table: string) => {
    if (table === "action_sends") return { select: () => approvalChain };
    calls.table = table;
    return chain;
  });
  return calls;
}

beforeEach(() => {
  vi.clearAllMocks();
  mockValidateOrigin.mockReturnValue({ valid: true, origin: "https://app.soleur.ai" });
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER } }, error: null });
});

describe("POST /api/dashboard/today/[id]/discard", () => {
  test("archives the caller's draft: 200 with the id and archived status", async () => {
    wire();
    const res = await POST(req(), ctx());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ id: MSG, status: "archived" });
    expect(mockReport).not.toHaveBeenCalled();
  });

  test("the UPDATE writes status archived on messages, filtered by id, user_id and status draft, and reads the row back", async () => {
    const calls = wire();
    await POST(req(), ctx());
    expect(calls.table).toBe("messages");
    expect(calls.update).toEqual({ status: "archived" });
    // As a set: the order of the .eq calls is not behaviour.
    expect([...calls.filters].sort()).toEqual(
      [["id", MSG], ["status", "draft"], ["user_id", FOUNDER]].sort(),
    );
    // Without .select() PostgREST returns no row, so every successful discard would answer 403 (the #11569 symptom).
    expect(calls.select).toBe("id");
  });

  test("zero rows matched (a draft the caller does not own, or already handled): 403 forbidden, no Sentry noise", async () => {
    wire({ row: null });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "forbidden" });
    expect(mockReport).not.toHaveBeenCalled();
  });

  test("a database error: 500 internal_error, mirrored to Sentry with the route op", async () => {
    wire({ row: null, error: { message: "permission denied for table messages" } });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(500);
    expect(await res.json()).toEqual({ error: "internal_error" });
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({
      feature: "dashboard-discard",
      op: "messages-archive",
    });
  });

  test("a draft that already has an approval row: 409 draft_already_approved, nothing archived", async () => {
    const calls = wire({ approval: { id: "as-1" } });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(409);
    expect(await res.json()).toEqual({ error: "draft_already_approved", message_id: MSG });
    expect(calls.update).toBeUndefined();
  });

  test("an approval lookup error fails closed: 500, mirrored to Sentry, nothing archived", async () => {
    const calls = wire({ approvalError: { message: "boom" } });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(500);
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({
      feature: "dashboard-discard",
      op: "action-sends-lookup",
    });
    expect(calls.update).toBeUndefined();
  });

  test("unauthenticated: 401 and no UPDATE is attempted", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null }, error: null });
    const calls = wire();
    const res = await POST(req(), ctx());
    expect(res.status).toBe(401);
    expect(calls.update).toBeUndefined();
  });

  test("a cross-origin request is refused before any database call", async () => {
    mockValidateOrigin.mockReturnValue({ valid: false, origin: "https://evil.example" });
    const calls = wire();
    const res = await POST(req(), ctx());
    expect(res.status).toBe(403);
    expect(calls.update).toBeUndefined();
  });
});
