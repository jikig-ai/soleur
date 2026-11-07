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
  /** The message_id the approval row belongs to; the lookup only finds it when the route asks for exactly that id. */
  approvalFor?: string;
  /** Successive approval lookups (the second is the post-archive race recheck); defaults to [approval, null]. */
  approvals?: Array<{ id: string } | null>;
  /** The messages.status read made once an approval exists: a status string, or null for "no such row". */
  messageStatus?: string | null;
  statusError?: { message: string } | null;
  /** An error returned by the post-archive recheck only (the second approval lookup). */
  recheckError?: { message: string } | null;
}

function wire({
  row = { id: MSG },
  error = null,
  approval = null,
  approvalError = null,
  approvalFor = MSG,
  approvals,
  messageStatus = "draft",
  statusError = null,
  recheckError = null,
}: Wiring = {}) {
  const queue = approvals ?? [approval, null];
  let lookups = 0;
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
    maybeSingle: async () => {
      // The status read made after an approval was found selects "status"; the update selects "id".
      if (calls.select === "status") {
        return { data: messageStatus === null ? null : { status: messageStatus }, error: statusError };
      }
      return { data: row, error };
    },
  };
  const approvalFilters: Array<[string, unknown]> = [];
  const approvalChain = {
    eq(col: string, val: unknown) {
      approvalFilters.push([col, val]);
      return approvalChain;
    },
    // Like the real table: the approval is found only for the message and user it belongs to.
    maybeSingle: async () => {
      const f = Object.fromEntries(approvalFilters);
      const hit = f.message_id === approvalFor && f.user_id === FOUNDER;
      const n = lookups++;
      const found = queue[Math.min(n, queue.length - 1)] ?? null;
      approvalFilters.length = 0;
      return { data: hit ? found : null, error: n >= 1 ? (recheckError ?? approvalError) : approvalError };
    },
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

  test("an approval row but the message is already archived (sent in another tab): 403 forbidden, not the 409", async () => {
    const calls = wire({ approval: { id: "as-1" }, messageStatus: "archived" });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(403);
    expect(await res.json()).toEqual({ error: "forbidden" });
    expect(calls.update).toBeUndefined();
  });

  test("an approval row and the message row is gone: 403 forbidden", async () => {
    wire({ approval: { id: "as-1" }, messageStatus: null });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(403);
  });

  test("an approval row and the status read fails: fail closed 500, mirrored to Sentry", async () => {
    const calls = wire({ approval: { id: "as-1" }, statusError: { message: "boom" } });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(500);
    expect(mockReport.mock.calls[0][1]).toMatchObject({ feature: "dashboard-discard", op: "messages-status-lookup" });
    expect(calls.update).toBeUndefined();
  });

  test("a Send raced this Discard (an approval row appears after the archive): still 200, reported as discard-send-race", async () => {
    wire({ approvals: [null, { id: "as-late" }] });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(200);
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({ feature: "dashboard-discard", op: "discard-send-race" });
  });

  test("the post-archive recheck itself failing is reported and does not change the 200", async () => {
    wire({ recheckError: { message: "boom" } });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(200);
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({
      op: "discard-send-race",
      message: "Post-archive approval recheck failed",
    });
  });

  test("an approval that belongs to a DIFFERENT message does not block this discard (the lookup is scoped by message_id)", async () => {
    const calls = wire({ approval: { id: "as-1" }, approvalFor: "22222222-2222-4222-bbbb-222222222222" });
    const res = await POST(req(), ctx());
    expect(res.status).toBe(200);
    expect(calls.update).toEqual({ status: "archived" });
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
