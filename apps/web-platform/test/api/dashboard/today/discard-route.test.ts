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
}

function wire({ row = { id: MSG }, error = null }: Wiring = {}) {
  const calls = {
    table: "" as string,
    update: undefined as unknown,
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
    select: () => chain,
    maybeSingle: async () => ({ data: row, error }),
  };
  mockFrom.mockImplementation((table: string) => {
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

  test("the UPDATE writes status archived on messages, filtered by id, user_id and status draft", async () => {
    const calls = wire();
    await POST(req(), ctx());
    expect(calls.table).toBe("messages");
    expect(calls.update).toEqual({ status: "archived" });
    expect(calls.filters).toEqual([
      ["id", MSG],
      ["user_id", FOUNDER],
      ["status", "draft"],
    ]);
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
